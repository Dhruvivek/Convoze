import { USER_SELECT } from '../messaging/hydrator.js';

// Every other registered User (#71): the Contacts tab's source of who's on
// Convoze, until real phone-contact matching replaces it. Ordered by
// `createdAt` so the list is stable across calls rather than reshuffling.
export async function listUsers(prisma, userId) {
  return prisma.user.findMany({
    where: { id: { not: userId } },
    select: USER_SELECT,
    orderBy: { createdAt: 'asc' },
  });
}
