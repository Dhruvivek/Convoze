import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';

import { echo, logout, refresh, signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const OTHER_DEVICE = '0199a1b2-0000-4000-8000-00000000000b';

function assertError(res, status, code) {
  assert.equal(res.status, status);
  assert.equal(res.body.error.code, code);
}

describe('POST /auth/logout', () => {
  it("ends the calling Session: its refresh and access tokens stop working", async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);

    const res = await logout(app, `Bearer ${signedIn.accessToken}`);

    assert.equal(res.status, 204);
    assertError(await refresh(app, signedIn.refreshToken), 401, 'invalid_refresh_token');
    assertError(await echo(app, `Bearer ${signedIn.accessToken}`), 401, 'unauthenticated');
  });

  it("leaves the User's Sessions on other Devices working", async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const thisDevice = await signIn(app);
    const otherDevice = await signIn(app, { deviceId: OTHER_DEVICE });

    await logout(app, `Bearer ${thisDevice.accessToken}`);

    assert.equal((await echo(app, `Bearer ${otherDevice.accessToken}`)).status, 200);
    assert.equal((await refresh(app, otherDevice.refreshToken)).status, 200);
  });

  it('requires a valid access token', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);
    await logout(app, `Bearer ${signedIn.accessToken}`);

    assertError(await logout(app), 401, 'unauthenticated');
    assertError(await logout(app, 'Bearer not-a-jwt'), 401, 'unauthenticated');
    assertError(await logout(app, `Bearer ${signedIn.accessToken}`), 401, 'unauthenticated');
  });
});

describe('session-revoked hook', () => {
  function recordRevocations(sessionRevoked) {
    const events = [];
    sessionRevoked.subscribe((event) => events.push(event));
    return events;
  }

  it('fires with the Session and its User on logout', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const events = recordRevocations(sessionRevoked);
    const signedIn = await signIn(app);

    await logout(app, `Bearer ${signedIn.accessToken}`);

    assert.deepEqual(events, [
      { sessionId: jwt.decode(signedIn.accessToken).sessionId, userId: signedIn.user.id },
    ]);
  });

  it('fires once when refresh token reuse revokes the Session', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const events = recordRevocations(sessionRevoked);
    const signedIn = await signIn(app);
    await refresh(app, signedIn.refreshToken);

    await Promise.all([refresh(app, signedIn.refreshToken), refresh(app, signedIn.refreshToken)]);

    assert.deepEqual(events, [
      { sessionId: jwt.decode(signedIn.accessToken).sessionId, userId: signedIn.user.id },
    ]);
  });

  it('fires once when concurrent refreshes with one token count as reuse', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const events = recordRevocations(sessionRevoked);
    const signedIn = await signIn(app);

    await Promise.all(Array.from({ length: 5 }, () => refresh(app, signedIn.refreshToken)));

    assert.deepEqual(events, [
      { sessionId: jwt.decode(signedIn.accessToken).sessionId, userId: signedIn.user.id },
    ]);
  });

  it('does not fire on sign-in or an ordinary refresh', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const events = recordRevocations(sessionRevoked);
    const signedIn = await signIn(app);

    await refresh(app, signedIn.refreshToken);

    assert.deepEqual(events, []);
  });

  it('still logs out when a subscriber throws', async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma, e2eMode: true });
    sessionRevoked.subscribe(() => {
      throw new Error('subscriber failed');
    });
    const signedIn = await signIn(app);

    const res = await logout(app, `Bearer ${signedIn.accessToken}`);

    assert.equal(res.status, 204);
    assertError(await refresh(app, signedIn.refreshToken), 401, 'invalid_refresh_token');
  });
});
