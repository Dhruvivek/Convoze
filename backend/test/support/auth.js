import assert from 'node:assert/strict';
import request from 'supertest';

import { TEST_OTP_CODE } from './testApp.js';

// Signs one Device in through the real API and returns the verify response.
export async function signIn(
  app,
  { phoneNumber = '+14155550100', deviceId = '0199a1b2-0000-4000-8000-00000000000a' } = {},
) {
  const res = await request(app).post('/auth/otp/verify').send({
    phoneNumber,
    code: TEST_OTP_CODE,
    deviceId,
    platform: 'android',
  });
  assert.equal(res.status, 200);
  return res.body;
}

export function refresh(app, refreshToken) {
  return request(app).post('/auth/refresh').send({ refreshToken });
}

export function logout(app, authorization) {
  const req = request(app).post('/auth/logout');
  return authorization === undefined ? req : req.set('Authorization', authorization);
}

// The e2e echo endpoint sits behind the real auth middleware, so it stands in
// for every protected route. Needs an app built with e2eMode.
export function echo(app, authorization) {
  const req = request(app).get('/__e2e__/echo');
  return authorization === undefined ? req : req.set('Authorization', authorization);
}

export function logoutOthers(app, authorization) {
  const req = request(app).post('/auth/sessions/logout-others');
  return authorization === undefined ? req : req.set('Authorization', authorization);
}
