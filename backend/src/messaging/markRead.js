import { isUuid } from '../auth/tokens.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

function fail(code) {
  return { ok: false, code };
}

// `conversation:read` (#49/ADR 0008): `{ conversationId, messageId }` moves
// the caller's read watermark forward to `messageId`, and the delivery
// watermark along with it (read implies delivered) — both forward-only.
// Writes a coalesced `conversation.receipts` Update to every Participant,
// including the mover's own other Devices, which is how unread badges clear
// across Devices.
export function createReadMarker({ prisma, onWake }) {
  return async function markRead(userId, request) {
    const { conversationId, messageId } = request ?? {};
    if (!isUuid(conversationId) || !isUuid(messageId)) return fail('INVALID');

    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    });
    if (!participant) return fail('NOT_PARTICIPANT');

    const message = await prisma.message.findUnique({ where: { id: messageId } });
    if (!message) return fail('NOT_FOUND');
    if (message.conversationId !== conversationId) return fail('FORBIDDEN');

    let receiptUpdates = [];
    await prisma.$transaction(
      async (tx) => {
        const moved = await tx.$executeRaw`
          UPDATE "Participant"
          SET
            "lastReadMessageId" = ${messageId}::uuid,
            "lastDeliveredMessageId" = CASE
              WHEN "lastDeliveredMessageId" IS NULL OR "lastDeliveredMessageId" < ${messageId}::uuid
              THEN ${messageId}::uuid
              ELSE "lastDeliveredMessageId"
            END
          WHERE "conversationId" = ${conversationId}::uuid AND "userId" = ${userId}::uuid
            AND ("lastReadMessageId" IS NULL OR "lastReadMessageId" < ${messageId}::uuid)
        `;
        if (moved === 0) return;
        const participants = await tx.participant.findMany({
          where: { conversationId },
          select: { userId: true },
        });
        receiptUpdates = participants.map(({ userId: participantId }) => ({
          userId: participantId,
          kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
          conversationId,
        }));
        await writeUpdatesInTx(tx, receiptUpdates);
      },
      { timeout: 20_000, maxWait: 10_000 },
    );

    for (const affectedUserId of new Set(receiptUpdates.map((u) => u.userId))) onWake(affectedUserId);
    return { ok: true };
  };
}
