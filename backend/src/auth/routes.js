import { Router } from 'express';

import { sendError } from '../http/errors.js';
import { normalisePhoneNumber } from './phoneNumber.js';
import { signIn } from './sessions.js';

const PLATFORMS = new Set(['android', 'ios']);

export function createAuthRouter({ prisma, verifyClient, clock, jwtSecret }) {
  const router = Router();

  // Answers the same way whether or not the number belongs to a User, so it
  // can't be used to find out who is registered.
  router.post('/otp/request', async (req, res) => {
    const phoneNumber = normalisePhoneNumber(req.body?.phoneNumber);
    if (!phoneNumber) {
      sendError(res, 400, 'invalid_request', 'Expected { phoneNumber } in international format');
      return;
    }

    await verifyClient.sendCode(phoneNumber);
    // Recorded only once the send is accepted, so the rate limit counts
    // codes actually sent.
    await prisma.otpRequest.create({ data: { phoneNumber, requestedAt: clock.now() } });
    res.status(202).end();
  });

  // There is no separate sign-up: a number's first successful verify creates
  // its User.
  router.post('/otp/verify', async (req, res) => {
    const { code, deviceId, platform } = req.body ?? {};
    const phoneNumber = normalisePhoneNumber(req.body?.phoneNumber);
    const valid =
      phoneNumber &&
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

    if (!(await verifyClient.checkCode(phoneNumber, code))) {
      sendError(res, 401, 'invalid_code', 'The code is wrong or has expired');
      return;
    }

    const result = await signIn(prisma, { phoneNumber, deviceId, platform }, { clock, jwtSecret });
    res.json(result);
  });

  return router;
}
