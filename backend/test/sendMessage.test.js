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

function messagePayload(conversationId, overrides = {}) {
  return { clientMsgId: randomUUID(), conversationId, content: 'hi', ...overrides };
}

describe('message:send', () => {
  it('acks {ok, messageId, createdAt}, and a retry with the same clientMsgId returns the same result', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const payload = messagePayload(conversation.body.id);

    const first = await send(alice.socket, payload);
    assert.equal(first.ok, true);
    assert.equal(typeof first.messageId, 'string');
    assert.ok(first.createdAt);

    const retry = await send(alice.socket, payload);
    assert.deepEqual(retry, first);

    const rows = await prisma.message.findMany({ where: { clientMsgId: payload.clientMsgId } });
    assert.equal(rows.length, 1);
  });

  it('rejects a sender who is not a Participant', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([BOB]);
    const alice = await connectAs(ALICE);

    const res = await send(alice.socket, messagePayload(conversation.body.id));

    assert.deepEqual(res, { ok: false, code: 'NOT_PARTICIPANT' });
  });

  it('rejects empty and oversized content', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    const empty = await send(alice.socket, messagePayload(conversation.body.id, { content: '   ' }));
    assert.deepEqual(empty, { ok: false, code: 'INVALID' });

    const tooBig = await send(
      alice.socket,
      messagePayload(conversation.body.id, { content: 'x'.repeat(4097) }),
    );
    assert.deepEqual(tooBig, { ok: false, code: 'TOO_LARGE' });
  });

  it('rejects a malformed request', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    assert.deepEqual(await send(alice.socket, {}), { ok: false, code: 'INVALID' });
    assert.deepEqual(
      await send(alice.socket, { clientMsgId: 'not-a-uuid', conversationId: conversation.body.id, content: 'hi' }),
      { ok: false, code: 'INVALID' },
    );
  });

  it('requires a replyToMessageId to exist in the same Conversation', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const other = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const original = await send(alice.socket, messagePayload(conversation.body.id));
    const elsewhere = await send(alice.socket, messagePayload(other.body.id));

    const missing = await send(
      alice.socket,
      messagePayload(conversation.body.id, { replyToMessageId: randomUUID() }),
    );
    assert.deepEqual(missing, { ok: false, code: 'NOT_FOUND' });

    const wrongConversation = await send(
      alice.socket,
      messagePayload(conversation.body.id, { replyToMessageId: elsewhere.messageId }),
    );
    assert.deepEqual(wrongConversation, { ok: false, code: 'FORBIDDEN' });

    const ok = await send(
      alice.socket,
      messagePayload(conversation.body.id, { replyToMessageId: original.messageId }),
    );
    assert.equal(ok.ok, true);
  });

  it('allows replying to a Message that was itself deleted', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const original = await send(alice.socket, messagePayload(conversation.body.id));
    await prisma.message.update({ where: { id: original.messageId }, data: { isDeleted: true } });

    const res = await send(
      alice.socket,
      messagePayload(conversation.body.id, { replyToMessageId: original.messageId }),
    );

    assert.equal(res.ok, true);
  });

  it('validates a linkPreview: an https url present in the content, and bounded title/description', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const url = 'https://example.com/article';

    const notPresent = await send(
      alice.socket,
      messagePayload(conversation.body.id, {
        content: 'no link here',
        linkPreview: { url, title: 'Title', description: 'Desc' },
      }),
    );
    assert.deepEqual(notPresent, { ok: false, code: 'INVALID' });

    const notHttps = await send(
      alice.socket,
      messagePayload(conversation.body.id, {
        content: `see http://example.com`,
        linkPreview: { url: 'http://example.com', title: 'Title' },
      }),
    );
    assert.deepEqual(notHttps, { ok: false, code: 'INVALID' });

    const titleTooLong = await send(
      alice.socket,
      messagePayload(conversation.body.id, {
        content: `see ${url}`,
        linkPreview: { url, title: 'x'.repeat(201) },
      }),
    );
    assert.deepEqual(titleTooLong, { ok: false, code: 'INVALID' });

    const ok = await send(
      alice.socket,
      messagePayload(conversation.body.id, {
        content: `see ${url}`,
        linkPreview: { url, title: 'Title', description: 'Desc' },
      }),
    );
    assert.equal(ok.ok, true);
    const message = await prisma.message.findUnique({ where: { id: ok.messageId } });
    assert.deepEqual(message.linkPreview, { url, title: 'Title', description: 'Desc' });
  });

  it('rate limits a sender at 30 messages per sliding 10s, and recovers after the window', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    for (let i = 0; i < 30; i += 1) {
      const res = await send(alice.socket, messagePayload(conversation.body.id));
      assert.equal(res.ok, true, `message ${i} should be accepted`);
    }

    const limited = await send(alice.socket, messagePayload(conversation.body.id));
    assert.deepEqual(limited, { ok: false, code: 'RATE_LIMITED' });

    server.clock.advance(10_001);

    const recovered = await send(alice.socket, messagePayload(conversation.body.id));
    assert.equal(recovered.ok, true);
  });

  it("delivers message.new live to an online recipient, and to the sender's own log", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    await nextEvent(alice.socket, 'sync:caught-up', 8000);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);

    // Started only now, not before the catch-up waits above: their window
    // must cover just `send()` and delivery, not also however long the
    // (network-latency-bound) catch-up handshake takes.
    const aliceBatch = nextEvent(alice.socket, 'sync:batch', 8000);
    const bobBatch = nextEvent(bob.socket, 'sync:batch', 8000);

    const sent = await send(alice.socket, messagePayload(conversation.body.id, { content: 'hello bob' }));

    const bobPayload = await bobBatch;
    assert.equal(bobPayload.updates[0].kind, 'message.new');
    assert.equal(bobPayload.updates[0].payload.id, sent.messageId);
    assert.equal(bobPayload.updates[0].payload.content, 'hello bob');

    const alicePayload = await aliceBatch;
    assert.equal(alicePayload.updates[0].kind, 'message.new');
    assert.equal(alicePayload.updates[0].payload.id, sent.messageId);
  });

  it('delivers message.new on connect to a recipient who was offline when it was sent', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    const sent = await send(alice.socket, messagePayload(conversation.body.id, { content: 'while you were out' }));

    // `connectAs` may already have received and recorded the catch-up batch
    // by the time this line runs, so read from its `batches` list instead of
    // racing a fresh `nextEvent` listener against an event that already fired.
    const bob = await connectAs(BOB);
    await waitFor(() => bob.batches.length > 0, 8000);

    assert.equal(bob.batches[0].updates[0].payload.id, sent.messageId);
  });

  it("delivers message.new to the sender's other Device", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const aliceDevice1 = await connectAs(ALICE, 'device-1');
    const aliceDevice2 = await connectAs(ALICE, 'device-2');
    await nextEvent(aliceDevice1.socket, 'sync:caught-up', 8000);
    await nextEvent(aliceDevice2.socket, 'sync:caught-up', 8000);

    const otherDeviceBatch = nextEvent(aliceDevice2.socket, 'sync:batch', 8000);
    const sent = await send(aliceDevice1.socket, messagePayload(conversation.body.id));

    const batch = await otherDeviceBatch;
    assert.equal(batch.updates[0].payload.id, sent.messageId);
  });

  it('preserves seq order live across a burst of sends to several Conversations', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversationA = await seedConversation([ALICE, BOB]);
    const conversationB = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);

    for (const [conversation, content] of [
      [conversationA, 'a1'],
      [conversationB, 'b1'],
      [conversationA, 'a2'],
    ]) {
      const res = await send(alice.socket, messagePayload(conversation.body.id, { content }));
      assert.equal(res.ok, true);
    }

    // Acking each batch also moves Bob's delivery watermark (#49), which
    // interleaves conversation.receipts Updates among these message.new
    // ones — order among the message.new Updates is what's under test here.
    const messageNewUpdates = () =>
      bob.batches.flatMap((b) => b.updates).filter((u) => u.kind === 'message.new');
    await waitFor(() => messageNewUpdates().length >= 3, 8000);
    const contents = messageNewUpdates().map((u) => u.payload.content);
    assert.deepEqual(contents, ['a1', 'b1', 'a2']);
  });
});
