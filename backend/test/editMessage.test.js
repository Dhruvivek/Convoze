import { randomUUID } from 'node:crypto';
import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { collectBatches, connect, nextEvent, waitFor } from './support/realtime.js';
import { startTestServer } from './support/realtime.js';
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

function edit(socket, payload) {
  return socket.emitWithAck('message:edit', payload);
}

async function sendMessage(socket, conversationId, content = 'hi') {
  return send(socket, { clientMsgId: randomUUID(), conversationId, content });
}

describe('message:edit', () => {
  it("sets editedAt and writes message.edited to every Participant, sender included", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    await nextEvent(alice.socket, 'sync:caught-up', 8000);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);
    const sent = await sendMessage(alice.socket, conversation.body.id, 'origianl');
    // Delivery is decoupled from the send ack: wait for the original
    // message.new to actually land on both Devices (drained via
    // collectBatches) before listening for the edit's batch, or the
    // still-in-flight message.new can be the one the listener below catches.
    const hasOriginal = (batches) => batches.some((b) => b.updates.some((u) => u.payload?.id === sent.messageId));
    await waitFor(() => hasOriginal(bob.batches), 8000);
    await waitFor(() => hasOriginal(alice.batches), 8000);
    // Bob's own ack of that message.new (someone else's, unlike Alice's own
    // copy) moves his delivery watermark, which triggers a
    // conversation.receipts fan-out (#49) to every Participant — Alice
    // included, so her "delivered" state stays current — shortly after:
    // wait for it on both before listening for the edit's batch, or it can
    // be what either listener below catches instead.
    const hasReceipts = (batches) => batches.flatMap((b) => b.updates).some((u) => u.kind === 'conversation.receipts');
    await waitFor(() => hasReceipts(bob.batches), 8000);
    await waitFor(() => hasReceipts(alice.batches), 8000);

    const bobBatch = nextEvent(bob.socket, 'sync:batch', 8000);
    const aliceBatch = nextEvent(alice.socket, 'sync:batch', 8000);
    const res = await edit(alice.socket, { messageId: sent.messageId, content: 'fixed typo' });

    assert.deepEqual(res, { ok: true });

    const message = await prisma.message.findUnique({ where: { id: sent.messageId } });
    assert.equal(message.content, 'fixed typo');
    assert.ok(message.editedAt);

    const bobPayload = await bobBatch;
    assert.equal(bobPayload.updates[0].kind, 'message.edited');
    assert.equal(bobPayload.updates[0].payload.content, 'fixed typo');

    const alicePayload = await aliceBatch;
    assert.equal(alicePayload.updates[0].kind, 'message.edited');
  });

  it('refuses a non-sender with FORBIDDEN', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    const res = await edit(bob.socket, { messageId: sent.messageId, content: 'hijacked' });

    assert.deepEqual(res, { ok: false, code: 'FORBIDDEN' });
    const message = await prisma.message.findUnique({ where: { id: sent.messageId } });
    assert.notEqual(message.content, 'hijacked');
  });

  it('refuses editing a deleted Message', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);
    await prisma.message.update({ where: { id: sent.messageId }, data: { isDeleted: true } });

    const res = await edit(alice.socket, { messageId: sent.messageId, content: 'still trying' });

    assert.deepEqual(res, { ok: false, code: 'FORBIDDEN' });
  });

  it('rejects empty, oversized, and malformed requests', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    assert.deepEqual(await edit(alice.socket, { messageId: sent.messageId, content: '   ' }), {
      ok: false,
      code: 'INVALID',
    });
    assert.deepEqual(
      await edit(alice.socket, { messageId: sent.messageId, content: 'x'.repeat(4097) }),
      { ok: false, code: 'TOO_LARGE' },
    );
    assert.deepEqual(await edit(alice.socket, { messageId: 'not-a-uuid', content: 'hi' }), {
      ok: false,
      code: 'INVALID',
    });
  });

  it('returns NOT_FOUND for a Message that does not exist', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    const res = await edit(alice.socket, { messageId: randomUUID(), content: 'hi' });

    assert.deepEqual(res, { ok: false, code: 'NOT_FOUND' });
  });

  it('rate limits edits alongside sends, sharing the same 30/10s budget', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    for (let i = 0; i < 29; i += 1) {
      const res = await edit(alice.socket, { messageId: sent.messageId, content: `edit ${i}` });
      assert.equal(res.ok, true, `edit ${i} should be accepted`);
    }

    const limited = await edit(alice.socket, { messageId: sent.messageId, content: 'one too many' });
    assert.deepEqual(limited, { ok: false, code: 'RATE_LIMITED' });
  });
});
