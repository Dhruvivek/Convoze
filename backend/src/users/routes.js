import { Router } from 'express';
import { parsePhoneNumberFromString } from 'libphonenumber-js';

import { sendError } from '../http/errors.js';
import { createSendRateLimit } from '../messaging/rateLimiter.js';
import { MAX_CONTACT_NUMBERS, matchContacts } from './matchContacts.js';
import { lookupUserByPhoneNumber } from './lookupUserByPhoneNumber.js';

// Both routes below turn a phone number into a User, which is the one thing
// `GET /users/:id` deliberately won't do (#43's enumeration guard) — so both
// sit behind their own rate limit rather than relying on that guard.
const CONTACTS_RATE_LIMIT = { limit: 30, windowMs: 10 * 60 * 1000 };

// Contacts (#101): matching a Device's address book, and finding one User by
// exact phone number, against the registered User table.
export function createUsersRouter({ prisma, authenticated, clock }) {
  const router = Router();
  const rateLimit = createSendRateLimit({ clock, ...CONTACTS_RATE_LIMIT });

  async function callerDefaultCountry(userId) {
    const caller = await prisma.user.findUnique({ where: { id: userId }, select: { phoneNumber: true } });
    return parsePhoneNumberFromString(caller?.phoneNumber ?? '')?.country;
  }

  router.post('/match', authenticated, async (req, res) => {
    if (!rateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many contact syncs');
      return;
    }
    const { phoneNumbers } = req.body ?? {};
    if (!Array.isArray(phoneNumbers) || !phoneNumbers.every((n) => typeof n === 'string')) {
      sendError(res, 400, 'invalid_request', 'phoneNumbers must be an array of strings');
      return;
    }
    if (phoneNumbers.length > MAX_CONTACT_NUMBERS) {
      sendError(res, 400, 'invalid_request', `phoneNumbers must have at most ${MAX_CONTACT_NUMBERS} entries`);
      return;
    }

    const defaultCountry = await callerDefaultCountry(req.auth.userId);
    const users = await matchContacts(prisma, req.auth.userId, phoneNumbers, defaultCountry);
    res.json({ users });
  });

  router.get('/lookup', authenticated, async (req, res) => {
    if (!rateLimit.consume(req.auth.userId)) {
      sendError(res, 429, 'rate_limited', 'Too many contact syncs');
      return;
    }
    const { phoneNumber } = req.query ?? {};
    if (typeof phoneNumber !== 'string' || phoneNumber.trim().length === 0) {
      sendError(res, 400, 'invalid_request', 'phoneNumber is required');
      return;
    }

    const defaultCountry = await callerDefaultCountry(req.auth.userId);
    const user = await lookupUserByPhoneNumber(prisma, req.auth.userId, phoneNumber, defaultCountry);
    res.json({ user });
  });

  return router;
}
