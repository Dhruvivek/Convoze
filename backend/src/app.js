import express from 'express';

import { createAuthenticator, requireAuth } from './auth/authenticate.js';
import { createAuthRouter } from './auth/routes.js';
import { createTokenTtls } from './auth/tokenTtls.js';
import { createFaultInjector } from './e2e/faults.js';
import { createRefreshCounter } from './e2e/refreshCounter.js';
import { createE2eRouter } from './e2e/routes.js';
import { errorHandler, notFoundHandler } from './http/errors.js';

// Builds the Express app from its dependencies, so tests and production wire
// different implementations (fake Verify client, controllable clock, ...).
export function createApp({ prisma, verifyClient, clock, jwtSecret, e2eMode = false }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());
  const tokenTtls = createTokenTtls();
  const authenticated = requireAuth(createAuthenticator({ prisma, jwtSecret, clock }));

  if (e2eMode) {
    const faults = createFaultInjector();
    const refreshCounter = createRefreshCounter();
    // The router goes first so a fault can never break the test-only endpoints.
    app.use(
      '/__e2e__',
      createE2eRouter({ prisma, faults, refreshCounter, authenticated, tokenTtls }),
    );
    // Counted ahead of faults, so a refresh made to fail still counts.
    app.post('/auth/refresh', refreshCounter.middleware);
    app.use(faults.middleware);
  }

  app.get('/health', async (_req, res) => {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  });

  app.use('/auth', createAuthRouter({ prisma, verifyClient, clock, jwtSecret, tokenTtls }));

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
