import { parsePhoneNumberFromString } from 'libphonenumber-js';

// Normalises user input (with its +country code) to E.164, or returns null
// when it isn't a valid phone number. Every phone number is normalised
// before any other use, so one number always has one spelling.
export function normalisePhoneNumber(input) {
  if (typeof input !== 'string') return null;
  const parsed = parsePhoneNumberFromString(input);
  return parsed?.isValid() ? parsed.number : null;
}
