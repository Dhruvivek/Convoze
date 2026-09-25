import { randomUUID } from 'node:crypto';

// Seeds `count` Messages into an existing Conversation, bypassing the
// Update log the same way `seedConversation.js` bypasses it — this is only
// ever used to fast-fill history for the pagination e2e suite (#55), not to
// exercise the send pipeline. Inserted sequentially so each Message's
// uuidv7 `id` (and so `GET .../messages`'s `id`-ordered paging) sorts in
// insertion order.
export async function seedMessages(prisma, conversationId, { count, senderId } = {}) {
  if (!Number.isInteger(count) || count <= 0 || typeof senderId !== 'string') return null;

  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const message = await prisma.message.create({
      data: {
        conversationId,
        senderId,
        content: `seeded message ${i + 1}`,
        clientMsgId: randomUUID(),
      },
      select: { id: true },
    });
    ids.push(message.id);
  }
  return { count: ids.length };
}
