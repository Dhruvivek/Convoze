import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import jwt from 'jsonwebtoken';
import request from 'supertest';

import { refresh } from './support/auth.js';
import {
  TEST_JWT_SECRET,
  TEST_OTP_CODE,
  buildTestApp,
  createTestPrisma,
  resetDatabase,
} from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const PHONE = '+14155550100';
const DEVICE_A = '0199a1b2-0000-4000-8000-00000000000a';
const DEVICE_B = '0199a1b2-0000-4000-8000-00000000000b';

// Every error response has exactly one shape: { error: { code, message } }.
function assertError(res, status, code) {
  assert.equal(res.status, status);
  assert.deepEqual(Object.keys(res.body), ['error']);
  assert.deepEqual(Object.keys(res.body.error).sort(), ['code', 'message']);
  assert.equal(res.body.error.code, code);
  assert.equal(typeof res.body.error.message, 'string');
}

function requestOtp(app, phoneNumber = PHONE) {
  return request(app).post('/auth/otp/request').send({ phoneNumber });
}

function failSends(verifyClient) {
  verifyClient.sendCode = async () => {
    throw new Error('Twilio is down');
  };
}

function verify(app, overrides = {}) {
  return request(app)
    .post('/auth/otp/verify')
    .send({
      phoneNumber: PHONE,
      code: TEST_OTP_CODE,
      deviceId: DEVICE_A,
      platform: 'android',
      ...overrides,
    });
}

describe('POST /auth/otp/request', () => {
  it('answers 202 with an empty body for an unknown number', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app).post('/auth/otp/request').send({ phoneNumber: PHONE });

    assert.equal(res.status, 202);
    assert.equal(res.text, '');
  });

  it('answers a known number exactly as it answers an unknown one', async () => {
    const { app } = buildTestApp({ prisma });
    const unknown = await request(app).post('/auth/otp/request').send({ phoneNumber: PHONE });
    await prisma.user.create({ data: { phoneNumber: PHONE, phoneVerifiedAt: new Date() } });

    const known = await request(app).post('/auth/otp/request').send({ phoneNumber: PHONE });

    assert.equal(known.status, 202);
    assert.equal(known.text, unknown.text);
    assert.deepEqual(Object.keys(known.headers).sort(), Object.keys(unknown.headers).sort());
  });

  it('records each accepted request against the normalised number', async () => {
    const { app, clock } = buildTestApp({ prisma });

    await request(app).post('/auth/otp/request').send({ phoneNumber: '+1 (415) 555-0100' });
    await request(app).post('/auth/otp/request').send({ phoneNumber: PHONE });

    const rows = await prisma.otpRequest.findMany();
    assert.equal(rows.length, 2);
    for (const row of rows) {
      assert.equal(row.phoneNumber, PHONE);
      assert.deepEqual(row.requestedAt, clock.now());
    }
  });

  it('rejects a phone number that is not valid, without recording it', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app).post('/auth/otp/request').send({ phoneNumber: '12345' });

    assertError(res, 400, 'invalid_phone_number');
    assert.equal(await prisma.otpRequest.count(), 0);
  });

  it('rejects a body without a phone number', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app).post('/auth/otp/request').send({});

    assertError(res, 400, 'invalid_request');
  });

  it('answers 502 when the SMS provider fails, without recording the request', async () => {
    const { app, verifyClient } = buildTestApp({ prisma });
    failSends(verifyClient);

    const res = await requestOtp(app);

    assertError(res, 502, 'otp_provider_unavailable');
    assert.equal(await prisma.otpRequest.count(), 0);
  });
});

