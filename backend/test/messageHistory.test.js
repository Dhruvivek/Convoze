import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { listMessages } from '../src/messaging/messageHistory.js';
import { createConversation, createMessage, createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function ids(messages) {
  return messages.map((m) => m.id);
}

describe('listMessages', () => {
  it('returns messages newest first, hydrated to their current state', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const m1 = await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });
    const m2 = await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });

    const result = await listMessages(prisma, alice.id, conversation.id, {});

    assert.equal(result.ok, true);
    assert.deepEqual(ids(result.messages), [m2.id, m1.id]);
  });

  it('pages strictly older than `before`, and reports the next boundary', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const messages = [];
    for (let i = 0; i < 5; i += 1) {
      messages.push(await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id }));
    }

    const firstPage = await listMessages(prisma, alice.id, conversation.id, { limit: 2 });
    assert.deepEqual(ids(firstPage.messages), [messages[4].id, messages[3].id]);
    assert.equal(firstPage.nextBefore, messages[3].id);

    const secondPage = await listMessages(prisma, alice.id, conversation.id, {
      before: firstPage.nextBefore,
      limit: 2,
    });
    assert.deepEqual(ids(secondPage.messages), [messages[2].id, messages[1].id]);

    const lastPage = await listMessages(prisma, alice.id, conversation.id, {
      before: secondPage.nextBefore,
      limit: 2,
    });
    assert.deepEqual(ids(lastPage.messages), [messages[0].id]);
    assert.equal(lastPage.nextBefore, null);
  });

  it('carries reactions and a live-hydrated Reply preview', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const original = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: alice.id,
      content: 'original',
    });
    const reply = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.id,
      replyToMessageId: original.id,
    });
    await prisma.reaction.create({ data: { messageId: reply.id, userId: alice.id, emoji: '👍' } });

    const result = await listMessages(prisma, alice.id, conversation.id, {});
    const replyOut = result.messages.find((m) => m.id === reply.id);

    assert.deepEqual(replyOut.reactions, [{ userId: alice.id, emoji: '👍' }]);
    assert.equal(replyOut.replyPreview.id, original.id);
    assert.equal(replyOut.replyPreview.content, 'original');

    // Edited after the reply was sent: the preview reflects it now, not a
    // copy taken at reply time (CONTEXT.md's Reply).
    await prisma.message.update({ where: { id: original.id }, data: { content: 'edited', editedAt: new Date() } });
    const afterEdit = await listMessages(prisma, alice.id, conversation.id, {});
    assert.equal(afterEdit.messages.find((m) => m.id === reply.id).replyPreview.content, 'edited');
  });

  it('shows a tombstone Reply preview once the original is deleted', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const original = await createMessage(prisma, { conversationId: conversation.id, senderId: alice.id });
    const reply = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.id,
      replyToMessageId: original.id,
    });
    await prisma.message.update({
      where: { id: original.id },
      data: { isDeleted: true, content: null },
    });

    const result = await listMessages(prisma, alice.id, conversation.id, {});
    const replyOut = result.messages.find((m) => m.id === reply.id);

    assert.deepEqual(replyOut.replyPreview, { id: original.id, conversationId: conversation.id, isDeleted: true });
  });

  it('carries a users side-list for senders and reactors', async () => {
    const alice = await createUser(prisma, { displayName: 'Alice' });
    const bob = await createUser(prisma, { displayName: 'Bob' });
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const message = await createMessage(prisma, { conversationId: conversation.id, senderId: bob.id });
    await prisma.reaction.create({ data: { messageId: message.id, userId: alice.id, emoji: '❤️' } });

    const result = await listMessages(prisma, alice.id, conversation.id, {});

    assert.deepEqual(
      result.users.map((u) => u.id).sort(),
      [alice.id, bob.id].sort(),
    );
  });

  it('rejects a non-Participant', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const stranger = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });

    const result = await listMessages(prisma, stranger.id, conversation.id, {});

    assert.deepEqual(result, { ok: false, code: 'NOT_PARTICIPANT' });
  });

  it('rejects a malformed Conversation id or before cursor', async () => {
    const alice = await createUser(prisma);

    assert.deepEqual(await listMessages(prisma, alice.id, 'not-a-uuid', {}), {
      ok: false,
      code: 'INVALID',
    });
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });
    assert.deepEqual(
      await listMessages(prisma, alice.id, conversation.id, { before: 'not-a-uuid' }),
      { ok: false, code: 'INVALID' },
    );
  });

  it('caps history at when a Participant left, even if newer Messages exist', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const beforeLeft = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.id,
      createdAt: new Date('2026-01-01T00:00:00.000Z'),
    });
    await prisma.participant.updateMany({
      where: { conversationId: conversation.id, userId: alice.id },
      data: { leftAt: new Date('2026-01-01T00:00:30.000Z') },
    });
    await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.id,
      createdAt: new Date('2026-01-01T00:01:00.000Z'),
    });

    const result = await listMessages(prisma, alice.id, conversation.id, {});

    assert.deepEqual(ids(result.messages), [beforeLeft.id]);
  });

  it('rejects a Conversation id with no such Conversation', async () => {
    const alice = await createUser(prisma);
    const result = await listMessages(prisma, alice.id, randomUUID(), {});
    assert.deepEqual(result, { ok: false, code: 'NOT_PARTICIPANT' });
  });
});
