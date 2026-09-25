import { groupBy } from './groupBy.js';
import { UPDATE_KINDS } from './kinds.js';
import { messagePayload, tombstone } from './messagePayload.js';
import { unreadCountFor } from './unreadCount.js';

export const USER_SELECT = { id: true, displayName: true, avatarUrl: true, phoneNumber: true };

// Distinct values of `field` across `rows`, optionally narrowed to one
// `kind` first; always present since a kind's own ref field is never null.
function idsOf(rows, field, kind) {
  const matching = kind ? rows.filter((r) => r.kind === kind) : rows.filter((r) => r[field]);
  return [...new Set(matching.map((r) => r[field]))];
}

// The `users` side-list (ADR 0009) for a set of referenced user ids, shared
// by the Update batches this file hydrates and the REST pages of #50.
export async function hydrateUsers(prisma, userIds) {
  if (userIds.length === 0) return [];
  return prisma.user.findMany({ where: { id: { in: userIds } }, select: USER_SELECT });
}

// A single Conversation row, hydrated exactly as `listConversations.js`
// hydrates one of its rows, plus the caller's Conversation preferences (#45)
// — the one hydrator both a `conversation.prefs` Update and the three
// preference-writing endpoints (`conversationPrefs.js`) read from, so the
// history-cleared filter only has to be applied in one place (inside
// `unreadCountFor` and here). Returns `null` when `userId` isn't a current
// or former Participant of `conversationId`.
export async function hydrateConversationForUser(prisma, conversationId, userId) {
  const participant = await prisma.participant.findUnique({
    where: { conversationId_userId: { conversationId, userId } },
  });
  if (!participant) return null;

  const [conversation, members, rawLastMessage] = await Promise.all([
    prisma.conversation.findUnique({ where: { id: conversationId } }),
    prisma.participant.findMany({ where: { conversationId } }),
    prisma.message.findFirst({ where: { conversationId }, orderBy: { id: 'desc' } }),
  ]);

  const clearedId = participant.historyClearedMessageId;
  const lastMessage = rawLastMessage && (!clearedId || rawLastMessage.id > clearedId) ? rawLastMessage : null;

  const referencedUserIds = new Set(members.map((m) => m.userId));
  if (lastMessage && !lastMessage.isDeleted) referencedUserIds.add(lastMessage.senderId);

  const [unreadCount, users] = await Promise.all([
    unreadCountFor(prisma, conversationId, participant),
    hydrateUsers(prisma, [...referencedUserIds]),
  ]);

  return {
    conversationRow: {
      id: conversation.id,
      type: conversation.type,
      name: conversation.name,
      participants: members.map((m) => ({ userId: m.userId, role: m.role })),
      lastMessage: lastMessage ? messagePayload(lastMessage) : null,
      unreadCount,
      readWatermarks: members.map((m) => ({ userId: m.userId, messageId: m.lastReadMessageId })),
      deliveryWatermarks: members.map((m) => ({
        userId: m.userId,
        messageId: m.lastDeliveredMessageId,
      })),
      left: participant.leftAt !== null,
      pinnedAt: participant.pinnedAt,
      archivedAt: participant.archivedAt,
      mutedUntil: participant.mutedUntil,
      hiddenAt: participant.hiddenAt,
      historyClearedMessageId: participant.historyClearedMessageId,
    },
    users,
  };
}

// Turns a batch of UserUpdate rows into their payloads as of now (ADR
// 0008's Hydrator table) plus the `users` side-list every payload refers to
// (ADR 0009). References, not copies: an edit or delete committed after the
// Update was written still hydrates to the latest state.
export async function hydrateUpdates(prisma, rows) {
  const messageIds = idsOf(rows, 'messageId');
  const conversationIds = idsOf(rows, 'conversationId');

  const [messages, conversations] = await Promise.all([
    messageIds.length > 0
      ? prisma.message.findMany({ where: { id: { in: messageIds } } })
      : Promise.resolve([]),
    conversationIds.length > 0
      ? prisma.conversation.findMany({ where: { id: { in: conversationIds } } })
      : Promise.resolve([]),
  ]);
  const messageById = new Map(messages.map((m) => [m.id, m]));
  const conversationById = new Map(conversations.map((c) => [c.id, c]));

  const reactionMessageIds = idsOf(rows, 'messageId', UPDATE_KINDS.REACTION_CHANGED);
  const reactions =
    reactionMessageIds.length > 0
      ? await prisma.reaction.findMany({ where: { messageId: { in: reactionMessageIds } } })
      : [];
  const reactionsByMessage = groupBy(reactions, (r) => r.messageId);

  const receiptsConversationIds = idsOf(rows, 'conversationId', UPDATE_KINDS.CONVERSATION_RECEIPTS);
  const participants =
    receiptsConversationIds.length > 0
      ? await prisma.participant.findMany({
          where: { conversationId: { in: receiptsConversationIds } },
        })
      : [];
  const participantsByConversation = groupBy(participants, (p) => p.conversationId);

  const referencedUserIds = new Set();
  const updates = [];
  for (const row of rows) {
    let payload;
    switch (row.kind) {
      case UPDATE_KINDS.MESSAGE_NEW:
      case UPDATE_KINDS.MESSAGE_EDITED: {
        const message = messageById.get(row.messageId);
        payload = messagePayload(message);
        if (!message.isDeleted) referencedUserIds.add(message.senderId);
        break;
      }
      case UPDATE_KINDS.MESSAGE_DELETED: {
        payload = tombstone(messageById.get(row.messageId));
        break;
      }
      case UPDATE_KINDS.REACTION_CHANGED: {
        const message = messageById.get(row.messageId);
        const list = reactionsByMessage.get(row.messageId) ?? [];
        payload = {
          messageId: row.messageId,
          conversationId: message.conversationId,
          reactions: list.map((r) => ({ userId: r.userId, emoji: r.emoji })),
        };
        for (const r of list) referencedUserIds.add(r.userId);
        break;
      }
      case UPDATE_KINDS.CONVERSATION_RECEIPTS: {
        const list = participantsByConversation.get(row.conversationId) ?? [];
        const caller = list.find((p) => p.userId === row.userId);
        payload = {
          conversationId: row.conversationId,
          participants: list.map((p) => ({
            userId: p.userId,
            lastReadMessageId: p.lastReadMessageId,
            lastDeliveredMessageId: p.lastDeliveredMessageId,
          })),
          unreadCount: caller ? await unreadCountFor(prisma, row.conversationId, caller) : 0,
        };
        for (const p of list) referencedUserIds.add(p.userId);
        break;
      }
      case UPDATE_KINDS.CONVERSATION_JOINED: {
        payload = { ...conversationById.get(row.conversationId) };
        break;
      }
      case UPDATE_KINDS.CONVERSATION_PREFS: {
        const hydrated = await hydrateConversationForUser(prisma, row.conversationId, row.userId);
        payload = hydrated ? hydrated.conversationRow : null;
        if (payload) {
          for (const member of payload.participants) referencedUserIds.add(member.userId);
        }
        break;
      }
      default:
        throw new Error(`hydrateUpdates: unknown kind ${row.kind}`);
    }
    updates.push({
      id: row.id,
      userId: row.userId,
      seq: typeof row.seq === 'bigint' ? Number(row.seq) : row.seq,
      kind: row.kind,
      createdAt: row.createdAt,
      payload,
    });
  }

  const users = await hydrateUsers(prisma, [...referencedUserIds]);

  return { updates, users };
}
