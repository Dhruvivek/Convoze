import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { writeUpdates } from '../src/messaging/updateWriter.js';
import { signIn } from './support/auth.js';
import { createConversation, createUser } from './support/messaging.js';
import {
  collectBatches,
  connect,
  nextEvent,
  startTestServer,
  timedOut,
} from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

const ALICE = '+14155550100';

async function joinedUpdate(userId, conversationId) {
  return writeUpdates(prisma, [
    { userId, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId },
  ]);
}

describe('sync handshake', () => {
  it('resets a first-ever connect (no since) and starts the pump from the current seq', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE });
    const socket = server.client({ auth: { token: accessToken } });
    const reset = nextEvent(socket, 'sync:reset', 5000);
    const caughtUp = nextEvent(socket, 'sync:caught-up', 5000);

    await connect(socket);

    assert.deepEqual(await reset, { currentSeq: 0 });
    assert.deepEqual(await caughtUp, { seq: 0 });
  });

  it('resumes from `since` without a reset when nothing has been pruned', async () => {
    server = await startTestServer({ prisma });
    const alice = await createUser(prisma, { phoneNumber: ALICE });
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });
    await joinedUpdate(alice.id, conversation.id);
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE });

    const socket = server.client({ auth: { token: accessToken, since: 1 } });
    const reset = nextEvent(socket, 'sync:reset', 300);
    const caughtUp = nextEvent(socket, 'sync:caught-up', 5000);

    await connect(socket);

    assert.equal(await reset, timedOut);
    assert.deepEqual(await caughtUp, { seq: 1 });
  });

  it('resets when `since` is ahead of the User\'s lastSeq', async () => {
    server = await startTestServer({ prisma });
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE });

    const socket = server.client({ auth: { token: accessToken, since: 999 } });
    const reset = nextEvent(socket, 'sync:reset', 5000);

    await connect(socket);

    assert.deepEqual(await reset, { currentSeq: 0 });
  });

  it('resets when `since` is older than the oldest retained Update', async () => {
    server = await startTestServer({ prisma });
    const alice = await createUser(prisma, { phoneNumber: ALICE });
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });
    await joinedUpdate(alice.id, conversation.id);
    await joinedUpdate(alice.id, conversation.id);
    await joinedUpdate(alice.id, conversation.id);
    // Simulates retention having pruned the first two Updates.
    await prisma.userUpdate.deleteMany({ where: { userId: alice.id, seq: { lt: 3 } } });
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE });

    const socket = server.client({ auth: { token: accessToken, since: 0 } });
    const reset = nextEvent(socket, 'sync:reset', 5000);

    await connect(socket);

    assert.deepEqual(await reset, { currentSeq: 3 });
  });
});

describe('the pump', () => {
  it('drains retained Updates in seq order, then emits sync:caught-up', async () => {
    server = await startTestServer({ prisma });
    const alice = await createUser(prisma, { phoneNumber: ALICE });
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });
    await joinedUpdate(alice.id, conversation.id);
    await joinedUpdate(alice.id, conversation.id);
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE });

    const socket = server.client({ auth: { token: accessToken, since: 0 } });
    const batches = collectBatches(socket);
    const caughtUp = nextEvent(socket, 'sync:caught-up', 5000);

    await connect(socket);
    assert.deepEqual(await caughtUp, { seq: 2 });

    assert.equal(batches.length, 1);
    assert.deepEqual(
      batches[0].updates.map((u) => u.seq),
      [1, 2],
    );
  });

  it('stops on an ack timeout, and the next connect resends the unacked batch', async () => {
    server = await startTestServer({ prisma, pumpOptions: { ackTimeoutMs: 100 } });
    const alice = await createUser(prisma, { phoneNumber: ALICE });
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });
    await joinedUpdate(alice.id, conversation.id);
    const { accessToken } = await signIn(server.app, { phoneNumber: ALICE, deviceId: 'device-1' });

    // Never acks, so the pump's emitWithAck times out.
    const firstSocket = await connect(server.client({ auth: { token: accessToken, since: 0 } }));
    await new Promise((resolve) => setTimeout(resolve, 250));

    const secondSocket = server.client({ auth: { token: accessToken, since: 0 } });
    const batches = collectBatches(secondSocket);
    const caughtUp = nextEvent(secondSocket, 'sync:caught-up', 5000);
    await connect(secondSocket);

    assert.deepEqual(await caughtUp, { seq: 1 });
    assert.deepEqual(batches[0].updates.map((u) => u.seq), [1]);
    assert.equal(firstSocket.connected, true);
  });
});
