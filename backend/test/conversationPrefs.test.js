import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { createSendRateLimit } from '../src/messaging/rateLimiter.js';
import { createMessageSender } from '../src/messaging/sendMessage.js';
import { createFakeClock } from './support/fakeClock.js';
import { signIn } from './support/auth.js';
import { createConversation, createMessage, createUser } from './support/messaging.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const ALICE = '+14155550100';
const BOB = '+14155550101';
const CAROL = '+14155550102';

function auth(token) {
  return `Bearer ${token}`;
}

describe('PATCH /conversations/:id/prefs', () => {
  it('pins a conversation', async () => {
    const { app, clock } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    assert.equal(res.status, 200);
    assert.equal(res.body.pinnedAt, clock.now().toISOString());

    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId: conversation.id, userId: alice.user.id } },
    });
    assert.ok(participant.pinnedAt);
  });

  it('unpins a conversation', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    const res = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: false });

    assert.equal(res.status, 200);
    assert.equal(res.body.pinnedAt, null);
  });

  it('rejects pinning a 6th conversation', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const conversations = [];
    for (let i = 0; i < 6; i += 1) {
      const other = await createUser(prisma);
      const conversation = await createConversation(prisma, {
        type: 'direct',
        participantIds: [alice.user.id, other.id],
      });
      conversations.push(conversation);
    }
    for (const conversation of conversations.slice(0, 5)) {
      const res = await request(app)
        .patch(`/conversations/${conversation.id}/prefs`)
        .set('Authorization', auth(alice.accessToken))
        .send({ pinned: true });
      assert.equal(res.status, 200);
    }

    const res = await request(app)
      .patch(`/conversations/${conversations[5].id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'pin_limit');
  });

  it('re-pinning an already-pinned conversation is not blocked by the limit', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const conversations = [];
    for (let i = 0; i < 5; i += 1) {
      const other = await createUser(prisma);
      const conversation = await createConversation(prisma, {
        type: 'direct',
        participantIds: [alice.user.id, other.id],
      });
      conversations.push(conversation);
      await request(app)
        .patch(`/conversations/${conversation.id}/prefs`)
        .set('Authorization', auth(alice.accessToken))
        .send({ pinned: true });
    }

    const res = await request(app)
      .patch(`/conversations/${conversations[0].id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    assert.equal(res.status, 200);
  });

  it('archives and unarchives', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const archived = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ archived: true });
    assert.ok(archived.body.archivedAt);

    const unarchived = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ archived: false });
    assert.equal(unarchived.body.archivedAt, null);
  });

  it('stays archived once a new message arrives', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ archived: true });

    const send = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: createFakeClock() }),
      onWake: realtime.wakeUser,
    });
    const sendResult = await send(bob.user.id, {
      clientMsgId: randomUUID(),
      conversationId: conversation.id,
      content: 'new',
    });
    assert.equal(sendResult.ok, true);

    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId: conversation.id, userId: alice.user.id } },
    });
    assert.ok(participant.archivedAt, 'a new message must not clear archivedAt');

    const list = await request(app).get('/conversations').set('Authorization', auth(alice.accessToken));
    assert.equal(list.body.conversations[0].archivedAt, participant.archivedAt.toISOString());
  });

  it('mutes for 8h, 1w and always with the exact clock-derived mutedUntil', async () => {
    const { app, clock } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const now = clock.now();

    const eightHours = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ mute: '8h' });
    assert.equal(eightHours.body.mutedUntil, new Date(now.getTime() + 8 * 60 * 60 * 1000).toISOString());

    const oneWeek = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ mute: '1w' });
    assert.equal(oneWeek.body.mutedUntil, new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString());

    const always = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ mute: 'always' });
    assert.equal(always.body.mutedUntil, new Date('9999-12-31T00:00:00.000Z').toISOString());

    const unmuted = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ mute: null });
    assert.equal(unmuted.body.mutedUntil, null);
  });

  it('rejects an invalid mute value', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ mute: '1d' });

    assert.equal(res.status, 400);
  });

  it('returns 404 for a non-Participant', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(carol.accessToken))
      .send({ pinned: true });

    assert.equal(res.status, 404);
  });

  it("writes conversation.prefs only to the caller's own log", async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    const aliceUpdates = await prisma.userUpdate.findMany({
      where: { userId: alice.user.id, conversationId: conversation.id, kind: UPDATE_KINDS.CONVERSATION_PREFS },
    });
    const bobUpdates = await prisma.userUpdate.findMany({
      where: { userId: bob.user.id, conversationId: conversation.id, kind: UPDATE_KINDS.CONVERSATION_PREFS },
    });
    assert.equal(aliceUpdates.length, 1);
    assert.equal(bobUpdates.length, 0);
  });
});

