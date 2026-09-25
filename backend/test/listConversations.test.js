import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { listConversations } from '../src/messaging/listConversations.js';
import { createConversation, createMessage, createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function ids(conversations) {
  return conversations.map((c) => c.id);
}

describe('listConversations', () => {
  it('orders by newest activity (latest Message, or Conversation creation with none) first', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const oldest = await createConversation(prisma, { participantIds: [alice.id, bob.id], name: 'oldest' });
    const noMessages = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.id, bob.id],
    });
    const mostRecentActivity = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
      name: 'active',
    });
    await createMessage(prisma, { conversationId: oldest.id, senderId: alice.id });
    await createMessage(prisma, { conversationId: mostRecentActivity.id, senderId: bob.id });

    const { conversations } = await listConversations(prisma, alice.id);

    // `oldest`'s Message was written after `noMessages` was created, so its
    // activity is more recent than `noMessages`'s own (message-less)
    // creation time.
    assert.deepEqual(ids(conversations), [mostRecentActivity.id, oldest.id, noMessages.id]);
  });

  it('paginates with a cursor, one page after another with no overlap', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversations = [];
    for (let i = 0; i < 5; i += 1) {
      const conversation = await createConversation(prisma, {
        participantIds: [alice.id, bob.id],
        name: `c${i}`,
      });
      await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
      conversations.push(conversation);
    }

    const firstPage = await listConversations(prisma, alice.id, { limit: 2 });
    assert.equal(firstPage.conversations.length, 2);
    assert.ok(firstPage.nextCursor);

    const secondPage = await listConversations(prisma, alice.id, {
      limit: 2,
      cursor: firstPage.nextCursor,
    });
    assert.equal(secondPage.conversations.length, 2);

    const thirdPage = await listConversations(prisma, alice.id, {
      limit: 2,
      cursor: secondPage.nextCursor,
    });
    assert.equal(thirdPage.conversations.length, 1);
    assert.equal(thirdPage.nextCursor, null);

    const seenIds = [...firstPage.conversations, ...secondPage.conversations, ...thirdPage.conversations].map(
      (c) => c.id,
    );
    assert.deepEqual(seenIds.sort(), conversations.map((c) => c.id).sort());
  });

  it('reports currentSeq only on the first page', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    for (let i = 0; i < 2; i += 1) {
      const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
      await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    }

    const firstPage = await listConversations(prisma, alice.id, { limit: 1 });
    assert.equal(typeof firstPage.currentSeq, 'number');
    assert.ok(firstPage.nextCursor);

    const secondPage = await listConversations(prisma, alice.id, {
      limit: 1,
      cursor: firstPage.nextCursor,
    });
    assert.equal('currentSeq' in secondPage, false);
  });

  it('reports the unread count and watermarks per Participant', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const m1 = await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    await prisma.participant.updateMany({
      where: { conversationId: conversation.id, userId: alice.id },
      data: { lastReadMessageId: m1.id, lastDeliveredMessageId: m1.id },
    });

    const { conversations } = await listConversations(prisma, alice.id);

    const row = conversations[0];
    assert.equal(row.unreadCount, 1);
    const aliceRead = row.readWatermarks.find((w) => w.userId === alice.id);
    assert.equal(aliceRead.messageId, m1.id);
    const bobRead = row.readWatermarks.find((w) => w.userId === bob.id);
    assert.equal(bobRead.messageId, null);
    const aliceDelivered = row.deliveryWatermarks.find((w) => w.userId === alice.id);
    assert.equal(aliceDelivered.messageId, m1.id);
  });

  it('omits an empty direct Conversation for the Participant who did not create it', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.id, bob.id],
      createdById: alice.id,
    });

    const aliceList = await listConversations(prisma, alice.id);
    const bobList = await listConversations(prisma, bob.id);

    assert.deepEqual(ids(aliceList.conversations), [conversation.id]);
    assert.deepEqual(ids(bobList.conversations), []);
  });

  it('shows a direct Conversation to the non-creator once it has a Message', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.id, bob.id],
      createdById: alice.id,
    });
    await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });

    const bobList = await listConversations(prisma, bob.id);

    assert.deepEqual(ids(bobList.conversations), [conversation.id]);
  });

  it('flags a Conversation the Participant has left, and keeps it in the list', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    await prisma.participant.updateMany({
      where: { conversationId: conversation.id, userId: alice.id },
      data: { leftAt: new Date() },
    });

    const { conversations } = await listConversations(prisma, alice.id);

    assert.equal(conversations.length, 1);
    assert.equal(conversations[0].left, true);
  });

  it('carries a users side-list for every referenced Participant and sender', async () => {
    const alice = await createUser(prisma, { displayName: 'Alice' });
    const bob = await createUser(prisma, { displayName: 'Bob' });
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });

    const { users } = await listConversations(prisma, alice.id);

    assert.deepEqual(
      users.map((u) => u.id).sort(),
      [alice.id, bob.id].sort(),
    );
  });

  it('is empty for a User with no Conversations', async () => {
    const alice = await createUser(prisma);
    const result = await listConversations(prisma, alice.id);
    assert.deepEqual(result, { conversations: [], nextCursor: null, users: [], currentSeq: 0 });
  });
});
