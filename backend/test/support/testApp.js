import { createApp } from '../../src/app.js';
import { createPrismaClient } from '../../src/db.js';
import { resetDatabase } from '../../src/e2e/resetDatabase.js';
import { createFakeVerifyClient } from '../../src/verify/fakeVerifyClient.js';
import { createFakeClock } from './fakeClock.js';

export const TEST_OTP_CODE = '123456';

export function testDatabaseUrl() {
  const url = process.env.TEST_DATABASE_URL;
  if (!url) throw new Error('TEST_DATABASE_URL must be set to run the backend tests');
  return url;
}

// One Prisma client per test file; callers disconnect it in `after`.
export function createTestPrisma() {
  return createPrismaClient(testDatabaseUrl());
}

export function buildTestApp({ prisma, e2eMode = false } = {}) {
  const clock = createFakeClock();
  const verifyClient = createFakeVerifyClient({ code: TEST_OTP_CODE });
  const app = createApp({
    prisma,
    verifyClient,
    clock,
    jwtSecret: 'test-jwt-secret',
    e2eMode,
  });
  return { app, clock, verifyClient };
}

export { resetDatabase };
