import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import request from 'supertest';

import { echo, signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function assertUnauthenticated(res) {
  assert.equal(res.status, 401);
  assert.equal(res.body.error.code, 'unauthenticated');
}

describe('auth middleware', () => {
  it('lets a valid access token through, naming its User and Session', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);

    const res = await echo(app, `Bearer ${signedIn.accessToken}`);

    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      userId: signedIn.user.id,
      sessionId: jwt.decode(signedIn.accessToken).sessionId,
    });
  });

  it('rejects a request without an access token', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });

    assertUnauthenticated(await echo(app));
  });

  it('rejects a malformed access token or Authorization header', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    const forged = jwt.sign(jwt.decode(signedIn.accessToken), 'someone-elses-secret');

    assertUnauthenticated(await echo(app, 'Bearer not-a-jwt'));
    assertUnauthenticated(await echo(app, `Bearer ${forged}`));
    assertUnauthenticated(await echo(app, signedIn.accessToken));
    assertUnauthenticated(await echo(app, `Basic ${signedIn.accessToken}`));
  });

  it('rejects an access token once its 15 minutes are up', async () => {
    const { app, clock } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);

    clock.advance(15 * 60 * 1000 - 1000);
    const justBefore = await echo(app, `Bearer ${signedIn.accessToken}`);
    clock.advance(1000);
    const atExpiry = await echo(app, `Bearer ${signedIn.accessToken}`);

    assert.equal(justBefore.status, 200);
    assertUnauthenticated(atExpiry);
  });

  it('rejects a still-valid access token once its Session is revoked', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    await prisma.session.updateMany({ data: { revokedAt: new Date() } });

    assertUnauthenticated(await echo(app, `Bearer ${signedIn.accessToken}`));
  });

  it('rejects the access token of a Session revoked for refresh token reuse', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    const rotated = await request(app)
      .post('/auth/refresh')
      .send({ refreshToken: signedIn.refreshToken });

    await request(app).post('/auth/refresh').send({ refreshToken: signedIn.refreshToken });

    assertUnauthenticated(await echo(app, `Bearer ${rotated.body.accessToken}`));
  });

  it('rejects an access token whose Session no longer exists', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    const signedIn = await signIn(app);
    await prisma.session.deleteMany();

    assertUnauthenticated(await echo(app, `Bearer ${signedIn.accessToken}`));
  });
});