describe('POST /conversations/:id/clear', () => {
  it('excludes cleared messages from unreadCount, lastMessage and history', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.user.id, content: 'old' });

    const cleared = await request(app)
      .post(`/conversations/${conversation.id}/clear`)
      .set('Authorization', auth(alice.accessToken));
    assert.equal(cleared.status, 200);
    assert.equal(cleared.body.lastMessage, null);
    assert.equal(cleared.body.unreadCount, 0);

    const list = await request(app).get('/conversations').set('Authorization', auth(alice.accessToken));
    assert.equal(list.body.conversations[0].lastMessage, null);
    assert.equal(list.body.conversations[0].unreadCount, 0);

    const history = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(alice.accessToken));
    assert.equal(history.body.messages.length, 0);

    // The other participant's own view is untouched.
    const bobHistory = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(bob.accessToken));
    assert.equal(bobHistory.body.messages.length, 1);
  });

  it("shows a reply to a cleared message as deleted to the owner, but intact to the other participant", async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const original = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.user.id,
      content: 'original',
    });

    // Clearing now cuts off at `original`, the only (and newest) message.
    await request(app)
      .post(`/conversations/${conversation.id}/clear`)
      .set('Authorization', auth(alice.accessToken));

    const send = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: createFakeClock() }),
      onWake: realtime.wakeUser,
    });
    const sendResult = await send(bob.user.id, {
      clientMsgId: randomUUID(),
      conversationId: conversation.id,
      content: 'a reply to the cleared message',
      replyToMessageId: original.id,
    });
    assert.equal(sendResult.ok, true);

    const aliceHistory = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(alice.accessToken));
    const aliceReply = aliceHistory.body.messages.find((m) => m.id === sendResult.messageId);
    assert.deepEqual(aliceReply.replyPreview, {
      id: original.id,
      conversationId: conversation.id,
      isDeleted: true,
    });

    const bobHistory = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(bob.accessToken));
    const bobReply = bobHistory.body.messages.find((m) => m.id === sendResult.messageId);
    assert.equal(bobReply.replyPreview.isDeleted, false);
    assert.equal(bobReply.replyPreview.content, 'original');
  });

  it('is a no-op when there is nothing to clear', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/clear`)
      .set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
    const updates = await prisma.userUpdate.count({ where: { userId: alice.user.id } });
    assert.equal(updates, 0);
  });

  it('returns 404 for a non-Participant', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/clear`)
      .set('Authorization', auth(carol.accessToken));

    assert.equal(res.status, 404);
  });
});

describe('POST /conversations/:id/delete', () => {
  it('hides a direct conversation from the list, unpinned and cleared', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.user.id });
    await request(app)
      .patch(`/conversations/${conversation.id}/prefs`)
      .set('Authorization', auth(alice.accessToken))
      .send({ pinned: true });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/delete`)
      .set('Authorization', auth(alice.accessToken));
    assert.equal(res.status, 200);
    assert.equal(res.body.pinnedAt, null);

    const list = await request(app).get('/conversations').set('Authorization', auth(alice.accessToken));
    assert.equal(list.body.conversations.length, 0);
  });

  it('reappears, with only the new message, once the other participant writes again', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.user.id, content: 'old' });
    await request(app)
      .post(`/conversations/${conversation.id}/delete`)
      .set('Authorization', auth(alice.accessToken));

    const send = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: createFakeClock() }),
      onWake: realtime.wakeUser,
    });
    const sendResult = await send(bob.user.id, {
      clientMsgId: randomUUID(),
      conversationId: conversation.id,
      content: 'new',
    });
    assert.equal(sendResult.ok, true);

    const list = await request(app).get('/conversations').set('Authorization', auth(alice.accessToken));
    assert.equal(list.body.conversations.length, 1);
    assert.equal(list.body.conversations[0].lastMessage.content, 'new');

    const prefsUpdates = await prisma.userUpdate.findMany({
      where: { userId: alice.user.id, conversationId: conversation.id, kind: UPDATE_KINDS.CONVERSATION_PREFS },
    });
    assert.ok(prefsUpdates.length >= 1);
  });

  it('refuses to delete a group the caller has not left', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      type: 'group',
      participantIds: [alice.user.id, bob.id],
    });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/delete`)
      .set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 409);
    assert.equal(res.body.error.code, 'must_leave_group');
  });

  it('allows deleting a group once the caller has left', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      type: 'group',
      participantIds: [alice.user.id, bob.id],
    });
    await prisma.participant.update({
      where: { conversationId_userId: { conversationId: conversation.id, userId: alice.user.id } },
      data: { leftAt: new Date() },
    });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/delete`)
      .set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
  });

  it('returns 404 for a non-Participant', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .post(`/conversations/${conversation.id}/delete`)
      .set('Authorization', auth(carol.accessToken));

    assert.equal(res.status, 404);
  });
});
