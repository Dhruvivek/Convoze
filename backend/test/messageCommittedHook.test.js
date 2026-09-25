import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { createSendRateLimit } from '../src/messaging/rateLimiter.js';
import { createMessageSender } from '../src/messaging/sendMessage.js';
import { createFakeClock } from './support/fakeClock.js';
import { createConversation, createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function buildSender(overrides = {}) {
  const rateLimiter = createSendRateLimit({ clock: createFakeClock() });
  return createMessageSender({ prisma, rateLimiter, onWake: () => {}, ...overrides });
}

// The push/blocking seam (#50/ADR 0006): sendMessage.js is the only place a
// message.new commits, so this is where onMessageCommitted must fire.
describe('onMessageCommitted', () => {
  it('fires once per new Message, after commit, with every recipient but the sender', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const carol = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      participantIds: [alice.id, bob.id, carol.id],
    });
    const calls = [];
    const sendMessage = buildSender({
      onMessageCommitted: (message, recipientUserIds) => calls.push({ message, recipientUserIds }),
    });

    const result = await sendMessage(alice.id, {
      clientMsgId: randomUUID(),
      conversationId: conversation.id,
      content: 'hi',
    });

    assert.equal(calls.length, 1);
    assert.equal(calls[0].message.id, result.messageId);
    assert.deepEqual(calls[0].recipientUserIds.sort(), [bob.id, carol.id].sort());
    const row = await prisma.message.findUnique({ where: { id: result.messageId } });
    assert.ok(row);
  });

  it('does not fire again for a retried send with the same clientMsgId', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const calls = [];
    const sendMessage = buildSender({ onMessageCommitted: () => calls.push(1) });
    const payload = { clientMsgId: randomUUID(), conversationId: conversation.id, content: 'hi' };

    await sendMessage(alice.id, payload);
    await sendMessage(alice.id, payload);

    assert.equal(calls.length, 1);
  });

  it('defaults to a no-op when omitted', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id, bob.id] });
    const sendMessage = buildSender();

    const result = await sendMessage(alice.id, {
      clientMsgId: randomUUID(),
      conversationId: conversation.id,
      content: 'hi',
    });

    assert.equal(result.ok, true);
  });
});
