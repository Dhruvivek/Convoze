import { Router } from 'express';

import { sendError } from '../http/errors.js';
import { createSendRateLimit } from '../messaging/rateLimiter.js';
import { deliveryUrls, MEDIA_LIMITS, signUpload } from './cloudinarySigner.js';

// `POST /media/upload-signature` and `GET /messages/:id/media` (#40,
// reduced scope): the two media endpoints that don't belong under
// `/conversations` — signing an upload before it happens, and refreshing a
// delivery URL after it has expired.
export function createMediaRouter({ prisma, authenticated, clock }) {
  const router = Router();
  // 60 signature requests per user per 10 minutes — same shape as the
  // per-sender send limit, just its own independent window.
  const signatureRateLimit = createSendRateLimit({ clock, limit: 60, windowMs: 10 * 60 * 1000 });

  router.post('/media/upload-signature', authenticated, (req, res) => {
    const { kind } = req.body ?? {};
    if (kind !== 'image' && kind !== 'file') {
      sendError(res, 400, 'invalid_request', "kind must be 'image' or 'file'");
      return;
    }
    if (!signatureRateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many upload signatures requested');
      return;
    }
    res.json(signUpload({ userId: req.auth.userId, kind }));
  });

  router.get('/messages/:id/media', authenticated, async (req, res) => {
    const message = await prisma.message.findUnique({ where: { id: req.params.id } });
    if (!message || !message.mediaPublicId || message.isDeleted) {
      sendError(res, 404, 'not_found', 'Not found');
      return;
    }
    // Same collapsed-404 as the rest of messaging: a non-Participant can't
    // tell "no such message" from "not yours to see" apart.
    const participant = await prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId: message.conversationId, userId: req.auth.userId } },
    });
    if (!participant) {
      sendError(res, 404, 'not_found', 'Not found');
      return;
    }
    res.json(deliveryUrls({ publicId: message.mediaPublicId, resourceType: message.mediaResourceType }));
  });

  return router;
}

export { MEDIA_LIMITS };
