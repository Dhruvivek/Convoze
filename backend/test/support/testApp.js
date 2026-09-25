import { createApp } from '../../src/app.js';
import { createSessionRevokedHook } from '../../src/auth/sessionRevoked.js';
import { createPrismaClient } from '../../src/db.js';
import { resetDatabase } from '../../src/e2e/resetDatabase.js';
import { createFakeVerifyClient } from '../../src/verify/fakeVerifyClient.js';
import { createFakeClock } from './fakeClock.js';

export const TEST_OTP_CODE = '123456';
export const TEST_JWT_SECRET = 'test-jwt-secret';

export function testDatabaseUrl() {
  const url = process.env.TEST_DATABASE_URL;
  if (!url) throw new Error('TEST_DATABASE_URL must be set to run the backend tests');
  return url;
}

// One Prisma client per test file; callers disconnect it in `after`.
export function createTestPrisma() {
  return createPrismaClient(testDatabaseUrl());
}

export function buildTestApp({ prisma, e2eMode = false, pumpOptions } = {}) {
  const clock = createFakeClock();
  const verifyClient = createFakeVerifyClient({ code: TEST_OTP_CODE });
  const sessionRevoked = createSessionRevokedHook();
  const { app, httpServer, realtime } = createApp({
    prisma,
    verifyClient,
    clock,
    jwtSecret: TEST_JWT_SECRET,
    sessionRevoked,
    e2eMode,
    pumpOptions,
  });
  return { app, httpServer, realtime, clock, verifyClient, sessionRevoked };
}

export { resetDatabase };
