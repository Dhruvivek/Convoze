import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import request from 'supertest';

import { echo, refresh, signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function setTokenTtls(app, ttls) {
  return request(app).post('/__e2e__/token-ttls').send(ttls);
}

describe('POST /__e2e__/token-ttls', () => {
  it('shortens the access token lifetime', async () => {
    const { app, clock } = buildTestApp({ prisma, e2eMode: true });
    await setTokenTtls(app, { accessTokenSeconds: 2 });
    const signedIn = await signIn(app);

    const fresh = await echo(app, `Bearer ${signedIn.accessToken}`);
    clock.advance(2000);
    const expired = await echo(app, `Bearer ${signedIn.accessToken}`);
    const refreshed = await refresh(app, signedIn.refreshToken);
    clock.advance(1000);
    const renewed = await echo(app, `Bearer ${refreshed.body.accessToken}`);

    assert.equal(fresh.status, 200);
    assert.equal(expired.status, 401);
    assert.equal(renewed.status, 200);
    const { iat, exp } = jwt.decode(refreshed.body.accessToken);
    assert.equal(exp - iat, 2);
  });

  it('shortens the refresh token lifetime', async () => {
    const { app, clock } = buildTestApp({ prisma, e2eMode: true });
    await setTokenTtls(app, { refreshTokenSeconds: 5 });
    const signedIn = await signIn(app);

    clock.advance(4000);
    const inTime = await refresh(app, signedIn.refreshToken);
    clock.advance(5000);
    const tooLate = await refresh(app, inTime.body.refreshToken);

    assert.equal(inTime.status, 200);
    assert.equal(tooLate.status, 401);
  });

  it('goes back to the real lifetimes on reset', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    await setTokenTtls(app, { accessTokenSeconds: 2, refreshTokenSeconds: 5 });

    await request(app).post('/__e2e__/reset');
    const signedIn = await signIn(app);

    const { iat, exp } = jwt.decode(signedIn.accessToken);
    assert.equal(exp - iat, 15 * 60);
    const session = await prisma.session.findFirst();
    assert.equal(session.expiresAt - session.issuedAt, 30 * 24 * 60 * 60 * 1000);
  });

  it('rejects anything but positive whole seconds for known TTLs', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });

    for (const body of [
      { accessTokenSeconds: 0 },
      { refreshTokenSeconds: 1.5 },
      { accessTokenSeconds: '60' },
      { sessionSeconds: 60 },
    ]) {
      const res = await setTokenTtls(app, body);
      assert.equal(res.status, 400, JSON.stringify(body));
      assert.equal(res.body.error.code, 'invalid_request');
    }
  });
});

describe('GET /__e2e__/sessions/:sessionId/refresh-count', () => {
  function refreshCount(app, sessionId) {
    return request(app).get(`/__e2e__/sessions/${sessionId}/refresh-count`);
  }

  it('counts every refresh call made for a Session, accepted or not', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    const sessionId = jwt.decode(signedIn.accessToken).sessionId;

    const before = await refreshCount(app, sessionId);
    const rotated = await refresh(app, signedIn.refreshToken);
    await refresh(app, rotated.body.refreshToken);
    await refresh(app, `${sessionId}.wrong-secret`);
    const after = await refreshCount(app, sessionId);

    assert.deepEqual(before.body, { count: 0 });
    assert.deepEqual(after.body, { count: 3 });
  });

  it('counts each Session separately', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const first = await signIn(app);
    const second = await signIn(app);

    await refresh(app, first.refreshToken);

    const secondId = jwt.decode(second.accessToken).sessionId;
    assert.deepEqual((await refreshCount(app, secondId)).body, { count: 0 });
  });

  it('starts again from zero on reset', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    const sessionId = jwt.decode(signedIn.accessToken).sessionId;
    await refresh(app, signedIn.refreshToken);

    await request(app).post('/__e2e__/reset');

    assert.deepEqual((await refreshCount(app, sessionId)).body, { count: 0 });
  });
});
