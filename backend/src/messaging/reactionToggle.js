import { isUuid } from '../auth/tokens.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

const MAX_EMOJI_BYTES = 32;
const graphemeSegmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });

// A single grapheme cluster, at most 32 bytes: good enough to admit one
// emoji (including multi-codepoint ones like a skin-tone or ZWJ sequence)
// without pulling in an emoji-specific Unicode property check.
function isSingleGrapheme(value) {
  if (typeof value !== 'string' || value.length === 0) return false;
  if (Buffer.byteLength(value, 'utf8') > MAX_EMOJI_BYTES) return false;
  const segments = [...graphemeSegmenter.segment(value)];
  return segments.length === 1;
}

function fail(code) {
  return { ok: false, code };
}

// `reaction:toggle` (#49/ADR 0008): `{ messageId, emoji }`. Participant
// only. Adds the reaction if absent, removes it if present. Writes
// `reaction.changed` — the Message's full reaction set — to every
// Participant.
export function createReactionToggler({ prisma, rateLimiter, onWake }) {
  return async function toggleReaction(userId, request) {
    const { messageId, emoji } = request ?? {};
    if (!isUuid(messageId) || !isSingleGrapheme(emoji)) return fail('INVALID');

    if (!rateLimiter.consume(userId)) return fail('RATE_LIMITED');

    const message = await prisma.message.findUnique({ where: { id: messageId } });
    if (!message) return fail('NOT_FOUND');

    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId: message.conversationId, userId } },
    });
    if (!participant) return fail('NOT_PARTICIPANT');

    const participants = await prisma.participant.findMany({
      where: { conversationId: message.conversationId },
      select: { userId: true },
    });

    await prisma.$transaction(
      async (tx) => {
        const existing = await tx.reaction.findUnique({
          where: { messageId_userId_emoji: { messageId, userId, emoji } },
        });
        if (existing) {
          await tx.reaction.delete({ where: { id: existing.id } });
        } else {
          await tx.reaction.create({ data: { messageId, userId, emoji } });
        }
        await writeUpdatesInTx(
          tx,
          participants.map(({ userId: participantId }) => ({
            userId: participantId,
            kind: UPDATE_KINDS.REACTION_CHANGED,
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