describe('OTP request rate limit', () => {
  const MINUTE = 60 * 1000;

  it('accepts three requests for a number within 15 minutes and rejects the fourth', async () => {
    const { app, clock } = buildTestApp({ prisma });

    for (let i = 0; i < 3; i++) {
      assert.equal((await requestOtp(app)).status, 202);
      clock.advance(4 * MINUTE);
    }
    const fourth = await requestOtp(app);

    assertError(fourth, 429, 'otp_rate_limited');
  });

  it('does not record rejected requests', async () => {
    const { app } = buildTestApp({ prisma });
    for (let i = 0; i < 3; i++) await requestOtp(app);

    await requestOtp(app);
    await requestOtp(app);

    assert.equal(await prisma.otpRequest.count(), 3);
  });

  it('does not text a code for a rejected request', async () => {
    const { app, verifyClient } = buildTestApp({ prisma });
    for (let i = 0; i < 3; i++) await requestOtp(app);
    let sends = 0;
    verifyClient.sendCode = async () => {
      sends += 1;
    };

    await requestOtp(app);

    assert.equal(sends, 0);
  });

  it('accepts requests again once the oldest one is 15 minutes old', async () => {
    const { app, clock } = buildTestApp({ prisma });
    await requestOtp(app);
    clock.advance(1 * MINUTE);
    await requestOtp(app);
    await requestOtp(app);

    clock.advance(14 * MINUTE - 1);
    const justBefore = await requestOtp(app);
    clock.advance(1);
    const atWindowEnd = await requestOtp(app);
    const next = await requestOtp(app);

    assertError(justBefore, 429, 'otp_rate_limited');
    assert.equal(atWindowEnd.status, 202);
    // The window slides: the other two requests are still inside it.
    assertError(next, 429, 'otp_rate_limited');
  });

  it('counts every spelling of one number against the same limit', async () => {
    const { app } = buildTestApp({ prisma });

    await requestOtp(app, '+1 (415) 555-0100');
    await requestOtp(app, '+1 415-555-0100');
    await requestOtp(app, '+14155550100');
    const fourth = await requestOtp(app, '+1 415 555 0100');

    assertError(fourth, 429, 'otp_rate_limited');
  });

  it('never lets concurrent requests past the limit', async () => {
    const { app } = buildTestApp({ prisma });

    const responses = await Promise.all(Array.from({ length: 8 }, () => requestOtp(app)));

    const accepted = responses.filter((res) => res.status === 202).length;
    assert.ok(accepted <= 3, `accepted ${accepted} concurrent requests`);
    assert.equal(await prisma.otpRequest.count(), accepted);
    for (const res of responses.filter((r) => r.status !== 202)) {
      assertError(res, 429, 'otp_rate_limited');
    }
  });

  it('limits each number separately', async () => {
    const { app } = buildTestApp({ prisma });
    for (let i = 0; i < 3; i++) await requestOtp(app);

    const other = await requestOtp(app, '+14155550199');

    assert.equal(other.status, 202);
  });

  it('does not count requests the SMS provider failed to send', async () => {
    const { app, verifyClient } = buildTestApp({ prisma });
    const sendCode = verifyClient.sendCode;
    failSends(verifyClient);
    for (let i = 0; i < 3; i++) await requestOtp(app);
    verifyClient.sendCode = sendCode;

    const res = await requestOtp(app);

    assert.equal(res.status, 202);
  });
});

