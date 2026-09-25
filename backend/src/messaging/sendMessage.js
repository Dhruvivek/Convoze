import { isUuid } from '../auth/tokens.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

const MAX_CONTENT_BYTES = 4096;
const MAX_LINK_TITLE_LENGTH = 200;
const MAX_LINK_DESCRIPTION_LENGTH = 500;

const INVALID_LINK_PREVIEW = Symbol('invalid-link-preview');

// `null` (no preview given), a normalised `{url, title, description}`, or
// the sentinel above for anything malformed.
function normalizeLinkPreview(linkPreview, content) {
  if (linkPreview === undefined || linkPreview === null) return null;
  if (typeof linkPreview !== 'object' || Array.isArray(linkPreview)) return INVALID_LINK_PREVIEW;

  const { url, title, description } = linkPreview;
  // Never fetched server-side (ADR 0002/0008): just checked for shape, and
  // that it actually names a link this Message contains.
  if (typeof url !== 'string' || !url.startsWith('https://') || !content.includes(url)) {
    return INVALID_LINK_PREVIEW;
  }
  if (isTooLong(title, MAX_LINK_TITLE_LENGTH) || isTooLong(description, MAX_LINK_DESCRIPTION_LENGTH)) {
    return INVALID_LINK_PREVIEW;
  }
  return { url, title: title ?? null, description: description ?? null };
}

// `undefined`/`null` are fine (the field is optional); anything else must be
// a string within `max`.
function isTooLong(value, max) {
  return value !== undefined && value !== null && (typeof value !== 'string' || value.length > max);
}

function fail(code) {
  return { ok: false, code };
}

// `message:send` (ADR 0008 / #48): the only path a Message is created
// through — there's no REST send path, so there's only one set of guards to
// keep in sync. `onWake(userId)` fires once per affected Participant
// (sender included) after commit, which is what lets their connected pumps
// (`pump.js`) notice immediately rather than polling for it. `onMessageCommitted`
// is the push seam (#50/ADR 0006): no-op by default, so this ticket sends no
// pushes itself, but a later one can pass a real implementation without
// touching this file again.
export function createMessageSender({ prisma, rateLimiter, onWake, onMessageCommitted = () => {} }) {
  return async function sendMessage(userId, request) {
    const { clientMsgId, conversationId, content, replyToMessageId, linkPreview } = request ?? {};

    if (!isUuid(clientMsgId) || !isUuid(conversationId) || typeof content !== 'string') {
      return fail('INVALID');
    }

    // Idempotency first: a retry must return the original result rather
    // than being re-validated (its Participant status, say, may since have
    // changed), and shouldn't cost the sender a slot in their rate limit.
    const existing = await prisma.message.findUnique({
      where: { senderId_clientMsgId: { senderId: userId, clientMsgId } },
    });
    if (existing) return { ok: true, messageId: existing.id, createdAt: existing.createdAt };

    if (!rateLimiter.consume(userId)) return fail('RATE_LIMITED');

    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    });
    if (!participant) return fail('NOT_PARTICIPANT');

    const trimmed = content.trim();
    const contentBytes = Buffer.byteLength(trimmed, 'utf8');
    if (contentBytes === 0) return fail('INVALID');
    if (contentBytes > MAX_CONTENT_BYTES) return fail('TOO_LARGE');

    if (replyToMessageId !== undefined && replyToMessageId !== null) {
      if (!isUuid(replyToMessageId)) return fail('INVALID');
      const replyTo = await prisma.message.findUnique({ where: { id: replyToMessageId } });
      if (!replyTo) return fail('NOT_FOUND');
      if (replyTo.conversationId !== conversationId) return fail('FORBIDDEN');
    }

    const normalizedLinkPreview = normalizeLinkPreview(linkPreview, trimmed);
    if (normalizedLinkPreview === INVALID_LINK_PREVIEW) return fail('INVALID');

    const participants = await prisma.participant.findMany({
      where: { conversationId },
      select: { userId: true, hiddenAt: true },
    });

    let message;
    try {
      message = await prisma.$transaction(
        async (tx) => {
          const created = await tx.message.create({
            data: {
              conversationId,
              senderId: userId,
              clientMsgId,
              content: trimmed,
              replyToMessageId: replyToMessageId ?? null,
              linkPreview: normalizedLinkPreview,
            },
          });
          // A Conversation this Participant deleted (#45) reappears — with
          // only this and later Messages, since the watermark stays put —
          // the moment someone writes into it again.
          const hiddenRecipientIds = participants
            .filter((p) => p.hiddenAt !== null)
            .map((p) => p.userId);
          if (hiddenRecipientIds.length > 0) {
            await tx.participant.updateMany({
              where: { conversationId, userId: { in: hiddenRecipientIds } },
              data: { hiddenAt: null },
            });
          }

          // The sender's own log gets `message.new` too (ADR 0008), in the
          // same transaction as every other Participant.
          await writeUpdatesInTx(tx, [
            ...participants.map(({ userId: recipientId }) => ({
              userId: recipientId,
              kind: UPDATE_KINDS.MESSAGE_NEW,
              conversationId,
              messageId: created.id,
            })),
            ...hiddenRecipientIds.map((recipientId) => ({
              userId: recipientId,
              kind: UPDATE_KINDS.CONVERSATION_PREFS,
              conversationId,
            })),
          ]);
          return created;
        },
        { timeout: 20_000, maxWait: 10_000 },
      );
    } catch (err) {
      // A concurrent retry of the same (senderId, clientMsgId) lost the race
      // to insert; the winner's row is the one true result, same as if this
      // call had found it up front.
      if (err.code === 'P2002') {
        const winner = await prisma.message.findUnique({
          where: { senderId_clientMsgId: { senderId: userId, clientMsgId } },
        });
        if (winner) return { ok: true, messageId: winner.id, createdAt: winner.createdAt };
      }
      throw err;
    }

    for (const { userId: recipientId } of participants) onWake(recipientId);
    const recipientUserIds = participants
      .map(({ userId: participantId }) => participantId)
      .filter((participantId) => participantId !== userId);
    onMessageCommitted(message, recipientUserIds);

    return { ok: true, messageId: message.id, createdAt: message.createdAt };
  };
}
