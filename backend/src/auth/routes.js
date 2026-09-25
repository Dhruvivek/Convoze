import { Router } from 'express';

import { sendError } from '../http/errors.js';
import { releaseOtpRequest, reserveOtpRequest } from './otpRateLimit.js';
import { normalisePhoneNumber } from './phoneNumber.js';
import { signIn } from './sessions.js';

const PLATFORMS = new Set(['android', 'ios']);

// The Verify client failing is the provider's outage, not ours: 502, not 500.
function sendProviderUnavailable(res, err) {
  console.error(err);
  sendError(res, 502, 'otp_provider_unavailable', "Couldn't reach the SMS provider");
}

function sendInvalidPhoneNumber(res) {
  sendError(res, 400, 'invalid_phone_number', 'Not a valid phone number in international format');
}

export function createAuthRouter({ prisma, verifyClient, clock, jwtSecret }) {
  const router = Router();

  // Answers the same way whether or not the number belongs to a User, so it
  // can't be used to find out who is registered.
  router.post('/otp/request', async (req, res) => {
    const rawPhoneNumber = req.body?.phoneNumber;
    if (typeof rawPhoneNumber !== 'string') {
      sendError(res, 400, 'invalid_request', 'Expected { phoneNumber } in international format');
      return;
    }
    const phoneNumber = normalisePhoneNumber(rawPhoneNumber);
    if (!phoneNumber) {
      sendInvalidPhoneNumber(res);
      return;
    }

    const reservation = await reserveOtpRequest(prisma, phoneNumber, clock.now());
    if (!reservation) {
      sendError(res, 429, 'otp_rate_limited', 'Too many codes requested. Try again later.');
      return;
    }

    try {
      await verifyClient.sendCode(phoneNumber);
    } catch (err) {
      // Only codes actually sent count towards the limit.
      await releaseOtpRequest(prisma, reservation);
      sendProviderUnavailable(res, err);
      return;
    }
    res.status(202).end();
  });

  // There is no separate sign-up: a number's first successful verify creates
  // its User.
  router.post('/otp/verify', async (req, res) => {
    const { phoneNumber: rawPhoneNumber, code, deviceId, platform } = req.body ?? {};
    const valid =
      typeof rawPhoneNumber === 'string' &&
      typeof code === 'string' &&
      code.length > 0 &&
      typeof deviceId === 'string' &&
      deviceId.length > 0 &&
      deviceId.length <= 128 &&
      PLATFORMS.has(platform);
    if (!valid) {
      sendError(
        res,
        400,
        'invalid_request',
        'Expected { phoneNumber, code, deviceId, platform: "android" | "ios" }',
      );
      return;
    }
    const phoneNumber = normalisePhoneNumber(rawPhoneNumber);
    if (!phoneNumber) {
      sendInvalidPhoneNumber(res);
      return;
    }

    let approved;
    try {
      approved = await verifyClient.checkCode(phoneNumber, code);
    } catch (err) {
      sendProviderUnavailable(res, err);
      return;
    }
    if (!approved) {
      sendError(res, 401, 'invalid_otp', 'The code is wrong or has expired');
      return;
    }

    const result = await signIn(prisma, { phoneNumber, deviceId, platform }, { clock, jwtSecret });
    res.json(result);
  });

  return router;
}