describe('POST /auth/otp/verify', () => {
  it('creates the User on their first verify and signs them in', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await verify(app);

    assert.equal(res.status, 200);
    assert.equal(typeof res.body.accessToken, 'string');
    assert.equal(typeof res.body.refreshToken, 'string');
    assert.equal(typeof res.body.user.id, 'string');
    assert.deepEqual(res.body.user, { id: res.body.user.id, phoneNumber: PHONE, displayName: null });
  });

  it('reuses the existing User on a later verify', async () => {
    const { app } = buildTestApp({ prisma });

    const first = await verify(app);
    const second = await verify(app, { phoneNumber: '+1 415-555-0100' });

    assert.equal(second.status, 200);
    assert.equal(second.body.user.id, first.body.user.id);
    assert.equal(second.body.user.phoneNumber, PHONE);
    assert.equal(await prisma.user.count(), 1);
  });

  it('settles two first-time verifies for one number on a single User', async () => {
    const { app } = buildTestApp({ prisma });

    const [a, b] = await Promise.all([verify(app), verify(app, { deviceId: DEVICE_B })]);

    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    assert.equal(a.body.user.id, b.body.user.id);
  });

  it('leaves the Session on the first Device in place when a second Device signs in', async () => {
    const { app } = buildTestApp({ prisma });

    const onA = await verify(app, { deviceId: DEVICE_A, platform: 'android' });
    const onB = await verify(app, { deviceId: DEVICE_B, platform: 'ios' });

    const sessionA = jwt.decode(onA.body.accessToken).sessionId;
    const sessionB = jwt.decode(onB.body.accessToken).sessionId;
    assert.notEqual(sessionA, sessionB);
    const sessions = await prisma.session.findMany({ orderBy: { issuedAt: 'asc' } });
    assert.deepEqual(
      sessions.map((s) => [s.id, s.deviceId, s.platform, s.revokedAt]),
      [
        [sessionA, DEVICE_A, 'android', null],
        [sessionB, DEVICE_B, 'ios', null],
      ],
    );
  });

  it("replaces the Device's old Session when it signs in again", async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const first = await verify(app);
    const revoked = [];
    sessionRevoked.subscribe((event) => revoked.push(event));

    const second = await verify(app);

    assert.equal(second.status, 200);
    assertError(await refresh(app, first.body.refreshToken), 401, 'invalid_refresh_token');
    assert.equal((await refresh(app, second.body.refreshToken)).status, 200);
    assert.deepEqual(revoked, [
      { sessionId: jwt.decode(first.body.accessToken).sessionId, userId: first.body.user.id },
    ]);
  });

  it("leaves another User's Session on the same Device alone", async () => {
    const { app, sessionRevoked } = buildTestApp({ prisma });
    const someoneElse = await verify(app, { phoneNumber: '+14155550199' });
    const revoked = [];
    sessionRevoked.subscribe((event) => revoked.push(event));

    await verify(app);

    assert.equal((await refresh(app, someoneElse.body.refreshToken)).status, 200);
    assert.deepEqual(revoked, []);
  });

  it('issues a 15-minute access token naming the User and the Session', async () => {
    const { app, clock } = buildTestApp({ prisma });

    const res = await verify(app);

    const claims = jwt.verify(res.body.accessToken, TEST_JWT_SECRET, {
      clockTimestamp: clock.now().getTime() / 1000,
    });
    assert.equal(claims.sub, res.body.user.id);
    const session = await prisma.session.findUniqueOrThrow({ where: { id: claims.sessionId } });
    assert.equal(session.userId, res.body.user.id);
    assert.equal(claims.exp - claims.iat, 15 * 60);
    assert.equal(claims.iat, Date.parse('2026-01-01T00:00:00Z') / 1000);
  });

  it('issues a refresh token of the form <sessionId>.<secret>, storing only the secret\'s hash', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await verify(app);

    const [sessionId, secret, ...rest] = res.body.refreshToken.split('.');
    assert.equal(rest.length, 0);
    assert.equal(sessionId, jwt.decode(res.body.accessToken).sessionId);
    assert.ok(Buffer.from(secret, 'base64url').length >= 32, 'secret carries at least 256 bits');
    const session = await prisma.session.findUniqueOrThrow({ where: { id: sessionId } });
    assert.equal(session.refreshTokenHash, createHash('sha256').update(secret).digest('hex'));
    assert.ok(!session.refreshTokenHash.includes(secret));
  });

  it('opens a Session that expires 30 days after it is issued', async () => {
    const { app, clock } = buildTestApp({ prisma });

    const res = await verify(app);

    const session = await prisma.session.findUniqueOrThrow({
      where: { id: jwt.decode(res.body.accessToken).sessionId },
    });
    assert.deepEqual(session.issuedAt, clock.now());
    assert.deepEqual(session.expiresAt, new Date('2026-01-31T00:00:00.000Z'));
  });

  it('rejects a wrong code without creating a User or Session', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await verify(app, { code: '999999' });

    assertError(res, 401, 'invalid_otp');
    assert.equal(await prisma.user.count(), 0);
    assert.equal(await prisma.session.count(), 0);
  });

  it('rejects a request without a Device or with an unknown platform', async () => {
    const { app } = buildTestApp({ prisma });

    const noDevice = await verify(app, { deviceId: undefined });
    const badPlatform = await verify(app, { platform: 'windows' });

    assertError(noDevice, 400, 'invalid_request');
    assertError(badPlatform, 400, 'invalid_request');
  });

  it('rejects a request without a code or phone number', async () => {
    const { app } = buildTestApp({ prisma });

    const noCode = await verify(app, { code: undefined });
    const noPhone = await verify(app, { phoneNumber: undefined });
    const numericCode = await verify(app, { code: 123456 });

    assertError(noCode, 400, 'invalid_request');
    assertError(noPhone, 400, 'invalid_request');
    assertError(numericCode, 400, 'invalid_request');
  });

  it('rejects malformed JSON', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await request(app)
      .post('/auth/otp/verify')
      .set('Content-Type', 'application/json')
      .send('{"phoneNumber":');

    assertError(res, 400, 'invalid_request');
  });

  it('rejects a phone number that is not valid', async () => {
    const { app } = buildTestApp({ prisma });

    const res = await verify(app, { phoneNumber: '12345' });

    assertError(res, 400, 'invalid_phone_number');
  });

  it('answers 502 when the SMS provider cannot check the code', async () => {
    const { app, verifyClient } = buildTestApp({ prisma });
    verifyClient.checkCode = async () => {
      throw new Error('Twilio is down');
    };

    const res = await verify(app);

    assertError(res, 502, 'otp_provider_unavailable');
    assert.equal(await prisma.session.count(), 0);
  });
});
