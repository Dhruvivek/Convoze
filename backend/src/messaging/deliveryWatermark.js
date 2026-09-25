import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

// After a Device acks a `sync:batch`, moves `userId`'s delivery watermark
// forward to the newest `message.new` from someone else per Conversation the
// batch contained (ADR 0008). UUIDv7 ids sort chronologically as strings, so
// the greatest id is the newest message. Writes a coalesced
// `conversation.receipts` Update to every Participant of each Conversation
// whose watermark actually moved — including the acker's own other Devices,
// which is how unread badges clear across Devices.
export async function moveDeliveryWatermarksOnAck(prisma, { userId, updates, onWake }) {
  const newestByConversation = new Map();
  for (const update of updates) {
    if (update.kind !== UPDATE_KINDS.MESSAGE_NEW) continue;
    const { payload } = update;
    // A tombstone (deleted since this Update was written) no longer carries
    // a senderId, so it can't be attributed to "someone else"; skip it.
    if (payload.isDeleted || payload.senderId === userId) continue;
    const current = newestByConversation.get(payload.conversationId);
    if (!current || payload.id > current) newestByConversation.set(payload.conversationId, payload.id);
  }
  if (newestByConversation.size === 0) return;

  const receiptUpdates = [];
  await prisma.$transaction(
    async (tx) => {
      for (const [conversationId, messageId] of newestByConversation) {
        const moved = await tx.$executeRaw`
          UPDATE "Participant"
          SET "lastDeliveredMessageId" = ${messageId}::uuid
          WHERE "conversationId" = ${conversationId}::uuid AND "userId" = ${userId}::uuid
            AND ("lastDeliveredMessageId" IS NULL OR "lastDeliveredMessageId" < ${messageId}::uuid)
        `;
        if (moved === 0) continue;
        const participants = await tx.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });
        for (const { userId: participantId } of participants) {
          receiptUpdates.push({
            userId: participantId,
            kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
            conversationId,
          });
        }
      }
      if (receiptUpdates.length > 0) await writeUpdatesInTx(tx, receiptUpdates);
    },
    { timeout: 20_000, maxWait: 10_000 },
  );

  for (const affectedUserId of new Set(receiptUpdates.map((u) => u.userId))) onWake(affectedUserId);
}
