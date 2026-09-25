import { UPDATE_KINDS } from './kinds.js';

const USER_SELECT = { id: true, displayName: true, avatarUrl: true, phoneNumber: true };

// A deleted Message never carries its content past this boundary, even if
// the caller reused a stale row: a tombstone is always built from scratch.
function tombstone(message) {
  return { id: message.id, conversationId: message.conversationId, isDeleted: true };
}

function messagePayload(message) {
  if (message.isDeleted) return tombstone(message);
  return {
    id: message.id,
    conversationId: message.conversationId,
    senderId: message.senderId,
    clientMsgId: message.clientMsgId,
    replyToMessageId: message.replyToMessageId,
    linkPreview: message.linkPreview,
    type: message.type,
    content: message.content,
    createdAt: message.createdAt,
    editedAt: message.editedAt,
    isDeleted: message.isDeleted,
  };
}

function groupBy(items, keyFn) {
  const map = new Map();
  for (const item of items) {
    const key = keyFn(item);
    const list = map.get(key);
    if (list) list.push(item);
    else map.set(key, [item]);
  }
  return map;
}

// Distinct values of `field` across `rows`, optionally narrowed to one
// `kind` first; always present since a kind's own ref field is never null.
function idsOf(rows, field, kind) {
  const matching = kind ? rows.filter((r) => r.kind === kind) : rows.filter((r) => r[field]);
  return [...new Set(matching.map((r) => r[field]))];
}

// A Participant's unread count for `conversationId`: non-deleted Messages
// from other Users, at or after their read watermark's Message (ADR 0004's
// "seen by" comparison — UUIDv7 ids sort like their createdAt). None read
// yet counts every such Message (ADR 0009).
function unreadCount(prisma, conversationId, participant) {
  return prisma.message.count({
    where: {
      conversationId,
      isDeleted: false,
      senderId: { not: participant.userId },
      ...(participant.lastReadMessageId ? { id: { gt: participant.lastReadMessageId } } : {}),
    },
  });
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
          unreadCount: caller ? await unreadCount(prisma, row.conversationId, caller) : 0,
        };
        for (const p of list) referencedUserIds.add(p.userId);
        break;
      }
      case UPDATE_KINDS.CONVERSATION_JOINED: {
        payload = { ...conversationById.get(row.conversationId) };
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

  const users =
    referencedUserIds.size > 0
      ? await prisma.user.findMany({
          where: { id: { in: [...referencedUserIds] } },
          select: USER_SELECT,
        })
      : [];

  return { updates, users };
}
