import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const ALICE = '+14155550100';
const BOB = '+14155550101';

function auth(token) {
  return `Bearer ${token}`;
}

describe('GET /users/lookup', () => {
  it('requires authentication', async () => {
    const { app } = buildTestApp({ prisma });
    const res = await request(app).get('/users/lookup').query({ phoneNumber: BOB });
    assert.equal(res.status, 401);
  });

  it('finds a registered User by exact phone number', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });

    const res = await request(app)
      .get('/users/lookup')
      .set('Authorization', auth(alice.accessToken))
      .query({ phoneNumber: BOB });

    assert.equal(res.status, 200);
    assert.equal(res.body.user.id, bob.user.id);
  });

  it('returns null for a number nobody has registered', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .get('/users/lookup')
      .set('Authorization', auth(alice.accessToken))
      .query({ phoneNumber: '+15555550199' });

    assert.equal(res.status, 200);
    assert.equal(res.body.user, null);
  });

  it('returns null rather than matching the caller’s own number', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .get('/users/lookup')
      .set('Authorization', auth(alice.accessToken))
      .query({ phoneNumber: ALICE });

    assert.equal(res.status, 200);
    assert.equal(res.body.user, null);
  });

  it('rejects a missing phoneNumber', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app).get('/users/lookup').set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 400);
  });
});
