import { isUuid } from '../auth/tokens.js';
import { hydrateUsers } from './hydrator.js';
import { messagePayload, tombstone } from './messagePayload.js';

export const DEFAULT_HISTORY_LIMIT = 30;
export const MAX_HISTORY_LIMIT = 100;

function fail(code) {
  return { ok: false, code };
}

// `GET /conversations/:id/messages?before=&limit=` (#50): messages strictly
// older than `before`, newest first, each carrying its reactions and a
// live-hydrated Reply preview (`CONTEXT.md`'s Reply — the target as it is
// now, never a copy taken at reply time). Participants can page the whole
// history; someone who has left only sees up to when they did (`leftAt`),
// since nothing durable happens to their view of it after that.
export async function listMessages(prisma, userId, conversationId, { before, limit } = {}) {
  if (!isUuid(conversationId) || (before !== undefined && !isUuid(before))) return fail('INVALID');

  const participant = await prisma.participant.findUnique({
    where: { conversationId_userId: { conversationId, userId } },
  });
  if (!participant) return fail('NOT_PARTICIPANT');

  const take = Math.min(Math.max(1, limit ?? DEFAULT_HISTORY_LIMIT), MAX_HISTORY_LIMIT);
  const messages = await prisma.message.findMany({
    where: {
      conversationId,
      ...(before ? { id: { lt: before } } : {}),
      ...(participant.leftAt ? { createdAt: { lte: participant.leftAt } } : {}),
      // Cleared (#45): everything at or before this caller's watermark is
      // gone from their own history, permanently (survives a resync).
      ...(participant.historyClearedMessageId ? { id: { gt: participant.historyClearedMessageId } } : {}),
    },
    orderBy: { id: 'desc' },
    take,
    include: { reactions: true },
  });

  const replyToIds = [...new Set(messages.filter((m) => m.replyToMessageId).map((m) => m.replyToMessageId))];
  const replyTargets =
    replyToIds.length > 0 ? await prisma.message.findMany({ where: { id: { in: replyToIds } } }) : [];
  const replyById = new Map(replyTargets.map((m) => [m.id, m]));

  const referencedUserIds = new Set();
  const items = messages.map((message) => {
    const payload = messagePayload(message);
    if (!message.isDeleted) referencedUserIds.add(message.senderId);
    payload.reactions = message.reactions.map((r) => ({ userId: r.userId, emoji: r.emoji }));
    for (const reaction of message.reactions) referencedUserIds.add(reaction.userId);
    if (message.replyToMessageId) {
      const target = replyById.get(message.replyToMessageId);
      // A reply target this caller cleared for themselves (#45) hydrates as
      // deleted for them only — other Participants still see the real reply
      // preview through their own page of this same history.
      const targetCleared =
        target && participant.historyClearedMessageId && target.id <= participant.historyClearedMessageId;
      payload.replyPreview = !target ? null : targetCleared ? tombstone(target) : messagePayload(target);
      if (target && !target.isDeleted && !targetCleared) referencedUserIds.add(target.senderId);
    }
    return payload;
  });

  const users = await hydrateUsers(prisma, [...referencedUserIds]);
  const nextBefore = messages.length === take ? messages[messages.length - 1].id : null;
  return { ok: true, messages: items, nextBefore, users };
}
