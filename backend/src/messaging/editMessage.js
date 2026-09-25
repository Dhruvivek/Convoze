import { isUuid } from '../auth/tokens.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

const MAX_CONTENT_BYTES = 4096;

function fail(code) {
  return { ok: false, code };
}

// `message:edit` (#49/ADR 0008): `{ messageId, content }`. Sender only, text
// Messages only, and only while not deleted. Sets `editedAt` and writes
// `message.edited` to every Participant, sender included.
export function createMessageEditor({ prisma, rateLimiter, onWake }) {
  return async function editMessage(userId, request) {
    const { messageId, content } = request ?? {};
    if (!isUuid(messageId) || typeof content !== 'string') return fail('INVALID');

    if (!rateLimiter.consume(userId)) return fail('RATE_LIMITED');

    const message = await prisma.message.findUnique({ where: { id: messageId } });
    if (!message) return fail('NOT_FOUND');
    if (message.senderId !== userId) return fail('FORBIDDEN');
    if (message.type !== 'text' || message.isDeleted) return fail('FORBIDDEN');

    const trimmed = content.trim();
    const contentBytes = Buffer.byteLength(trimmed, 'utf8');
    if (contentBytes === 0) return fail('INVALID');
    if (contentBytes > MAX_CONTENT_BYTES) return fail('TOO_LARGE');

    const participants = await prisma.participant.findMany({
      where: { conversationId: message.conversationId },
      select: { userId: true },
    });

    await prisma.$transaction(
      async (tx) => {
        await tx.message.update({
          where: { id: messageId },
          data: { content: trimmed, editedAt: new Date() },
        });
        await writeUpdatesInTx(
          tx,
          participants.map(({ userId: participantId }) => ({
            userId: participantId,
            kind: UPDATE_KINDS.MESSAGE_EDITED,
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
