import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';
import { MAX_CONTACT_NUMBERS } from '../src/users/matchContacts.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const ALICE = '+14155550100';
const BOB = '+14155550101';
const CAROL = '+919876543210';

function auth(token) {
  return `Bearer ${token}`;
}

describe('POST /users/match', () => {
  it('requires authentication', async () => {
    const { app } = buildTestApp({ prisma });
    const res = await request(app).post('/users/match').send({ phoneNumbers: [] });
    assert.equal(res.status, 401);
  });

  it('matches registered Users by exact E.164 number, excluding the caller', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    await signIn(app, { phoneNumber: CAROL, deviceId: '0199a1b2-0000-4000-8000-00000000000b' });

    const res = await request(app)
      .post('/users/match')
      .set('Authorization', auth(alice.accessToken))
      .send({ phoneNumbers: [ALICE, BOB, '+15555550199'] });

    assert.equal(res.status, 200);
    assert.deepEqual(
      res.body.users.map((u) => u.id),
      [bob.user.id],
    );
  });

  it('falls back to the caller’s own region for numbers with no country code', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });

    // BOB's national number, as a device contact might have it saved.
    const res = await request(app)
      .post('/users/match')
      .set('Authorization', auth(alice.accessToken))
      .send({ phoneNumbers: ['(415) 555-0101'] });

    assert.equal(res.status, 200);
    assert.deepEqual(
      res.body.users.map((u) => u.id),
      [bob.user.id],
    );
  });

  it('rejects a non-array phoneNumbers field', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/users/match')
      .set('Authorization', auth(alice.accessToken))
      .send({ phoneNumbers: 'not-an-array' });

    assert.equal(res.status, 400);
  });

  it('rejects more numbers than the cap', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/users/match')
      .set('Authorization', auth(alice.accessToken))
      .send({ phoneNumbers: Array.from({ length: MAX_CONTACT_NUMBERS + 1 }, () => ALICE) });

    assert.equal(res.status, 400);
  });
});
