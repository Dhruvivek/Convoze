import express from 'express';

import { createFaultInjector } from './e2e/faults.js';
import { createE2eRouter } from './e2e/routes.js';
import { errorHandler, notFoundHandler } from './http/errors.js';

// Builds the Express app from its dependencies, so tests and production wire
// different implementations (fake Verify client, controllable clock, ...).
export function createApp({ prisma, verifyClient, clock, jwtSecret, e2eMode = false }) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());

  if (e2eMode) {
    const faults = createFaultInjector();
    // The router goes first so a fault can never break the test-only endpoints.
    app.use('/__e2e__', createE2eRouter({ prisma, faults }));
    app.use(faults.middleware);
  }

  app.get('/health', async (_req, res) => {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  });

  // Consumed by the auth routes that land in #23 onwards.
  app.locals.deps = { verifyClient, clock, jwtSecret };

  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
