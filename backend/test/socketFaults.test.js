import { randomUUID } from 'node:crypto';
import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { collectBatches, connect, startTestServer } from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

// Covers #54's socket half of "extending the existing fault-injection idea":
// rejecting the next N calls to a given socket event with a given error
// code, the way the client's Outbox drainer needs to exercise `RATE_LIMITED`
// backoff and `failed` deterministically.

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

const ALICE = '+14155550100';
const BOB = '+14155550101';

function seedConversation(participantPhoneNumbers, type = 'group') {
  return request(server.app).post('/__e2e__/conversations').send({ type, participantPhoneNumbers });
}

async function connectAs(phoneNumber) {
  const { accessToken, user } = await signIn(server.app, { phoneNumber });
  const socket = await connect(server.client({ auth: { token: accessToken, since: 0 } }));
  collectBatches(socket);
  return { socket, userId: user.id };
}

function injectSocketFault({ event, count, code }) {
  return request(server.app).post('/__e2e__/socket-faults').send({ event, count, code });
}

function send(socket, payload) {
  return socket.emitWithAck('message:send', payload);
}

function messagePayload(conversationId, overrides = {}) {
  return { clientMsgId: randomUUID(), conversationId, content: 'hi', ...overrides };
}

describe('e2e mode off', () => {
  it('does not mount the socket-faults endpoint', async () => {
    server = await startTestServer({ prisma });

    const res = await injectSocketFault({ event: 'message:send', count: 1, code: 'INVALID' });

    assert.equal(res.status, 404);
  });
});

describe('POST /__e2e__/socket-faults', () => {
  it('rejects the next N calls to the event, then lets calls through', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    const setup = await injectSocketFault({ event: 'message:send', count: 2, code: 'INVALID' });
    const first = await send(alice.socket, messagePayload(conversation.body.id));
    const second = await send(alice.socket, messagePayload(conversation.body.id));
    const third = await send(alice.socket, messagePayload(conversation.body.id));

    assert.equal(setup.status, 204);
    assert.deepEqual(first, { ok: false, code: 'INVALID' });
    assert.deepEqual(second, { ok: false, code: 'INVALID' });
    assert.equal(third.ok, true);
  });

  it('uses the given code, and a faulted send creates no Message', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const payload = messagePayload(conversation.body.id);
    await injectSocketFault({ event: 'message:send', count: 1, code: 'RATE_LIMITED' });

    const res = await send(alice.socket, payload);

    assert.deepEqual(res, { ok: false, code: 'RATE_LIMITED' });
    assert.equal(await prisma.message.count({ where: { clientMsgId: payload.clientMsgId } }), 0);
  });

  it('only affects the named event', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    await injectSocketFault({ event: 'message:edit', count: 1, code: 'INVALID' });

    const res = await send(alice.socket, messagePayload(conversation.body.id));

    assert.equal(res.ok, true);
  });

  it('rejects an invalid fault definition', async () => {
    server = await startTestServer({ prisma, e2eMode: true });

    const missingCode = await injectSocketFault({ event: 'message:send', count: 1, code: undefined });
    const badCount = await injectSocketFault({ event: 'message:send', count: 0, code: 'INVALID' });

    assert.equal(missingCode.status, 400);
    assert.equal(missingCode.body.error.code, 'invalid_request');
    assert.equal(badCount.status, 400);
  });
});

describe('POST /__e2e__/reset', () => {
  it('clears pending injected socket faults', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    await injectSocketFault({ event: 'message:send', count: 1, code: 'INVALID' });

    await request(server.app).post('/__e2e__/reset');
    // `reset` disconnects sockets (it deletes the Users); reconnect fresh.
    const conversationAfter = await seedConversation([ALICE, BOB]);
    const aliceAfter = await connectAs(ALICE);

    const res = await send(aliceAfter.socket, messagePayload(conversationAfter.body.id));

    assert.equal(res.ok, true);
  });
});
