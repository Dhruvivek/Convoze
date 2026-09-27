import { parsePhoneNumberFromString } from 'libphonenumber-js';

// Normalises user input (with its +country code) to E.164, or returns null
// when it isn't a valid phone number. Every phone number is normalised
// before any other use, so one number always has one spelling.
//
// `defaultCountry` (an ISO 3166-1 alpha-2 code) is only consulted for input
// that has no leading `+` — a device contact saved in national format, say.
// A number that already carries its own country code ignores it.
export function normalisePhoneNumber(input, defaultCountry) {
  if (typeof input !== 'string') return null;
  const parsed = parsePhoneNumberFromString(input, defaultCountry);
  return parsed?.isValid() ? parsed.number : null;
}
