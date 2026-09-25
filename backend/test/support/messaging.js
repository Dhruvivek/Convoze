import { randomUUID } from 'node:crypto';

let userCounter = 0;

// A User fixture with no Session, for tests exercising messaging primitives
// directly rather than through the API.
export function createUser(prisma, overrides = {}) {
  userCounter += 1;
  return prisma.user.create({
    data: {
      phoneNumber: `+14155551${String(userCounter).padStart(3, '0')}`,
      phoneVerifiedAt: new Date(),
      displayName: `User ${userCounter}`,
      ...overrides,
    },
  });
}

export function createConversation(prisma, { type = 'group', participantIds, name, createdById } = {}) {
  return prisma.conversation.create({
    data: {
      type,
      name,
      directKey: type === 'direct' ? [...participantIds].sort().join(':') : null,
      createdById,
      participants: { create: participantIds.map((userId) => ({ userId })) },
    },
  });
}

export function createMessage(prisma, { conversationId, senderId, content = 'hi', ...overrides }) {
  return prisma.message.create({
    data: {
      conversationId,
      senderId,
      content,
      clientMsgId: randomUUID(),
      ...overrides,
    },
  });
}
