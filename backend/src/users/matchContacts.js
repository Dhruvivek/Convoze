import { normalisePhoneNumber } from '../auth/phoneNumber.js';
import { USER_SELECT } from '../messaging/hydrator.js';

// A device's address book can run into the thousands; this caps how many
// numbers one request will normalise/query so a single sync can't turn into
// an unbounded lookup.
export const MAX_CONTACT_NUMBERS = 3000;

// The phone-contact matching behind "Contacts" (#101, Telegram/WhatsApp-
// style): given the raw phone numbers pulled from a Device's address book,
// normalise them the same way sign-in does and return whichever ones belong
// to a registered User other than the caller. Numbers with no leading `+`
// (a contact saved in national format) fall back to `defaultCountry` — the
// caller's own region, so "unknown number" contacts don't just vanish.
export async function matchContacts(prisma, userId, phoneNumbers, defaultCountry) {
  const candidates = phoneNumbers.slice(0, MAX_CONTACT_NUMBERS);
  const normalised = new Set();
  for (const raw of candidates) {
    const number = normalisePhoneNumber(raw, defaultCountry);
    if (number) normalised.add(number);
  }
  if (normalised.size === 0) return [];

  return prisma.user.findMany({
    where: { phoneNumber: { in: [...normalised] }, id: { not: userId } },
    select: USER_SELECT,
  });
}
