import { Router } from 'express';

import { DEFAULT_TOKEN_TTLS } from '../auth/tokenTtls.js';
import { sendError } from '../http/errors.js';
import { resetDatabase } from './resetDatabase.js';

// Test-only endpoints, mounted only when E2E_MODE is on.
export function createE2eRouter({ prisma, faults, refreshCounter, authenticated, tokenTtls }) {
  const router = Router();

  router.post('/reset', async (_req, res) => {
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

  // A protected route like any other, for exercising the real auth middleware.
  router.get('/echo', authenticated, (req, res) => {
    res.json(req.auth);
  });

  return router;
}
