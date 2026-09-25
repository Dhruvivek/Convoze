import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import jwt from 'jsonwebtoken';
import request from 'supertest';

import { E2E_TEST_EVENT } from '../src/e2e/routes.js';
import { signIn } from './support/auth.js';
import { connect, nextEvent, startTestServer, timedOut, waitFor } from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

describe('realtime handshake', () => {
  it('accepts a valid access token in the auth payload', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);

    const socket = await connect(server.client({ auth: { token: accessToken } }));

    assert.equal(socket.connected, true);
  });

  async function assertRejected(client) {
    await assert.rejects(connect(client), { message: 'unauthenticated' });
  }

  it('rejects a handshake without a token', async () => {
    server = await startTestServer({ prisma });

    await assertRejected(server.client());
    await assertRejected(server.client({ auth: {} }));
  });

  it('rejects a malformed or forged token', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);
    const forged = jwt.sign(jwt.decode(accessToken), 'someone-elses-secret');

    await assertRejected(server.client({ auth: { token: 'not-a-jwt' } }));
    await assertRejected(server.client({ auth: { token: forged } }));
    await assertRejected(server.client({ auth: { token: 42 } }));
  });

  it('rejects an expired token', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);

    server.clock.advance(15 * 60 * 1000);

    await assertRejected(server.client({ auth: { token: accessToken } }));
  });

  it("rejects a token whose Session is revoked", async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);
    await prisma.session.updateMany({ data: { revokedAt: new Date() } });

    await assertRejected(server.client({ auth: { token: accessToken } }));
  });

  it('ignores a token sent in the query string', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);

    await assertRejected(server.client({ query: { token: accessToken } }));
  });

  it('keeps a connected socket open once its token is past its 15 minutes', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app);
    const socket = await connect(server.client({ auth: { token: accessToken } }));

    server.clock.advance(60 * 60 * 1000);

    assert.equal(await nextEvent(socket, 'disconnect', 300), timedOut);
    assert.equal(socket.connected, true);
  });
});

describe('realtime rooms', () => {
  const ALICE = '+14155550100';
  const BOB = '+14155550101';
  const CAROL = '+14155550102';

  function seedConversation(participantPhoneNumbers, type = 'group') {
    return request(server.app)
      .post('/__e2e__/conversations')
      .send({ type, participantPhoneNumbers });
  }

  async function emitTo(room, payload) {
    const res = await request(server.app).post('/__e2e__/emit').send({ room, payload });
    assert.equal(res.status, 204);
  }

  async function connectAs(phoneNumber) {
    const { accessToken, user } = await signIn(server.app, { phoneNumber });
    const socket = await connect(server.client({ auth: { token: accessToken } }));
    return { socket, userId: user.id };
  }

  it('joins a socket to the rooms of the Conversations it participates in, and no others', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const shared = await seedConversation([ALICE, BOB]);
    const notAlices = await seedConversation([BOB, CAROL]);
    const alice = await connectAs(ALICE);

    const received = nextEvent(alice.socket, E2E_TEST_EVENT);
    await emitTo(`conversation:${shared.body.id}`, { n: 1 });
    assert.deepEqual(await received, { n: 1 });

    const missed = nextEvent(alice.socket, E2E_TEST_EVENT);
    await emitTo(`conversation:${notAlices.body.id}`, { n: 2 });
    assert.equal(await missed, timedOut);
  });

  it("joins a socket to its own user's personal room, and not to anyone else's", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    const received = nextEvent(alice.socket, E2E_TEST_EVENT);
    await emitTo(`user:${alice.userId}`, { n: 1 });
    assert.deepEqual(await received, { n: 1 });

    const missed = nextEvent(alice.socket, E2E_TEST_EVENT);
    await emitTo(`user:${bob.userId}`, { n: 2 });
    assert.equal(await missed, timedOut);
  });

  it('seeds a Conversation between the given phone numbers, creating their Users', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const { user: alice } = await signIn(server.app, { phoneNumber: ALICE });

    const res = await seedConversation([ALICE, BOB], 'direct');

    assert.equal(res.status, 201);
    const bob = res.body.participants.find((p) => p.phoneNumber === BOB);
    assert.deepEqual(
      res.body.participants.map((p) => p.phoneNumber).sort(),
      [ALICE, BOB],
    );
    assert.equal(res.body.participants.find((p) => p.phoneNumber === ALICE).userId, alice.id);
    const { user: signedInBob } = await signIn(server.app, { phoneNumber: BOB });
    assert.equal(signedInBob.id, bob.userId);
  });

  it('rejects an invalid Conversation to seed', async () => {
    server = await startTestServer({ prisma, e2eMode: true });

    const noParticipants = await seedConversation([]);
    const badType = await seedConversation([ALICE, BOB], 'channel');
    const directOfThree = await seedConversation([ALICE, BOB, CAROL], 'direct');
    const badNumber = await seedConversation(['not a number']);

    for (const res of [noParticipants, badType, directOfThree, badNumber]) {
      assert.equal(res.status, 400);
      assert.equal(res.body.error.code, 'invalid_request');
    }
  });

  it('rejects an invalid test event to emit', async () => {
    server = await startTestServer({ prisma, e2eMode: true });

    const res = await request(server.app).post('/__e2e__/emit').send({ payload: {} });

    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'invalid_request');
  });
});

describe('e2e live-connection endpoints', () => {
  function socketCount(sessionId) {
    return request(server.app).get(`/__e2e__/sessions/${sessionId}/sockets`);
  }

  it("counts a Session's live sockets", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const { accessToken } = await signIn(server.app);
    const { sessionId } = jwt.decode(accessToken);
    const first = await connect(server.client({ auth: { token: accessToken } }));
    await connect(server.client({ auth: { token: accessToken } }));

    assert.deepEqual((await socketCount(sessionId)).body, { count: 2 });

    first.disconnect();
    await waitFor(async () => (await socketCount(sessionId)).body.count === 1);
  });

  it('reset closes every live socket', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const { accessToken } = await signIn(server.app);
    const socket = await connect(server.client({ auth: { token: accessToken } }));

    const disconnected = nextEvent(socket, 'disconnect');
    await request(server.app).post('/__e2e__/reset');

    assert.equal(await disconnected, 'io server disconnect');
  });
});
