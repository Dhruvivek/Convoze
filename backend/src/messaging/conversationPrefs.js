import { isUuid } from '../auth/tokens.js';
import { hydrateConversationForUser } from './hydrator.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

// At most this many pinned Conversations at once (#45).
export const PIN_LIMIT = 5;

// "Always" (#45) is stored as a far-future sentinel rather than null, so
// `mutedUntil > now` is always the one check a reader needs — never "null
// means always, a date means until then".
const ALWAYS_SENTINEL = new Date('9999-12-31T00:00:00.000Z');

const MUTE_DURATIONS_MS = {
  '8h': 8 * 60 * 60 * 1000,
  '1w': 7 * 24 * 60 * 60 * 1000,
};

function fail(code) {
  return { ok: false, code };
}

function mutedUntilFor(mute, now) {
  if (mute === null) return null;
  if (mute === 'always') return ALWAYS_SENTINEL;
  return new Date(now.getTime() + MUTE_DURATIONS_MS[mute]);
}

// `PATCH /conversations/:id/prefs`, `POST /conversations/:id/clear` and
// `POST /conversations/:id/delete` (#45): every Conversation preference
// change. Each writes a `conversation.prefs` Update to the caller's own log
// only — nobody else in the Conversation ever learns a preference changed
// (ADR 0009) — in the same transaction as the Participant row update, then
// returns the freshly hydrated row (`hydrateConversationForUser`).
export function createConversationPrefsUpdater({ prisma, onWake, clock }) {
  async function findParticipant(userId, conversationId) {
    if (!isUuid(conversationId)) return undefined;
    return prisma.participant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    });
  }

  async function writePrefsUpdate(userId, conversationId, mutate) {
    await prisma.$transaction(async (tx) => {
      await mutate(tx);
      await writeUpdatesInTx(tx, [{ userId, kind: UPDATE_KINDS.CONVERSATION_PREFS, conversationId }]);
    });
    onWake(userId);
    return { ok: true, ...(await hydrateConversationForUser(prisma, conversationId, userId)) };
  }

  async function updatePrefs(userId, conversationId, request) {
    const participant = await findParticipant(userId, conversationId);
    if (participant === undefined) return fail('INVALID');
    if (!participant) return fail('NOT_FOUND');

    const { pinned, archived, mute } = request ?? {};
    if (pinned !== undefined && typeof pinned !== 'boolean') return fail('INVALID');
    if (archived !== undefined && typeof archived !== 'boolean') return fail('INVALID');
    if (mute !== undefined && mute !== null && !Object.hasOwn(MUTE_DURATIONS_MS, mute) && mute !== 'always') {
      return fail('INVALID');
    }
    if (pinned === undefined && archived === undefined && mute === undefined) return fail('INVALID');

    if (pinned === true && participant.pinnedAt === null) {
      const pinnedCount = await prisma.participant.count({
        where: { userId, pinnedAt: { not: null } },
      });
      if (pinnedCount >= PIN_LIMIT) return fail('PIN_LIMIT');
    }

    const now = clock.now();
    const data = {};
    if (pinned !== undefined) data.pinnedAt = pinned ? now : null;
    if (archived !== undefined) data.archivedAt = archived ? now : null;
    if (mute !== undefined) data.mutedUntil = mutedUntilFor(mute, now);

    return writePrefsUpdate(userId, conversationId, (tx) =>
      tx.participant.update({ where: { id: participant.id }, data }),
    );
  }

  async function clearHistory(userId, conversationId) {
    const participant = await findParticipant(userId, conversationId);
    if (participant === undefined) return fail('INVALID');
    if (!participant) return fail('NOT_FOUND');

    const newest = await prisma.message.findFirst({ where: { conversationId }, orderBy: { id: 'desc' } });
    if (!newest || (participant.historyClearedMessageId && newest.id <= participant.historyClearedMessageId)) {
      // Nothing new to clear; still answer with the current hydrated row.
      return { ok: true, ...(await hydrateConversationForUser(prisma, conversationId, userId)) };
    }

    return writePrefsUpdate(userId, conversationId, (tx) =>
      tx.participant.update({
        where: { id: participant.id },
        data: { historyClearedMessageId: newest.id },
      }),
    );
  }

  async function deleteChat(userId, conversationId) {
    const participant = await findParticipant(userId, conversationId);
    if (participant === undefined) return fail('INVALID');
    if (!participant) return fail('NOT_FOUND');

    const conversation = await prisma.conversation.findUnique({ where: { id: conversationId } });
    if (conversation.type === 'group' && participant.leftAt === null) return fail('MUST_LEAVE_GROUP');

    const now = clock.now();
    const newest = await prisma.message.findFirst({ where: { conversationId }, orderBy: { id: 'desc' } });
    const historyClearedMessageId = newest ? newest.id : participant.historyClearedMessageId;

    return writePrefsUpdate(userId, conversationId, (tx) =>
      tx.participant.update({
        where: { id: participant.id },
        data: { hiddenAt: now, pinnedAt: null, historyClearedMessageId },
      }),
    );
  }

  return { updatePrefs, clearHistory, deleteChat };
}
