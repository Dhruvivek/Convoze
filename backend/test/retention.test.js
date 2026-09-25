import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { pruneOldUpdates, RETENTION_DAYS } from '../src/messaging/retention.js';
import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { writeUpdates } from '../src/messaging/updateWriter.js';
import { createConversation, createUser } from './support/messaging.js';
import { createFakeClock } from './support/fakeClock.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const DAY_MS = 24 * 60 * 60 * 1000;

// UserUpdate.createdAt is stamped by Postgres's own `now()` at insert time
// (unlike this backend's other time-dependent fields), so a fake clock can't
// control a row's age by advancing before it's written. Tests backdate rows
// directly instead, and use the clock only for `pruneOldUpdates`'s "now".
async function backdate(prisma, rowId, createdAt) {
  await prisma.userUpdate.update({ where: { id: rowId }, data: { createdAt } });
}

describe('pruneOldUpdates', () => {
  it('prunes UserUpdate rows older than 30 days and leaves newer ones', async () => {
    const clock = createFakeClock();
    const alice = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });

    const [oldRow, newRow] = await writeUpdates(prisma, [
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
    ]);
    await backdate(prisma, oldRow.id, new Date(clock.now().getTime() - (RETENTION_DAYS * DAY_MS + 1)));
    await backdate(prisma, newRow.id, new Date(clock.now().getTime() - (RETENTION_DAYS * DAY_MS - DAY_MS)));

    const pruned = await pruneOldUpdates(prisma, clock);

    assert.equal(pruned, 1);
    const remaining = await prisma.userUpdate.findMany({ where: { userId: alice.id } });
    assert.deepEqual(
      remaining.map((r) => r.id),
      [newRow.id],
    );
    assert.notEqual(remaining[0].id, oldRow.id);
  });

  it('leaves everything at or under exactly 30 days old alone', async () => {
    const clock = createFakeClock();
    const alice = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });

    const [row] = await writeUpdates(prisma, [
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
    ]);
    await backdate(prisma, row.id, new Date(clock.now().getTime() - RETENTION_DAYS * DAY_MS));

    const pruned = await pruneOldUpdates(prisma, clock);

    assert.equal(pruned, 0);
    const remaining = await prisma.userUpdate.findMany({ where: { userId: alice.id } });
    assert.equal(remaining.length, 1);
  });

  it('is a no-op when there is nothing to prune', async () => {
    const clock = createFakeClock();
    assert.equal(await pruneOldUpdates(prisma, clock), 0);
  });
});
