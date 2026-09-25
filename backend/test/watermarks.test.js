import { randomUUID } from 'node:crypto';
import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import {
  collectBatches,
  connect,
  nextEvent,
  startTestServer,
  waitFor,
} from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

const ALICE = '+14155550100';
const BOB = '+14155550101';

function seedConversation(participantPhoneNumbers, type = 'group') {
  return request(server.app)
    .post('/__e2e__/conversations')
    .send({ type, participantPhoneNumbers });
}

async function connectAs(phoneNumber, deviceId) {
  const { accessToken, user } = await signIn(server.app, { phoneNumber, deviceId });
  const socket = await connect(server.client({ auth: { token: accessToken, since: 0 } }));
  const batches = collectBatches(socket);
  return { socket, userId: user.id, accessToken, batches };
}

function send(socket, payload) {
  return socket.emitWithAck('message:send', payload);
}

function read(socket, payload) {
  return socket.emitWithAck('conversation:read', payload);
}

async function sendMessage(socket, conversationId, content = 'hi') {
  return send(socket, { clientMsgId: randomUUID(), conversationId, content });
}

async function participant(conversationId, userId) {
  return prisma.participant.findUnique({ where: { conversationId_userId: { conversationId, userId } } });
}

describe('delivery watermark on ack', () => {
  it("moves the sender-visible delivery watermark to the newest message from someone else once the recipient acks", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB); // auto-acks via collectBatches
    await nextEvent(alice.socket, 'sync:caught-up', 8000);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);

    const sent = await sendMessage(alice.socket, conversation.body.id, 'hello');
    await waitFor(() => bob.batches.length > 0, 8000);

    await waitFor(async () => {
      const bobParticipant = await participant(conversation.body.id, bob.userId);
      return bobParticipant.lastDeliveredMessageId === sent.messageId;
    }, 8000);
  });

  it("doesn't move the watermark for the sender's own message.new update in the same batch", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE); // auto-acks its own batch too

    const sent = await sendMessage(alice.socket, conversation.body.id, 'hello');
    await waitFor(() => alice.batches.length > 0, 8000);
    await new Promise((resolve) => setTimeout(resolve, 200));

    const aliceParticipant = await participant(conversation.body.id, alice.userId);
    assert.notEqual(aliceParticipant.lastDeliveredMessageId, sent.messageId);
  });
});

describe('conversation:read', () => {
  it('moves both watermarks forward, and never backwards', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    const first = await sendMessage(alice.socket, conversation.body.id, 'one');
    const second = await sendMessage(alice.socket, conversation.body.id, 'two');

    const res = await read(bob.socket, { conversationId: conversation.body.id, messageId: second.messageId });
    assert.deepEqual(res, { ok: true });

    let bobParticipant = await participant(conversation.body.id, bob.userId);
    assert.equal(bobParticipant.lastReadMessageId, second.messageId);
    assert.equal(bobParticipant.lastDeliveredMessageId, second.messageId);

    // Moving to an earlier message is a no-op, not a regression.
    const backwards = await read(bob.socket, {
      conversationId: conversation.body.id,
      messageId: first.messageId,
    });
    assert.deepEqual(backwards, { ok: true });

    bobParticipant = await participant(conversation.body.id, bob.userId);
    assert.equal(bobParticipant.lastReadMessageId, second.messageId);
  });

  it('rejects a non-Participant, and a messageId from another Conversation', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const other = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const elsewhere = await sendMessage(alice.socket, other.body.id);

    const wrongConversation = await read(alice.socket, {
      conversationId: conversation.body.id,
      messageId: elsewhere.messageId,
    });
    assert.deepEqual(wrongConversation, { ok: false, code: 'FORBIDDEN' });

    const notParticipant = await read(alice.socket, {
      conversationId: randomUUID(),
      messageId: elsewhere.messageId,
    });
    assert.deepEqual(notParticipant, { ok: false, code: 'NOT_PARTICIPANT' });
  });

  it('coalesces receipts into one undrained Update, delivered when an offline Device reconnects', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE, 'alice-device-1');
    const bobOnline = await connectAs(BOB, 'bob-device-1');
    const bobOffline = await connectAs(BOB, 'bob-device-2');
    await nextEvent(bobOffline.socket, 'sync:caught-up', 8000);
    bobOffline.socket.disconnect();

    const messages = [];
    for (let i = 0; i < 5; i += 1) messages.push(await sendMessage(alice.socket, conversation.body.id, `m${i}`));

    for (const message of messages) {
      const res = await read(bobOnline.socket, { conversationId: conversation.body.id, messageId: message.messageId });
      assert.equal(res.ok, true);
    }

    const rows = await prisma.userUpdate.findMany({
      where: { userId: bobOnline.userId, kind: 'conversation.receipts' },
    });
    assert.equal(rows.length, 1);
  });

  it("wakes the mover's other Devices with the updated unreadCount", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bobDevice1 = await connectAs(BOB, 'bob-device-1');
    const bobDevice2 = await connectAs(BOB, 'bob-device-2');
    await nextEvent(bobDevice1.socket, 'sync:caught-up', 8000);
    await nextEvent(bobDevice2.socket, 'sync:caught-up', 8000);
    const sent = await sendMessage(alice.socket, conversation.body.id, 'hi');

    // Let the ack-driven delivery watermark — and the conversation.receipts
    // fan-out it triggers on its own — settle on both of Bob's Devices
    // first, so the assertion below isolates the read-driven receipt.
    await waitFor(async () => {
      const bobParticipant = await participant(conversation.body.id, bobDevice1.userId);
      return bobParticipant.lastDeliveredMessageId === sent.messageId;
    }, 8000);
    await waitFor(
      () =>
        bobDevice2.batches.flatMap((b) => b.updates).some((u) => u.kind === 'conversation.receipts'),
      8000,
    );

    const otherDeviceReceipt = nextEvent(bobDevice2.socket, 'sync:batch', 8000);
    const res = await read(bobDevice1.socket, {
      conversationId: conversation.body.id,
      messageId: sent.messageId,
    });
    assert.equal(res.ok, true);

    const payload = await otherDeviceReceipt;
    assert.equal(payload.updates[0].kind, 'conversation.receipts');
    assert.equal(payload.updates[0].payload.unreadCount, 0);
  });
});
