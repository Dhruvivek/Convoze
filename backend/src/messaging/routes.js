import { Router } from 'express';

import { isUuid } from '../auth/tokens.js';
import { sendError } from '../http/errors.js';
import { createConversationPrefsUpdater, PIN_LIMIT } from './conversationPrefs.js';
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
export function createMessagingRouter({ prisma, authenticated, wakeUser, joinUserToConversation, clock }) {
  const router = Router();
  const startDirectConversation = createDirectConversationStarter({
    prisma,
    onWake: wakeUser,
    joinUserToConversation,
  });
  const conversationPrefs = createConversationPrefsUpdater({ prisma, onWake: wakeUser, clock });

  function sendPrefsResult(res, result) {
    if (!result.ok) {
      if (result.code === 'NOT_FOUND') {
        sendError(res, 404, 'not_found', 'Not found');
      } else if (result.code === 'PIN_LIMIT') {
        sendError(res, 409, 'pin_limit', `Can't pin more than ${PIN_LIMIT} conversations`);
      } else if (result.code === 'MUST_LEAVE_GROUP') {
        sendError(res, 409, 'must_leave_group', 'Leave the group before deleting it');
      } else {
        sendError(res, 400, 'invalid_request', 'Invalid request');
      }
      return;
    }
    res.json({ ...result.conversationRow, users: result.users });
  }

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

  // #45: pin/unpin, archive/unarchive and mute/unmute, one REST call per
  // change, applying only to the caller (never seen by other Participants).
  router.patch('/:id/prefs', authenticated, async (req, res) => {
    if (!isUuid(req.params.id)) {
      sendError(res, 400, 'invalid_request', 'Expected a valid Conversation id');
      return;
    }
    const result = await conversationPrefs.updatePrefs(req.auth.userId, req.params.id, req.body);
    sendPrefsResult(res, result);
  });

  // #45: remove this caller's own history up to the newest Message, keeping
  // the Conversation in their list.
  router.post('/:id/clear', authenticated, async (req, res) => {
    if (!isUuid(req.params.id)) {
      sendError(res, 400, 'invalid_request', 'Expected a valid Conversation id');
      return;
    }
    const result = await conversationPrefs.clearHistory(req.auth.userId, req.params.id);
    sendPrefsResult(res, result);
  });

  // #45: clear plus hide the Conversation from this caller's list. A group
  // Conversation must be left first.
  router.post('/:id/delete', authenticated, async (req, res) => {
    if (!isUuid(req.params.id)) {
      sendError(res, 400, 'invalid_request', 'Expected a valid Conversation id');
      return;
    }
    const result = await conversationPrefs.deleteChat(req.auth.userId, req.params.id);
    sendPrefsResult(res, result);
  });

  return router;
}
