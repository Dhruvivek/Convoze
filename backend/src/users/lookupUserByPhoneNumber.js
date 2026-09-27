import { normalisePhoneNumber } from '../auth/phoneNumber.js';
import { USER_SELECT } from '../messaging/hydrator.js';

// The "find by phone number" half of Contacts (#101, Telegram-style): start a
// conversation with someone by their exact number even when they aren't in
// the Device's address book. Requires a full, unambiguous match — there's no
// partial/prefix search — so this can't be used to browse the User table.
export async function lookupUserByPhoneNumber(prisma, userId, rawPhoneNumber, defaultCountry) {
  const number = normalisePhoneNumber(rawPhoneNumber, defaultCountry);
  if (!number) return null;

  const user = await prisma.user.findUnique({ where: { phoneNumber: number }, select: USER_SELECT });
  return user && user.id !== userId ? user : null;
}
