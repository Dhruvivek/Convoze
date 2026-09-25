import { Router } from 'express';

import { sendError } from '../http/errors.js';
import { resetDatabase } from './resetDatabase.js';

// Test-only endpoints, mounted only when E2E_MODE is on.
export function createE2eRouter({ prisma, faults }) {
  const router = Router();

  router.post('/reset', async (_req, res) => {
    await resetDatabase(prisma);
    faults.clear();
    res.status(204).end();
  });

  router.post('/faults', (req, res) => {
    const { method, path, count } = req.body ?? {};
    const valid =
      typeof method === 'string' &&
      typeof path === 'string' &&
      path.startsWith('/') &&
      Number.isInteger(count) &&
      count > 0;
    if (!valid) {
      sendError(res, 400, 'invalid_request', 'Expected { method, path, count > 0 }');
      return;
    }
    faults.inject(method, path, count);
    res.status(204).end();
  });

  return router;
}
