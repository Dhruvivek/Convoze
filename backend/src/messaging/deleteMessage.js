import { isUuid } from '../auth/tokens.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

function fail(code) {
  return { ok: false, code };
}

// `message:delete` (#49/ADR 0008): `{ messageId }`. Sender only. A soft
// delete — `isDeleted` is set and `content`/`linkPreview` are cleared, never
// the row itself — and idempotent: deleting an already-deleted Message
// succeeds without writing a further Update. Writes `message.deleted` (a
// tombstone) to every Participant.
export function createMessageDeleter({ prisma, onWake }) {
  return async function deleteMessage(userId, request) {
    const { messageId } = request ?? {};
    if (!isUuid(messageId)) return fail('INVALID');

    const message = await prisma.message.findUnique({ where: { id: messageId } });
    if (!message) return fail('NOT_FOUND');
    if (message.senderId !== userId) return fail('FORBIDDEN');
    if (message.isDeleted) return { ok: true };

    const participants = await prisma.participant.findMany({
      where: { conversationId: message.conversationId },
      select: { userId: true },
    });

    await prisma.$transaction(
      async (tx) => {
        await tx.message.update({
          where: { id: messageId },
          data: { isDeleted: true, content: null, linkPreview: null },
        });
        await writeUpdatesInTx(
          tx,
          participants.map(({ userId: participantId }) => ({
            userId: participantId,
            kind: UPDATE_KINDS.MESSAGE_DELETED,
            conversationId: message.conversationId,
            messageId,
          })),
        );
      },
      { timeout: 20_000, maxWait: 10_000 },
    );

    for (const { userId: participantId } of participants) onWake(participantId);
    return { ok: true };
  };
}
