import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { hydrateUpdates } from '../src/messaging/hydrator.js';
import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { writeUpdates } from '../src/messaging/updateWriter.js';
import { createConversation, createMessage, createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

async function fixtures() {
  const alice = await createUser(prisma, { displayName: 'Alice' });
  const bob = await createUser(prisma, { displayName: 'Bob' });
  const conversation = await createConversation(prisma, {
    participantIds: [alice.id, bob.id],
  });
  return { alice, bob, conversation };
}

function userById(users, id) {
  return users.find((u) => u.id === id);
}

describe('hydrateUpdates', () => {
  it('hydrates message.new to the Message\'s current state', async () => {
    const { alice, bob, conversation } = await fixtures();
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
      content: 'hello',
    });
    const [row] = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_NEW, messageId: message.id },
    ]);

    const { updates, users } = await hydrateUpdates(prisma, [row]);

    assert.equal(updates.length, 1);
    assert.deepEqual(updates[0].payload, {
      id: message.id,
      conversationId: conversation.id,
      senderId: alice.id,
      clientMsgId: message.clientMsgId,
      replyToMessageId: null,
      linkPreview: null,
      type: 'text',
      content: 'hello',
      createdAt: message.createdAt,
      editedAt: null,
      isDeleted: false,
    });
    assert.equal(updates[0].seq, row.seq);
    assert.equal(typeof updates[0].seq, 'number');
    assert.deepEqual(userById(users, alice.id).displayName, 'Alice');
  });

  it('hydrates message.new to a tombstone when the Message was deleted after the Update was written', async () => {
    const { alice, bob, conversation } = await fixtures();
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
    });
    const [row] = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_NEW, messageId: message.id },
    ]);

    await prisma.message.update({ where: { id: message.id }, data: { isDeleted: true } });
    const { updates } = await hydrateUpdates(prisma, [row]);

    assert.deepEqual(updates[0].payload, {
      id: message.id,
      conversationId: conversation.id,
      isDeleted: true,
    });
  });

  it("hydrates message.edited to the Message's latest content, not what it was when written", async () => {
    const { alice, bob, conversation } = await fixtures();
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
      content: 'original',
    });
    const [row] = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_EDITED, messageId: message.id },
    ]);

    const editedAt = new Date();
    await prisma.message.update({
      where: { id: message.id },
      data: { content: 'edited', editedAt },
    });
    const { updates } = await hydrateUpdates(prisma, [row]);

    assert.equal(updates[0].payload.content, 'edited');
    assert.deepEqual(updates[0].payload.editedAt, editedAt);
  });

  it('hydrates message.deleted to a tombstone that never carries content', async () => {
    const { alice, bob, conversation } = await fixtures();
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
      content: 'secret',
    });
    await prisma.message.update({ where: { id: message.id }, data: { isDeleted: true } });
    const [row] = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_DELETED, messageId: message.id },
    ]);

    const { updates, users } = await hydrateUpdates(prisma, [row]);

    assert.deepEqual(updates[0].payload, {
      id: message.id,
      conversationId: conversation.id,
      isDeleted: true,
    });
    // The sender isn't referenced by a tombstone.
    assert.equal(userById(users, alice.id), undefined);
  });

  it('hydrates reaction.changed to the current reaction set, additions and removals alike', async () => {
    const { alice, bob, conversation } = await fixtures();
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
    });
    await prisma.reaction.create({ data: { messageId: message.id, userId: alice.id, emoji: '👍' } });
    const [row] = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.REACTION_CHANGED, messageId: message.id },
    ]);

    await prisma.reaction.create({ data: { messageId: message.id, userId: bob.id, emoji: '❤️' } });
    const { updates, users } = await hydrateUpdates(prisma, [row]);

    assert.equal(updates[0].payload.messageId, message.id);
    assert.equal(updates[0].payload.conversationId, conversation.id);
    assert.deepEqual(
      updates[0].payload.reactions.sort((a, b) => a.userId.localeCompare(b.userId)),
      [
        { userId: alice.id, emoji: '👍' },
        { userId: bob.id, emoji: '❤️' },
      ].sort((a, b) => a.userId.localeCompare(b.userId)),
    );
    assert.ok(userById(users, alice.id));
    assert.ok(userById(users, bob.id));
  });

  it("hydrates conversation.receipts to every Participant's watermarks and the caller's unreadCount", async () => {
    const { alice, bob, conversation } = await fixtures();
    const m1 = await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    const m2 = await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    await prisma.participant.updateMany({
      where: { conversationId: conversation.id, userId: alice.id },
      data: { lastReadMessageId: m1.id, lastDeliveredMessageId: m1.id },
    });

    const [row] = await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversation.id,
      },
    ]);
    const { updates, users } = await hydrateUpdates(prisma, [row]);

    assert.equal(updates[0].payload.conversationId, conversation.id);
    assert.equal(updates[0].payload.unreadCount, 1); // m2, not m1
    const aliceWatermark = updates[0].payload.participants.find((p) => p.userId === alice.id);
    assert.equal(aliceWatermark.lastReadMessageId, m1.id);
    assert.equal(aliceWatermark.lastDeliveredMessageId, m1.id);
    const bobWatermark = updates[0].payload.participants.find((p) => p.userId === bob.id);
    assert.equal(bobWatermark.lastReadMessageId, null);
    assert.ok(userById(users, alice.id));
    assert.ok(userById(users, bob.id));
  });

  it("counts every non-own Message as unread when the caller hasn't read anything yet", async () => {
    const { alice, bob, conversation } = await fixtures();
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });

    const [row] = await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversation.id,
      },
    ]);
    const { updates } = await hydrateUpdates(prisma, [row]);

    assert.equal(updates[0].payload.unreadCount, 1); // bob's message, not alice's own
  });

  it('hydrates conversation.joined to the Conversation row', async () => {
    const { alice, conversation } = await fixtures();

    const [row] = await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_JOINED,
        conversationId: conversation.id,
      },
    ]);
    const { updates } = await hydrateUpdates(prisma, [row]);

    assert.deepEqual(updates[0].payload, conversation);
  });

  it('attaches a users side-list with no duplicates across a batch of Updates', async () => {
    const { alice, bob, conversation } = await fixtures();
    const m1 = await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });
    const m2 = await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });

    const rows = await writeUpdates(prisma, [
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_NEW, messageId: m1.id },
      { userId: bob.id, kind: UPDATE_KINDS.MESSAGE_NEW, messageId: m2.id },
    ]);
    const { users } = await hydrateUpdates(prisma, rows);

    assert.equal(users.length, 1);
    assert.deepEqual(users[0], {
      id: alice.id,
      displayName: 'Alice',
      avatarUrl: null,
      phoneNumber: alice.phoneNumber,
    });
  });

  it('is a no-op for an empty batch', async () => {
    assert.deepEqual(await hydrateUpdates(prisma, []), { updates: [], users: [] });
  });
});
