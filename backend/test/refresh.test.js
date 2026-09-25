import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import request from 'supertest';

import { refresh, signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const DAY = 24 * 60 * 60 * 1000;

function assertError(res, status, code) {
  assert.equal(res.status, status);
  assert.equal(res.body.error.code, code);
}

describe('POST /auth/refresh', () => {
  it('rotates the refresh token and issues a new pair for the same Session', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);

    const res = await refresh(app, signedIn.refreshToken);

    assert.equal(res.status, 200);
    assert.notEqual(res.body.refreshToken, signedIn.refreshToken);
    assert.equal(
      jwt.decode(res.body.accessToken).sessionId,
      jwt.decode(signedIn.accessToken).sessionId,
    );
    assert.equal(jwt.decode(res.body.accessToken).sub, signedIn.user.id);
  });

  it('rejects the refresh token it replaced', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);
    await refresh(app, signedIn.refreshToken);

    const res = await refresh(app, signedIn.refreshToken);

    assertError(res, 401, 'invalid_refresh_token');
  });

  it('treats reuse of a replaced token as theft and revokes the Session', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);
    const rotated = await refresh(app, signedIn.refreshToken);

    await refresh(app, signedIn.refreshToken);
    const res = await refresh(app, rotated.body.refreshToken);

    assertError(res, 401, 'invalid_refresh_token');
  });

  it('lets exactly one of many concurrent refreshes with the same token succeed', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);

    const results = await Promise.all(
      Array.from({ length: 20 }, () => refresh(app, signedIn.refreshToken)),
    );

    assert.equal(results.filter((r) => r.status === 200).length, 1);
    for (const r of results.filter((r) => r.status !== 200)) {
      assertError(r, 401, 'invalid_refresh_token');
    }
  });

  it('rejects a refresh token unused for 30 days', async () => {
    const { app, clock } = buildTestApp({ prisma });
    const signedIn = await signIn(app);

    clock.advance(30 * DAY);
    const res = await refresh(app, signedIn.refreshToken);

    assertError(res, 401, 'invalid_refresh_token');
  });

  it('slides the 30 days forward on every refresh', async () => {
    const { app, clock } = buildTestApp({ prisma });
    const signedIn = await signIn(app);

    clock.advance(30 * DAY - 1);
    const first = await refresh(app, signedIn.refreshToken);
    clock.advance(30 * DAY - 1);
    const second = await refresh(app, first.body.refreshToken);
    clock.advance(30 * DAY);
    const third = await refresh(app, second.body.refreshToken);

    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    assertError(third, 401, 'invalid_refresh_token');
  });

  it('rejects a refresh token for a Session that does not exist', async () => {
    const { app } = buildTestApp({ prisma });
    const signedIn = await signIn(app);
    const secret = signedIn.refreshToken.split('.')[1];

    const unknownSession = await refresh(app, `0199a1b2-0000-7000-8000-000000000000.${secret}`);
    const notAToken = await refresh(app, 'not-a-token');
    const notAUuid = await refresh(app, `not-a-uuid.${secret}`);

    assertError(unknownSession, 401, 'invalid_refresh_token');
    assertError(notAToken, 401, 'invalid_refresh_token');
    assertError(notAUuid, 401, 'invalid_refresh_token');
  });

  it('rejects a body without a refresh token', async () => {
    const { app } = buildTestApp({ prisma });

    const missing = await request(app).post('/auth/refresh').send({});
    const numeric = await refresh(app, 42);

    assertError(missing, 400, 'invalid_request');
    assertError(numeric, 400, 'invalid_request');
  });
});
