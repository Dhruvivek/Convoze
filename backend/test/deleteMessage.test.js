import { randomUUID } from 'node:crypto';
import { after, afterEach, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { collectBatches, connect, nextEvent, startTestServer, waitFor } from './support/realtime.js';
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

function del(socket, payload) {
  return socket.emitWithAck('message:delete', payload);
}

async function sendMessage(socket, conversationId, content = 'hi') {
  return send(socket, { clientMsgId: randomUUID(), conversationId, content });
}

describe('message:delete', () => {
  it('soft-deletes: clears content and linkPreview, writes a tombstone to every Participant', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    await nextEvent(alice.socket, 'sync:caught-up', 8000);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);
    const url = 'https://example.com/a';
    const sent = await send(alice.socket, {
      clientMsgId: randomUUID(),
      conversationId: conversation.body.id,
      content: `see ${url}`,
      linkPreview: { url, title: 'Title' },
    });

    // Delivery is decoupled from the send ack, and Bob's own ack of the
    // original message.new (via collectBatches) triggers its own
    // conversation.receipts fan-out (#49) shortly after: wait for both the
    // message and that follow-up to land on Bob before listening for the
    // delete's batch, or either one still in flight can be what the
    // listener below catches instead.
    await waitFor(() => bob.batches.some((b) => b.updates.some((u) => u.payload?.id === sent.messageId)), 8000);
    await waitFor(
      () => bob.batches.flatMap((b) => b.updates).some((u) => u.kind === 'conversation.receipts'),
      8000,
    );

    const bobBatch = nextEvent(bob.socket, 'sync:batch', 8000);
    const res = await del(alice.socket, { messageId: sent.messageId });

    assert.deepEqual(res, { ok: true });

    const message = await prisma.message.findUnique({ where: { id: sent.messageId } });
    assert.equal(message.isDeleted, true);
    assert.equal(message.content, null);
    assert.equal(message.linkPreview, null);

    const bobPayload = await bobBatch;
    assert.equal(bobPayload.updates[0].kind, 'message.deleted');
    assert.deepEqual(bobPayload.updates[0].payload, {
      id: sent.messageId,
      conversationId: conversation.body.id,
      isDeleted: true,
    });
  });

  it('is idempotent: deleting twice succeeds without writing a second Update', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    const first = await del(alice.socket, { messageId: sent.messageId });
    const second = await del(alice.socket, { messageId: sent.messageId });

    assert.deepEqual(first, { ok: true });
    assert.deepEqual(second, { ok: true });
    const deletedUpdates = await prisma.userUpdate.findMany({
      where: { kind: 'message.deleted', messageId: sent.messageId },
    });
    assert.equal(deletedUpdates.length, 2); // one per Participant (alice, bob), not duplicated
  });

  it('refuses a non-sender with FORBIDDEN', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    const res = await del(bob.socket, { messageId: sent.messageId });

    assert.deepEqual(res, { ok: false, code: 'FORBIDDEN' });
    const message = await prisma.message.findUnique({ where: { id: sent.messageId } });
    assert.equal(message.isDeleted, false);
  });

  it('returns NOT_FOUND for a Message that does not exist, and INVALID for a malformed id', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    assert.deepEqual(await del(alice.socket, { messageId: randomUUID() }), {
      ok: false,
      code: 'NOT_FOUND',
    });
    assert.deepEqual(await del(alice.socket, { messageId: 'nope' }), {
      ok: false,
      code: 'INVALID',
    });
  });
});
