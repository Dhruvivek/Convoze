import { createServer } from 'node:http';
import express from 'express';

import { createAuthenticator, requireAuth } from './auth/authenticate.js';
import { createAuthRouter } from './auth/routes.js';
import { createSessionRevokedHook } from './auth/sessionRevoked.js';
import { createTokenTtls } from './auth/tokenTtls.js';
import { createFaultInjector } from './e2e/faults.js';
import { createRefreshCounter } from './e2e/refreshCounter.js';
import { createE2eRouter } from './e2e/routes.js';
import { errorHandler, notFoundHandler } from './http/errors.js';
import { createMessagingRouter } from './messaging/routes.js';
import { createRealtime } from './realtime/server.js';

// Builds the server from its dependencies, so tests and production wire
// different implementations (fake Verify client, controllable clock, ...):
// the Express `app`, and the `httpServer` that serves it with the realtime
// Socket.IO server attached. Whoever needs to hear about revoked Sessions
// subscribes to `sessionRevoked`.
export function createApp({
  prisma,
  verifyClient,
  clock,
  jwtSecret,
  sessionRevoked = createSessionRevokedHook(),
  e2eMode = false,
  pumpOptions,
}) {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());
  const tokenTtls = createTokenTtls();
  const authenticate = createAuthenticator({ prisma, jwtSecret, clock });
  const authenticated = requireAuth(authenticate);
  // Created ahead of `realtime` so its socket-event fault injection (#54) is
  // wired in from the first connection, not just once the e2e router mounts.
  const faults = e2eMode ? createFaultInjector() : undefined;
  const realtime = createRealtime({ prisma, authenticate, clock, sessionRevoked, pumpOptions, faults });

  if (e2eMode) {
    const refreshCounter = createRefreshCounter();
    // The router goes first so a fault can never break the test-only endpoints.
    app.use(
      '/__e2e__',
      createE2eRouter({
        prisma,
        clock,
        realtime,
        faults,
        refreshCounter,
        authenticated,
        tokenTtls,
      }),
    );
    // Counted ahead of faults, so a refresh made to fail still counts.
    app.post('/auth/refresh', refreshCounter.middleware);
    app.use(faults.middleware);
  }

  app.get('/health', async (_req, res) => {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ status: 'ok' });
  });

  app.use(
    '/auth',
    createAuthRouter({
      prisma,
      verifyClient,
      clock,
      jwtSecret,
      tokenTtls,
      sessionRevoked,
      authenticated,
    }),
  );

  app.use(
    '/conversations',
    createMessagingRouter({
      prisma,
      authenticated,
      wakeUser: realtime.wakeUser,
      joinUserToConversation: realtime.joinUserToConversation,
    }),
  );

  app.use(notFoundHandler);
  app.use(errorHandler);

  const httpServer = createServer(app);
  realtime.io.attach(httpServer);
  return { app, httpServer, realtime };
}
