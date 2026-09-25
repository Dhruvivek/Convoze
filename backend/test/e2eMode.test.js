import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';

import {
  TEST_OTP_CODE,
  buildTestApp,
  createTestPrisma,
  resetDatabase,
} from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

async function seedUser() {
  await prisma.user.create({
    data: { phoneNumber: '+14155550100', phoneVerifiedAt: new Date() },
  });
}

describe('e2e mode off', () => {
  it('does not mount the test-only endpoints', async () => {
    const { app } = buildTestApp({ prisma });

    const reset = await request(app).post('/__e2e__/reset');
    const faults = await request(app)
      .post('/__e2e__/faults')
      .send({ method: 'GET', path: '/health', count: 1 });

    assert.equal(reset.status, 404);
    assert.equal(faults.status, 404);
  });
});

describe('POST /__e2e__/reset', () => {
  it('empties every table', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    await seedUser();

    const res = await request(app).post('/__e2e__/reset');

    assert.equal(res.status, 204);
    assert.equal(await prisma.user.count(), 0);
  });

  it('clears pending injected faults', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    await request(app).post('/__e2e__/faults').send({ method: 'GET', path: '/health', count: 1 });

    await request(app).post('/__e2e__/reset');
    const res = await request(app).get('/health');

    assert.equal(res.status, 200);
  });
});

describe('POST /__e2e__/faults', () => {
  it('fails the next N calls to the endpoint with 503, then lets calls through', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });

    const setup = await request(app)
      .post('/__e2e__/faults')
      .send({ method: 'GET', path: '/health', count: 2 });
    const first = await request(app).get('/health');
    const second = await request(app).get('/health');
    const third = await request(app).get('/health');

    assert.equal(setup.status, 204);
    assert.equal(first.status, 503);
    assert.equal(first.body.error.code, 'fault_injected');
    assert.equal(second.status, 503);
    assert.equal(third.status, 200);
  });

  it('only affects the named method and path', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    await request(app).post('/__e2e__/faults').send({ method: 'POST', path: '/health', count: 1 });

    const res = await request(app).get('/health');

    assert.equal(res.status, 200);
  });

  it('never faults the test-only endpoints themselves', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });
    await request(app)
      .post('/__e2e__/faults')
      .send({ method: 'POST', path: '/__e2e__/reset', count: 1 });

    const res = await request(app).post('/__e2e__/reset');

    assert.equal(res.status, 204);
  });

  it('rejects an invalid fault definition', async () => {
    const { app } = buildTestApp({ prisma, e2eMode: true });

    const res = await request(app).post('/__e2e__/faults').send({ path: '/health', count: 0 });

    assert.equal(res.status, 400);
    assert.equal(res.body.error.code, 'invalid_request');
  });
});

describe('fake Verify client', () => {
  it('approves only the fixed code', async () => {
    const { verifyClient } = buildTestApp({ prisma, e2eMode: true });

    await verifyClient.sendCode('+14155550100');

    assert.equal(await verifyClient.checkCode('+14155550100', TEST_OTP_CODE), true);
    assert.equal(await verifyClient.checkCode('+14155550100', '999999'), false);
  });
});
