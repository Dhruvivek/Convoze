import { groupBy } from './groupBy.js';
import { hydrateUsers } from './hydrator.js';
import { messagePayload } from './messagePayload.js';
import { unreadCountFor } from './unreadCount.js';

export const DEFAULT_LIST_LIMIT = 50;
export const MAX_LIST_LIMIT = 100;

// `GET /conversations?cursor=&limit=` (#50): newest activity first, where
// "activity" is a Conversation's latest Message id, or its own id when it
// has none yet — both UUIDv7, so they sort chronologically as strings the
// same way the rest of this backend already compares message ids (see
// `deliveryWatermark.js`). No denormalized "last activity" column exists, so
// this loads the caller's Participant rows in full and paginates in memory;
// fine at this project's scale (a User's own Conversation count), matching
// the single-instance, no-separate-index-shape approach used elsewhere.
export async function listConversations(prisma, userId, { cursor, limit = DEFAULT_LIST_LIMIT } = {}) {
  const take = Math.min(Math.max(1, limit), MAX_LIST_LIMIT);

  const participants = await prisma.participant.findMany({
    where: { userId },
    include: { conversation: true },
  });
  if (participants.length === 0) {
    return { conversations: [], nextCursor: null, users: [], ...(cursor ? {} : { currentSeq: 0 }) };
  }

  const conversationIds = participants.map((p) => p.conversationId);
  const [latestMessages, allParticipants] = await Promise.all([
    prisma.message.findMany({
      where: { conversationId: { in: conversationIds } },
      orderBy: { id: 'desc' },
      distinct: ['conversationId'],
    }),
    prisma.participant.findMany({ where: { conversationId: { in: conversationIds } } }),
  ]);
  const latestByConversation = new Map(latestMessages.map((m) => [m.conversationId, m]));
  const membersByConversation = groupBy(allParticipants, (p) => p.conversationId);

  const rows = [];
  for (const participant of participants) {
    const { conversation } = participant;
    const lastMessage = latestByConversation.get(conversation.id) ?? null;
    // A direct Conversation nobody has said anything in yet is noise for
    // everyone except whoever started it.
    if (
      conversation.type === 'direct' &&
      !lastMessage &&
      conversation.createdById &&
      conversation.createdById !== userId
    ) {
      continue;
    }
    rows.push({
      activityKey: lastMessage ? lastMessage.id : conversation.id,
      conversation,
      participant,
      lastMessage,
      members: membersByConversation.get(conversation.id) ?? [],
    });
  }
  rows.sort((a, b) => (a.activityKey < b.activityKey ? 1 : a.activityKey > b.activityKey ? -1 : 0));

  const startIndex = cursor ? rows.findIndex((r) => r.activityKey < cursor) : 0;
  const remaining = startIndex === -1 ? [] : rows.slice(startIndex);
  const page = remaining.slice(0, take);
  const nextCursor = remaining.length > take ? page[page.length - 1].activityKey : null;

  const referencedUserIds = new Set();
  const unreadCounts = await Promise.all(
    page.map(({ conversation, participant }) => unreadCountFor(prisma, conversation.id, participant)),
  );
  const conversations = page.map(({ conversation, participant, lastMessage, members }, index) => {
    for (const member of members) referencedUserIds.add(member.userId);
    if (lastMessage && !lastMessage.isDeleted) referencedUserIds.add(lastMessage.senderId);
    return {
      id: conversation.id,
      type: conversation.type,
      name: conversation.name,
      participants: members.map((m) => ({ userId: m.userId, role: m.role })),
      lastMessage: lastMessage ? messagePayload(lastMessage) : null,
      unreadCount: unreadCounts[index],
      readWatermarks: members.map((m) => ({ userId: m.userId, messageId: m.lastReadMessageId })),
      deliveryWatermarks: members.map((m) => ({
        userId: m.userId,
        messageId: m.lastDeliveredMessageId,
      })),
      left: participant.leftAt !== null,
    };
  });

  const users = await hydrateUsers(prisma, [...referencedUserIds]);
  const result = { conversations, nextCursor, users };
  if (!cursor) {
    const seqRow = await prisma.userSeq.findUnique({ where: { userId } });
    result.currentSeq = seqRow ? Number(seqRow.lastSeq) : 0;
  }
  return result;
}
