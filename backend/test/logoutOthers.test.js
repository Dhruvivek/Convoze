import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';

import { echo, logout, logoutOthers, refresh, signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const DEVICE_B = '0199a1b2-0000-4000-8000-00000000000b';
const DEVICE_C = '0199a1b2-0000-4000-8000-00000000000c';

function assertError(res, status, code) {
  assert.equal(res.status, status);
  assert.equal(res.body.error.code, code);
}

function sessionIdOf(signedIn) {
  return jwt.decode(signedIn.accessToken).sessionId;
}

function bySessionId(a, b) {
  return a.sessionId.localeCompare(b.sessionId);
}

function recordRevocations(sessionRevoked) {
  const events = [];
  sessionRevoked.subscribe((event) => events.push(event));
  return events;
}

describe('POST /auth/sessions/logout-others', () => {
  it("ends every other Session of the User and keeps the caller's", async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const thisDevice = await signIn(app);
    const deviceB = await signIn(app, { deviceId: DEVICE_B });
    const deviceC = await signIn(app, { deviceId: DEVICE_C });

    const res = await logoutOthers(app, `Bearer ${thisDevice.accessToken}`);

    assert.equal(res.status, 204);
    for (const other of [deviceB, deviceC]) {
      assertError(await refresh(app, other.refreshToken), 401, 'invalid_refresh_token');
      assertError(await echo(app, `Bearer ${other.accessToken}`), 401, 'unauthenticated');
    }
    assert.equal((await echo(app, `Bearer ${thisDevice.accessToken}`)).status, 200);
    assert.equal((await refresh(app, thisDevice.refreshToken)).status, 200);
  });

  it("leaves other Users' Sessions working", async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const mine = await signIn(app);
    const someoneElse = await signIn(app, { phoneNumber: '+14155550199', deviceId: DEVICE_B });

    await logoutOthers(app, `Bearer ${mine.accessToken}`);

    assert.equal((await echo(app, `Bearer ${someoneElse.accessToken}`)).status, 200);
  });

  it('fires the session-revoked hook once per revoked Session', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const thisDevice = await signIn(app);
    const deviceB = await signIn(app, { deviceId: DEVICE_B });
    const deviceC = await signIn(app, { deviceId: DEVICE_C });
    // Already ended, so there's nothing left to revoke.
    const deviceD = await signIn(app, { deviceId: '0199a1b2-0000-4000-8000-00000000000d' });
    await logout(app, `Bearer ${deviceD.accessToken}`);
    const events = recordRevocations(sessionRevoked);

    await Promise.all([
      logoutOthers(app, `Bearer ${thisDevice.accessToken}`),
      logoutOthers(app, `Bearer ${thisDevice.accessToken}`),
    ]);

    const userId = thisDevice.user.id;
    assert.deepEqual(
      events.toSorted(bySessionId),
      [
        { sessionId: sessionIdOf(deviceB), userId },
        { sessionId: sessionIdOf(deviceC), userId },
      ].toSorted(bySessionId),
    );
  });

  it('requires a valid access token', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);
    await logout(app, `Bearer ${signedIn.accessToken}`);

    assertError(await logoutOthers(app), 401, 'unauthenticated');
    assertError(await logoutOthers(app, 'Bearer not-a-jwt'), 401, 'unauthenticated');
    assertError(await logoutOthers(app, `Bearer ${signedIn.accessToken}`), 401, 'unauthenticated');
  });
});
