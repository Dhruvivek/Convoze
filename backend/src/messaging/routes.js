import { Router } from 'express';

import { isUuid } from '../auth/tokens.js';
import { sendError } from '../http/errors.js';
import { createDirectConversationStarter } from './directConversation.js';
import { listConversations } from './listConversations.js';
import { listMessages } from './messageHistory.js';

// A positive integer from a query param, or `undefined` (falls back to the
// callee's default) — `NaN`/`{ok:false}` sentinels here so a bad `limit`
// value can't silently turn into "no limit".
function parseLimit(raw) {
  if (raw === undefined) return { ok: true, value: undefined };
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) return { ok: false };
  return { ok: true, value };
}

// The REST surface a Device uses for anything it can't get live (#50): the
// Conversation list, message history paging, and starting a direct chat.
export function createMessagingRouter({ prisma, authenticated, wakeUser, joinUserToConversation }) {
  const router = Router();
  const startDirectConversation = createDirectConversationStarter({
    prisma,
    onWake: wakeUser,
    joinUserToConversation,
  });

  router.get('/', authenticated, async (req, res) => {
    const { cursor, limit: rawLimit } = req.query;
    if (cursor !== undefined && !isUuid(cursor)) {
      sendError(res, 400, 'invalid_request', 'cursor must be a Message or Conversation id');
      return;
    }
    const limit = parseLimit(rawLimit);
    if (!limit.ok) {
      sendError(res, 400, 'invalid_request', 'limit must be a positive integer');
      return;
    }
    const result = await listConversations(prisma, req.auth.userId, { cursor, limit: limit.value });
    res.json(result);
  });

  router.get('/:id/messages', authenticated, async (req, res) => {
    const { before, limit: rawLimit } = req.query;
    const limit = parseLimit(rawLimit);
    if (!limit.ok) {
      sendError(res, 400, 'invalid_request', 'limit must be a positive integer');
      return;
    }
    const result = await listMessages(prisma, req.auth.userId, req.params.id, {
      before,
      limit: limit.value,
    });
    if (!result.ok) {
      if (result.code === 'NOT_PARTICIPANT') {
        // Collapsed with "no such Conversation" (never a distinct 404
        // message) so a probe can't tell the two apart.
        sendError(res, 404, 'not_found', 'Not found');
      } else {
        sendError(res, 400, 'invalid_request', 'Expected a valid Conversation id and before');
      }
      return;
    }
    res.json({ messages: result.messages, nextBefore: result.nextBefore, users: result.users });
  });

  router.post('/direct', authenticated, async (req, res) => {
    const result = await startDirectConversation(req.auth.userId, req.body);
    if (!result.ok) {
      if (result.code === 'NOT_FOUND') {
        sendError(res, 404, 'not_found', "That user doesn't exist");
      } else if (result.code === 'SELF') {
        sendError(res, 400, 'invalid_request', "Can't start a Conversation with yourself");
      } else {
        sendError(res, 400, 'invalid_request', 'Expected { userId }');
      }
      return;
    }
    const { conversation, created, participants, users } = result;
    res.status(created ? 201 : 200).json({
      id: conversation.id,
      type: conversation.type,
      name: conversation.name,
      participants,
      createdAt: conversation.createdAt,
      users,
    });
  });

  return router;
}
