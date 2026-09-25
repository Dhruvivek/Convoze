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
const CAROL = '+14155550102';

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

function react(socket, payload) {
  return socket.emitWithAck('reaction:toggle', payload);
}

async function sendMessage(socket, conversationId, content = 'hi') {
  return send(socket, { clientMsgId: randomUUID(), conversationId, content });
}

describe('reaction:toggle', () => {
  it('adds a reaction, then removes it on a second toggle, writing reaction.changed each time', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);
    await nextEvent(alice.socket, 'sync:caught-up', 8000);
    await nextEvent(bob.socket, 'sync:caught-up', 8000);
    const sent = await sendMessage(alice.socket, conversation.body.id);
    // Delivery is decoupled from the send ack, and Bob's own ack of the
    // original message.new (via collectBatches) triggers its own
    // conversation.receipts fan-out (#49) shortly after: wait for both the
    // message and that follow-up to land on Bob before listening for the
    // reaction's batch, or either one still in flight can be what the
    // listener below catches instead.
    await waitFor(() => bob.batches.some((b) => b.updates.some((u) => u.payload?.id === sent.messageId)), 8000);
    await waitFor(
      () => bob.batches.flatMap((b) => b.updates).some((u) => u.kind === 'conversation.receipts'),
      8000,
    );

    const bobAdd = nextEvent(bob.socket, 'sync:batch', 8000);
    const added = await react(alice.socket, { messageId: sent.messageId, emoji: '👍' });
    assert.deepEqual(added, { ok: true });
    const addedPayload = await bobAdd;
    assert.equal(addedPayload.updates[0].kind, 'reaction.changed');
    assert.deepEqual(addedPayload.updates[0].payload.reactions, [
      { userId: alice.userId, emoji: '👍' },
    ]);

    const bobRemove = nextEvent(bob.socket, 'sync:batch', 8000);
    const removed = await react(alice.socket, { messageId: sent.messageId, emoji: '👍' });
    assert.deepEqual(removed, { ok: true });
    const removedPayload = await bobRemove;
    assert.deepEqual(removedPayload.updates[0].payload.reactions, []);
  });

  it('allows several different emoji from the same user on one message', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    await react(alice.socket, { messageId: sent.messageId, emoji: '👍' });
    await react(alice.socket, { messageId: sent.messageId, emoji: '❤️' });

    const reactions = await prisma.reaction.findMany({ where: { messageId: sent.messageId } });
    assert.equal(reactions.length, 2);
  });

  it('refuses a non-Participant', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const carol = await connectAs(CAROL);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    const res = await react(carol.socket, { messageId: sent.messageId, emoji: '👍' });

    assert.deepEqual(res, { ok: false, code: 'NOT_PARTICIPANT' });
  });

  it('rejects a non-single-grapheme or oversized emoji, and a malformed messageId', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const sent = await sendMessage(alice.socket, conversation.body.id);

    assert.deepEqual(await react(alice.socket, { messageId: sent.messageId, emoji: 'abc' }), {
      ok: false,
      code: 'INVALID',
    });
    assert.deepEqual(await react(alice.socket, { messageId: sent.messageId, emoji: '' }), {
      ok: false,
      code: 'INVALID',
    });
    assert.deepEqual(
      await react(alice.socket, { messageId: 'not-a-uuid', emoji: '👍' }),
      { ok: false, code: 'INVALID' },
    );
  });

  it('returns NOT_FOUND for a Message that does not exist', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);

    const res = await react(alice.socket, { messageId: randomUUID(), emoji: '👍' });

    assert.deepEqual(res, { ok: false, code: 'NOT_FOUND' });
  });
});
