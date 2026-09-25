import { isUuid } from '../auth/tokens.js';
import { hydrateUsers } from './hydrator.js';
import { UPDATE_KINDS } from './kinds.js';
import { writeUpdatesInTx } from './updateWriter.js';

function fail(code) {
  return { ok: false, code };
}

function directKeyFor(userIdA, userIdB) {
  return [userIdA, userIdB].sort().join(':');
}

// `POST /conversations/direct { userId }` (#50): returns the caller's
// existing direct Conversation with `userId`, or creates one. `directKey`
// (ADR 0004) makes creation race-safe — two concurrent calls always converge
// on the one row the unique constraint lets through, and the loser here
// re-reads it rather than erroring. Creating one writes `conversation.joined`
// to both Users' logs (ADR 0008), the same as any other membership change.
export function createDirectConversationStarter({ prisma, onWake, joinUserToConversation }) {
  return async function startDirectConversation(userId, request) {
    const { userId: targetUserId } = request ?? {};
    if (!isUuid(targetUserId)) return fail('INVALID');
    if (targetUserId === userId) return fail('SELF');

    const target = await prisma.user.findUnique({ where: { id: targetUserId } });
    if (!target) return fail('NOT_FOUND');

    const directKey = directKeyFor(userId, targetUserId);
    let conversation = await prisma.conversation.findUnique({ where: { directKey } });
    let created = false;

    if (!conversation) {
      try {
        conversation = await prisma.$transaction(
          async (tx) => {
            const row = await tx.conversation.create({
              data: {
                type: 'direct',
                directKey,
                createdById: userId,
                participants: { create: [{ userId }, { userId: targetUserId }] },
              },
            });
            await writeUpdatesInTx(tx, [
              { userId, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: row.id },
              { userId: targetUserId, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: row.id },
            ]);
            return row;
          },
          { timeout: 20_000, maxWait: 10_000 },
        );
        created = true;
      } catch (err) {
        // A concurrent caller (either User, from either direction) won the
        // race to insert `directKey`; its row is the one true result.
        if (err.code !== 'P2002') throw err;
        conversation = await prisma.conversation.findUnique({ where: { directKey } });
        if (!conversation) throw err;
      }
    }

    if (created) {
      joinUserToConversation({ userId, conversationId: conversation.id });
      joinUserToConversation({ userId: targetUserId, conversationId: conversation.id });
      onWake(userId);
      onWake(targetUserId);
    }

    // Sourced from the database rather than assembled from the request, so
    // the response reflects reality even on the "already exists" path (and
    // carries the `users` side-list every REST page does, per the Hydrator
    // from #47).
    const [participantRows, users] = await Promise.all([
      prisma.participant.findMany({ where: { conversationId: conversation.id } }),
      hydrateUsers(prisma, [userId, targetUserId]),
    ]);

    return {
      ok: true,
      conversation,
      created,
      participants: participantRows.map((p) => ({ userId: p.userId, role: p.role })),
      users,
    };
  };
}
