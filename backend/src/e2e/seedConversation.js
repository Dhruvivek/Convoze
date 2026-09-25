import { normalisePhoneNumber } from '../auth/phoneNumber.js';

const TYPES = new Set(['direct', 'group']);

// Creates a Conversation between the Users with these phone numbers, creating
// any that don't exist yet as a first sign-in would. Null when the request
// doesn't describe a valid Conversation.
export async function seedConversation(prisma, { type, name, participantPhoneNumbers }, now) {
  if (!TYPES.has(type) || !Array.isArray(participantPhoneNumbers)) return null;
  const phoneNumbers = [...new Set(participantPhoneNumbers.map(normalisePhoneNumber))];
  const valid =
    phoneNumbers.length > 0 &&
    phoneNumbers.every(Boolean) &&
    (type === 'group' || phoneNumbers.length === 2) &&
    (name === undefined || (type === 'group' && typeof name === 'string'));
  if (!valid) return null;

  return prisma.$transaction(async (tx) => {
    const users = [];
    for (const phoneNumber of phoneNumbers) {
      users.push(
        await tx.user.upsert({
          where: { phoneNumber },
          create: { phoneNumber, phoneVerifiedAt: now },
          update: {},
        }),
      );
    }
    const directKey =
      type === 'direct'
        ? users
            .map((u) => u.id)
            .sort()
            .join(':')
        : null;
    const conversation = await tx.conversation.create({
      data: {
        type,
        name,
        directKey,
        participants: { create: users.map((u) => ({ userId: u.id })) },
      },
    });
    return {
      id: conversation.id,
      type,
      participants: users.map((u) => ({ userId: u.id, phoneNumber: u.phoneNumber })),
    };
  });
}
