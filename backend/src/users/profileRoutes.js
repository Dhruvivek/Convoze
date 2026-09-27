import { Router } from 'express';

import { sendError } from '../http/errors.js';
import { AVATAR_LIMITS, avatarDeliveryUrl, destroyAsset, verifyUploadResponse } from '../media/cloudinarySigner.js';
import { createSendRateLimit } from '../messaging/rateLimiter.js';
import { USER_SELECT } from '../messaging/hydrator.js';

const MAX_DISPLAY_NAME_LENGTH = 50;
const MAX_ABOUT_LENGTH = 140;
const CONTROL_CHARS = /[\x00-\x1F\x7F]/;

function profilePayload(user) {
  return { id: user.id, phoneNumber: user.phoneNumber, displayName: user.displayName, about: user.about, avatarUrl: user.avatarUrl };
}

// `null` clears the field, `undefined` leaves it untouched, a string sets it
// (trimmed) — the same three-way shape `PATCH /users/me` exposes for both
// `displayName` and `about`. Returns the symbol below for anything invalid.
const INVALID = Symbol('invalid-profile-field');

function normalizeField(value, { maxLength, allowEmpty }) {
  if (value === undefined) return undefined;
  if (value === null) return null;
  if (typeof value !== 'string') return INVALID;
  const trimmed = value.trim();
  if (!allowEmpty && trimmed.length === 0) return INVALID;
  if (trimmed.length > maxLength) return INVALID;
  if (CONTROL_CHARS.test(trimmed)) return INVALID;
  return trimmed.length === 0 ? null : trimmed;
}

// `PATCH /users/me`, `PUT/DELETE /users/me/avatar` and `GET /users/:id`
// (#43): the profile half of the User model `GET /users` (`listUsers.js`)
// already exposes for the Contacts tab. Kept in its own module — these are
// User-identity concerns, not the "everyone else on Convoze" listing.
export function createProfileRouter({ prisma, authenticated, clock }) {
  const router = Router();
  // Same shape as the media signature limiter: a generous, per-user,
  // in-memory sliding window — this is edited by the user themselves, not
  // fan-out to others, so there's no reason for it to be as strict as
  // messaging's per-sender limit.
  const writeRateLimit = createSendRateLimit({ clock, limit: 30, windowMs: 10 * 60 * 1000 });

  router.get('/users/me', authenticated, async (req, res) => {
    const user = await prisma.user.findUnique({ where: { id: req.auth.userId }, select: USER_SELECT });
    res.json(profilePayload(user));
  });

  router.patch('/users/me', authenticated, async (req, res) => {
    if (!writeRateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many profile updates');
      return;
    }
    const { displayName, about } = req.body ?? {};
    const normalizedName = normalizeField(displayName, { maxLength: MAX_DISPLAY_NAME_LENGTH, allowEmpty: false });
    const normalizedAbout = normalizeField(about, { maxLength: MAX_ABOUT_LENGTH, allowEmpty: true });
    if (normalizedName === INVALID) {
      sendError(res, 400, 'invalid_request', `displayName must be 1-${MAX_DISPLAY_NAME_LENGTH} characters, or null`);
      return;
    }
    if (normalizedAbout === INVALID) {
      sendError(res, 400, 'invalid_request', `about must be at most ${MAX_ABOUT_LENGTH} characters`);
      return;
    }

    const data = {};
    if (normalizedName !== undefined) data.displayName = normalizedName;
    if (normalizedAbout !== undefined) data.about = normalizedAbout;
    const user = await prisma.user.update({ where: { id: req.auth.userId }, data, select: USER_SELECT });
    res.json(profilePayload(user));
  });

  router.put('/users/me/avatar', authenticated, async (req, res) => {
    if (!writeRateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many profile updates');
      return;
    }
    const { publicId, version, signature, resourceType, bytes, format } = req.body ?? {};
    const invalid = () => sendError(res, 400, 'invalid_request', 'Invalid avatar upload');
    if (typeof publicId !== 'string' || !publicId.startsWith('avatars/')) return invalid();
    if (!verifyUploadResponse({ publicId, version, signature })) return invalid();
    if (resourceType !== AVATAR_LIMITS.resourceType) return invalid();
    if (typeof bytes !== 'number' || bytes <= 0) return invalid();
    if (bytes > AVATAR_LIMITS.maxBytes) {
      await destroyAsset(publicId, resourceType);
      sendError(res, 400, 'too_large', `Avatars must be at most ${AVATAR_LIMITS.maxBytes} bytes`);
      return;
    }
    if (typeof format !== 'string' || !AVATAR_LIMITS.formats.includes(format.toLowerCase())) {
      await destroyAsset(publicId, resourceType);
      return invalid();
    }

    const previous = await prisma.user.findUnique({ where: { id: req.auth.userId }, select: { avatarPublicId: true } });
    const user = await prisma.user.update({
      where: { id: req.auth.userId },
      data: { avatarPublicId: publicId, avatarUrl: avatarDeliveryUrl(publicId) },
      select: USER_SELECT,
    });
    // The `!==` guard matters only for a client that resubmits the very
    // same `publicId` (a retried request) — without it, this would destroy
    // the asset it just finished setting.
    if (previous?.avatarPublicId && previous.avatarPublicId !== publicId) {
      await destroyAsset(previous.avatarPublicId, 'image');
    }
    res.json(profilePayload(user));
  });

  router.delete('/users/me/avatar', authenticated, async (req, res) => {
    if (!writeRateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many profile updates');
      return;
    }
    const previous = await prisma.user.findUnique({ where: { id: req.auth.userId }, select: { avatarPublicId: true } });
    const user = await prisma.user.update({
      where: { id: req.auth.userId },
      data: { avatarPublicId: null, avatarUrl: null },
      select: USER_SELECT,
    });
    if (previous?.avatarPublicId) await destroyAsset(previous.avatarPublicId, 'image');
    res.json(profilePayload(user));
  });

  // Restricted to co-participants (current or former — leaving a
  // Conversation only sets `Participant.leftAt`, per ADR 0009, so this check
  // doesn't need to distinguish the two) rather than open to any signed-in
  // User, so a User's id can't be used to browse everyone's details (#43).
  router.get('/users/:id', authenticated, async (req, res) => {
    const shared = await prisma.participant.findFirst({
      where: {
        userId: req.auth.userId,
        conversation: { participants: { some: { userId: req.params.id } } },
      },
    });
    if (!shared) {
      sendError(res, 404, 'not_found', 'Not found');
      return;
    }
    const user = await prisma.user.findUnique({ where: { id: req.params.id }, select: USER_SELECT });
    if (!user) {
      sendError(res, 404, 'not_found', 'Not found');
      return;
    }
    res.json(profilePayload(user));
  });

  return router;
}
