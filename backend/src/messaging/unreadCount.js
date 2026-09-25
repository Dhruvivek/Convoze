// A Participant's unread count for `conversationId`: non-deleted Messages
// from other Users, at or after their read watermark's Message (ADR 0004's
// "seen by" comparison — UUIDv7 ids sort like their createdAt). None read
// yet counts every such Message (ADR 0009). Shared by the Hydrator (#47) and
// the REST conversation list (#50).
export function unreadCountFor(prisma, conversationId, participant) {
  return prisma.message.count({
    where: {
      conversationId,
      isDeleted: false,
      senderId: { not: participant.userId },
      ...(participant.lastReadMessageId ? { id: { gt: participant.lastReadMessageId } } : {}),
    },
  });
}
