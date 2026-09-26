// The later (chronologically greater) of two nullable UUIDv7 message ids —
// both sort like their `createdAt` as plain strings, the same assumption the
// rest of this backend already relies on (`listConversations.js`,
// `deliveryWatermark.js`).
function laterId(a, b) {
  if (!a) return b ?? null;
  if (!b) return a;
  return a > b ? a : b;
}

// A Participant's unread count for `conversationId`: non-deleted Messages
// from other Users, after the later of their read watermark and their own
// history-cleared watermark (#45 — a Message they cleared for themselves
// never counts as unread again). None read/cleared yet counts every such
// Message (ADR 0009). Shared by the Hydrator (#47) and the REST conversation
// list (#50).
export function unreadCountFor(prisma, conversationId, participant) {
  const cutoff = laterId(participant.lastReadMessageId, participant.historyClearedMessageId);
  return prisma.message.count({
    where: {
      conversationId,
      isDeleted: false,
      senderId: { not: participant.userId },
      ...(cutoff ? { id: { gt: cutoff } } : {}),
    },
  });
}
