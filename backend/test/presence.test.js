import { afterEach, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { connect, nextEvent, startTestServer, timedOut, waitFor } from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

// Covers #34: "online" derived from live sockets, "last seen" persisted the
// moment the last one drops, snapshot-on-connect and the audience being
// exactly "shares a Conversation with me".

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

const ALICE = '+14155550100';
const BOB = '+14155550101';
const CAROL = '+14155550102';

function seedConversation(participantPhoneNumbers, type = 'group') {
  return request(server.app)
    .post('/__e2e__/conversations')
    .send({ type, participantPhoneNumbers });
}

async function connectAs(phoneNumber, deviceId) {
  const { accessToken, user } = await signIn(server.app, { phoneNumber, deviceId });
  const socket = await connect(server.client({ auth: { token: accessToken } }));
  return { socket, userId: user.id };
}

// Like `connectAs`, but the `presenceSnapshot` listener is attached on the
// (still-disconnected) socket *before* `connect()` runs, so there's no race
// with the server sending it as part of this very connection.
async function connectCapturingSnapshot(phoneNumber, deviceId) {
  const { accessToken, user } = await signIn(server.app, { phoneNumber, deviceId });
  const socket = server.client({ auth: { token: accessToken } });
  const snapshot = new Promise((resolve) => socket.once('presenceSnapshot', resolve));
  await connect(socket);
  return { socket, userId: user.id, snapshot };
}

describe('presence: userOnline / userOffline', () => {
  it('the first socket fires userOnline to the audience only, not a bystander', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const bystander = await connectAs(CAROL);
    const bob = await connectAs(BOB);

    const bobReceived = nextEvent(bob.socket, 'userOnline');
    const bystanderMissed = nextEvent(bystander.socket, 'userOnline');
    const alice = await connectAs(ALICE);

    assert.deepEqual(await bobReceived, { userId: alice.userId });
    assert.equal(await bystanderMissed, timedOut);
  });

  it("a second Device doesn't fire a second userOnline", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const bob = await connectAs(BOB);
    await connectAs(ALICE, 'device-1');

    const missed = nextEvent(bob.socket, 'userOnline');
    await connectAs(ALICE, 'device-2');

    assert.equal(await missed, timedOut);
  });

  it('closing one of two Devices fires nothing', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const bob = await connectAs(BOB);
    const first = await connectAs(ALICE, 'device-1');
    await connectAs(ALICE, 'device-2');

    const missed = nextEvent(bob.socket, 'userOffline');
    first.socket.disconnect();

    assert.equal(await missed, timedOut);
  });

  it("closing the last Device fires userOffline with the clock's time and persists lastSeenAt", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const bob = await connectAs(BOB);
    const alice = await connectAs(ALICE);

    const offline = nextEvent(bob.socket, 'userOffline');
    alice.socket.disconnect();

    assert.deepEqual(await offline, {
      userId: alice.userId,
      lastSeenAt: server.clock.now().toISOString(),
    });
    await waitFor(async () => {
      const user = await prisma.user.findUnique({ where: { id: alice.userId } });
      return user.lastSeenAt?.getTime() === server.clock.now().getTime();
    });
  });

  it('a bystander with no shared Conversation never sees userOnline', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([BOB, CAROL]);
    const bystander = await connectAs(CAROL);

    const missed = nextEvent(bystander.socket, 'userOnline');
    await connectAs(BOB);

    assert.equal(await missed, timedOut);
  });
});

describe('presence: presenceSnapshot', () => {
  it('lists exactly the audience with correct online/lastSeenAt', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    await seedConversation([ALICE, CAROL]);
    const bob = await connectAs(BOB);
    bob.socket.disconnect();
    await waitFor(async () => {
      const user = await prisma.user.findUnique({ where: { id: bob.userId } });
      return user.lastSeenAt != null;
    });
    const carol = await connectAs(CAROL);

    const alice = await connectCapturingSnapshot(ALICE);
    const payload = await alice.snapshot;

    const byUserId = Object.fromEntries(payload.users.map((u) => [u.userId, u]));
    assert.deepEqual(Object.keys(byUserId).sort(), [bob.userId, carol.userId].sort());
    assert.deepEqual(byUserId[carol.userId], { userId: carol.userId, online: true, lastSeenAt: null });
    assert.equal(byUserId[bob.userId].online, false);
    assert.equal(byUserId[bob.userId].lastSeenAt, server.clock.now().toISOString());
  });

  it('never reveals a User with no shared Conversation', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    await signIn(server.app, { phoneNumber: CAROL, deviceId: 'carol-device' });

    const alice = await connectCapturingSnapshot(ALICE, 'alice-device');
    const snapshot = await alice.snapshot;

    const bob = await prisma.user.findUnique({ where: { phoneNumber: BOB } });
    assert.deepEqual(
      snapshot.users.map((u) => u.userId),
      [bob.id],
    );
  });

  it('is empty for a User in no Conversation at all', async () => {
    server = await startTestServer({ prisma, e2eMode: true });

    const alice = await connectCapturingSnapshot(ALICE);

    assert.deepEqual(await alice.snapshot, { users: [] });
  });
});
