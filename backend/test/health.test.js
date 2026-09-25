import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';

import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

describe('GET /health', () => {
  it('reports ok when the database is reachable', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app).get('/health');

    assert.equal(res.status, 200);
    assert.deepEqual(res.body, { status: 'ok' });
  });

  it('answers unknown routes with the standard error shape', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app).get('/nope');

    assert.equal(res.status, 404);
    assert.equal(res.body.error.code, 'not_found');
  });
});

describe('schema', () => {
  it('generates UUIDv7 primary keys in the database', async () => {
    const user = await prisma.user.create({
      data: { phoneNumber: '+14155550100', phoneVerifiedAt: new Date() },
    });

    // UUIDv7: version nibble is 7.
    assert.match(user.id, /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/);
  });
});
