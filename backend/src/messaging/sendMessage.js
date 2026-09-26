import { isUuid } from '../auth/tokens.js';
import { MEDIA_LIMITS, verifyUploadResponse } from '../media/cloudinarySigner.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

const MAX_CONTENT_BYTES = 4096;
const MAX_LINK_TITLE_LENGTH = 200;
const MAX_LINK_DESCRIPTION_LENGTH = 500;
const MAX_FILE_NAME_LENGTH = 255;

const INVALID_LINK_PREVIEW = Symbol('invalid-link-preview');
const INVALID_MEDIA = Symbol('invalid-media');
const MEDIA_TOO_LARGE = Symbol('media-too-large');

// `type: 'text'` carries no `media`; `'image'`/`'file'` (#40, reduced
// scope — video isn't a supported `type` this pass) must reference an
// asset the sender themselves just uploaded: `publicId` proves ownership by
// living in the sender's own Cloudinary folder, `verifyUploadResponse`
// proves Cloudinary actually stored it (ADR 0002 — no Admin API call
// needed), and the byte/type checks stand in for the upload-preset
// enforcement #40's full scope would otherwise rely on (see
// `cloudinarySigner.js`'s comment on why no preset exists here).
function validateMedia(userId, type, media) {
  if (type === 'text') return { ok: true, data: null };

  const limits = MEDIA_LIMITS[type];
  if (!limits || typeof media !== 'object' || media === null) return { ok: false, reason: INVALID_MEDIA };

  const { publicId, version, signature, resourceType, bytes, format, width, height, fileName } = media;
  if (typeof publicId !== 'string' || !publicId.startsWith(`u/${userId}/`)) {
    return { ok: false, reason: INVALID_MEDIA };
  }
  if (!verifyUploadResponse({ publicId, version, signature })) return { ok: false, reason: INVALID_MEDIA };
  if (resourceType !== limits.resourceType) return { ok: false, reason: INVALID_MEDIA };
  if (typeof bytes !== 'number' || bytes <= 0) return { ok: false, reason: INVALID_MEDIA };
  if (bytes > limits.maxBytes) return { ok: false, reason: MEDIA_TOO_LARGE };
  if (typeof format !== 'string' || !limits.formats.includes(format.toLowerCase())) {
    return { ok: false, reason: INVALID_MEDIA };
  }

  let sanitizedFileName = null;
  if (type === 'file') {
    if (typeof fileName !== 'string' || fileName.trim().length === 0) {
      return { ok: false, reason: INVALID_MEDIA };
    }
    // Strip any path component a hostile client sent — only the display
    // name is ever trusted, never used as an actual filesystem path.
    sanitizedFileName = fileName.trim().replaceAll(/[/\\]/g, '_').slice(0, MAX_FILE_NAME_LENGTH);
  }

  return {
    ok: true,
    data: {
      mediaPublicId: publicId,
      mediaResourceType: resourceType,
      mediaBytes: Math.trunc(bytes),
      mediaWidth: typeof width === 'number' ? Math.trunc(width) : null,
      mediaHeight: typeof height === 'number' ? Math.trunc(height) : null,
      mediaFormat: typeof format === 'string' ? format.slice(0, 32) : null,
      mediaFileName: sanitizedFileName,
    },
  };
}

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
    const { clientMsgId, conversationId, content, replyToMessageId, linkPreview, media } = request ?? {};
    const type = request?.type ?? 'text';

    if (
      !isUuid(clientMsgId) ||
      !isUuid(conversationId) ||
      typeof content !== 'string' ||
      (type !== 'text' && type !== 'image' && type !== 'file')
    ) {
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

    // A media message's `content` is an optional caption; a text message's
    // is the whole point of it, so only that one requires a non-empty body.
    const trimmed = content.trim();
    const contentBytes = Buffer.byteLength(trimmed, 'utf8');
    if (type === 'text' && contentBytes === 0) return fail('INVALID');
    if (contentBytes > MAX_CONTENT_BYTES) return fail('TOO_LARGE');

    const mediaResult = validateMedia(userId, type, media);
    if (!mediaResult.ok) return fail(mediaResult.reason === MEDIA_TOO_LARGE ? 'TOO_LARGE' : 'INVALID');

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
              type,
              // A media message with no caption stores `null`, not `''`,
              // matching every other optional-content path in this schema.
              content: trimmed.length > 0 ? trimmed : null,
              replyToMessageId: replyToMessageId ?? null,
              linkPreview: normalizedLinkPreview,
              ...mediaResult.data,
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
