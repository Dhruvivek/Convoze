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
const CAROL = '+14155550102';

function auth(token) {
  return `Bearer ${token}`;
}

describe('GET /users', () => {
  it('requires authentication', async () => {
    const { app } = buildTestApp({ prisma });
    const res = await request(app).get('/users');
    assert.equal(res.status, 401);
  });

  it('lists every other registered User, excluding the caller', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });

    const res = await request(app).get('/users').set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
    const ids = res.body.users.map((u) => u.id).sort();
    assert.deepEqual(ids, [bob.user.id, carol.user.id].sort());
    assert.ok(!ids.includes(alice.user.id));
    assert.ok(res.body.users.every((u) => typeof u.phoneNumber === 'string'));
  });

  it('returns an empty list when no one else is registered', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app).get('/users').set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
    assert.deepEqual(res.body.users, []);
  });
});
