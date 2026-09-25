import { Router } from 'express';

import { DEFAULT_TOKEN_TTLS } from '../auth/tokenTtls.js';
import { sendError } from '../http/errors.js';
import { resetDatabase } from './resetDatabase.js';
import { seedConversation } from './seedConversation.js';
import { seedMessages } from './seedMessages.js';

// The event the emit endpoint sends, which no feature listens for.
export const E2E_TEST_EVENT = 'e2e:test';

// Test-only endpoints, mounted only when E2E_MODE is on.
export function createE2eRouter({
  prisma,
  clock,
  realtime,
  faults,
  refreshCounter,
  authenticated,
  tokenTtls,
}) {
  const router = Router();

  router.post('/reset', async (_req, res) => {
    // Sockets of the Users about to be deleted would otherwise stay open.
    realtime.io.disconnectSockets(true);
    await resetDatabase(prisma);
    faults.clear();
    refreshCounter.clear();
    Object.assign(tokenTtls, DEFAULT_TOKEN_TTLS);
    res.status(204).end();
  });

  router.post('/faults', (req, res) => {
    const { method, path, count, status, code } = req.body ?? {};
    const valid =
      typeof method === 'string' &&
      typeof path === 'string' &&
      path.startsWith('/') &&
      Number.isInteger(count) &&
      count > 0 &&
      (status === undefined || (Number.isInteger(status) && status >= 400 && status <= 599)) &&
      (code === undefined || (typeof code === 'string' && code.length > 0));
    if (!valid) {
      sendError(
        res,
        400,
        'invalid_request',
        'Expected { method, path, count > 0, status?: 4xx | 5xx, code?: string }',
      );
      return;
    }
    faults.inject(method, path, count, { status, code });
    res.status(204).end();
  });

  // Shortens token lifetimes until the next reset, so expiry can be tested
  // in seconds.
  router.post('/token-ttls', (req, res) => {
    const ttls = req.body ?? {};
    const keys = Object.keys(DEFAULT_TOKEN_TTLS);
    const valid =
      Object.keys(ttls).every((key) => keys.includes(key)) &&
      Object.values(ttls).every((ttl) => Number.isInteger(ttl) && ttl > 0);
    if (!valid) {
      sendError(
        res,
        400,
        'invalid_request',
        'Expected { accessTokenSeconds?: int > 0, refreshTokenSeconds?: int > 0 }',
      );
      return;
    }
    Object.assign(tokenTtls, ttls);
    res.status(204).end();
  });

  router.get('/sessions/:sessionId/refresh-count', (req, res) => {
    res.json({ count: refreshCounter.count(req.params.sessionId) });
  });

  // Already-connected Participants join the new Conversation's room right
  // away, as any code creating Participant rows must (#30).
  router.post('/conversations', async (req, res) => {
    const conversation = await seedConversation(prisma, req.body ?? {}, clock.now());
    if (!conversation) {
      sendError(
        res,
        400,
        'invalid_request',
        'Expected { type: "direct" | "group", name?: string (groups only), participantPhoneNumbers: [2 for direct, 1+ for group] }',
      );
      return;
    }
    for (const { userId } of conversation.participants) {
      realtime.joinUserToConversation({ userId, conversationId: conversation.id });
    }
    res.status(201).json(conversation);
  });

  // Fast-fills a Conversation's history for the pagination e2e suite (#55):
  // direct Prisma inserts, bypassing `message:send`/the Update log entirely
  // (mirrors `seedConversation` above) — a Device only ever sees these
  // through `GET .../messages`, never a live Update.
  router.post('/conversations/:conversationId/messages/seed', async (req, res) => {
    const { count, senderId } = req.body ?? {};
    const result = await seedMessages(prisma, req.params.conversationId, { count, senderId });
    if (!result) {
      sendError(
        res,
        400,
        'invalid_request',
        'Expected { count: int > 0, senderId: uuid }',
      );
      return;
    }
    res.status(201).json(result);
  });

  // Removes a Participant, taking any of their live sockets out of the
  // Conversation's room right away, as any code deleting Participant rows
  // must (#30).
  router.delete('/conversations/:conversationId/participants/:userId', async (req, res) => {
    const { conversationId, userId } = req.params;
    const { count } = await prisma.participant.deleteMany({
      where: { conversationId, userId },
    });
    if (count > 0) realtime.removeUserFromConversation({ userId, conversationId });
    res.status(204).end();
  });

  // Sends `payload` as an `e2e:test` event to everyone in `room`, so room
  // membership can be checked before any feature emits events.
  router.post('/emit', (req, res) => {
    const { room, payload = {} } = req.body ?? {};
    if (typeof room !== 'string' || room.length === 0) {
      sendError(res, 400, 'invalid_request', 'Expected { room, payload? }');
      return;
    }
    realtime.io.to(room).emit(E2E_TEST_EVENT, payload);
    res.status(204).end();
  });

  // How many live sockets the server holds for the Session.
  router.get('/sessions/:sessionId/sockets', (req, res) => {
    res.json({ count: realtime.registry.socketsForSession(req.params.sessionId).length });
  });

  // Drops the Session's live sockets' transports without a server-initiated
  // disconnect, simulating a network drop so the client's own reconnect logic
  // runs (#31).
  router.post('/sessions/:sessionId/drop-transport', (req, res) => {
    realtime.dropTransports(req.params.sessionId);
    res.status(204).end();
  });

  // A protected route like any other, for exercising the real auth middleware.
  router.get('/echo', authenticated, (req, res) => {
    res.json(req.auth);
  });

  // Deletes every UserUpdate row for the User, simulating the retention job
  // (#50) having pruned the whole log (#51): their next connect finds a gap
  // between their stored `since` and the (now nonexistent) oldest retained
  // row, so `resolveStartSeq` sends them down the `sync:reset` path.
  router.post('/users/:userId/expire-updates', async (req, res) => {
    await prisma.userUpdate.deleteMany({ where: { userId: req.params.userId } });
    res.status(204).end();
  });

  return router;
}
