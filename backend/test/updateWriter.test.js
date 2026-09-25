import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { writeUpdates, writeUpdatesInTx } from '../src/messaging/updateWriter.js';
import { createConversation, createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function updatesForUsers(userIds, conversationId) {
  return userIds.map((userId) => ({
    userId,
    kind: UPDATE_KINDS.CONVERSATION_JOINED,
    conversationId,
  }));
}

describe('writeUpdates', () => {
  it('assigns sequential seq values, in Update order, to one User', async () => {
    const alice = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });

    const created = await writeUpdates(prisma, [
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
    ]);

    assert.deepEqual(
      created.map((u) => u.seq),
      [1, 2, 3],
    );
    for (const seq of created.map((u) => u.seq)) assert.equal(typeof seq, 'number');
  });

  it('fans a group write out to one row per member, each keeping their own counter', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
    });

    await writeUpdates(prisma, updatesForUsers([alice.id, bob.id], conversation.id));
    const second = await writeUpdates(prisma, updatesForUsers([alice.id], conversation.id));

    assert.equal(second[0].seq, 2);
    const bobRows = await prisma.userUpdate.findMany({ where: { userId: bob.id } });
    assert.equal(bobRows.length, 1);
    assert.equal(Number(bobRows[0].seq), 1);
  });

  it('keeps seq monotonic and gapless per User under concurrent writers to overlapping User sets', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const carol = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      participantIds: [alice.id, bob.id, carol.id],
    });

    // Overlapping, differently-ordered User sets: without sorting the lock
    // order by userId, this is a classic deadlock shape.
    const writers = [
      updatesForUsers([alice.id, bob.id], conversation.id),
      updatesForUsers([bob.id, alice.id], conversation.id),
      updatesForUsers([bob.id, carol.id], conversation.id),
      updatesForUsers([carol.id, bob.id], conversation.id),
      updatesForUsers([alice.id, carol.id], conversation.id),
      updatesForUsers([carol.id, alice.id], conversation.id),
      updatesForUsers([alice.id, bob.id, carol.id], conversation.id),
      updatesForUsers([carol.id, alice.id, bob.id], conversation.id),
    ];

    await Promise.all(writers.map((updates) => writeUpdates(prisma, updates)));

    for (const user of [alice, bob, carol]) {
      const rows = await prisma.userUpdate.findMany({
        where: { userId: user.id },
        orderBy: { seq: 'asc' },
      });
      const seqs = rows.map((r) => Number(r.seq));
      const expectedCount = writers.filter((w) => w.some((u) => u.userId === user.id)).length;
      assert.deepEqual(
        seqs,
        Array.from({ length: expectedCount }, (_, i) => i + 1),
        `User ${user.id} should have a gapless 1..${expectedCount} run of seqs`,
      );
      const seq = await prisma.userSeq.findUnique({ where: { userId: user.id } });
      assert.equal(Number(seq.lastSeq), expectedCount);
    }
  });

  it('coalesces conversation.receipts to at most one undrained row per (recipient, conversation)', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
    });
    // An unrelated Update for alice, so coalescing can be shown to leave it
    // alone.
    await writeUpdates(prisma, [
      { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED, conversationId: conversation.id },
    ]);

    const first = await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversation.id,
      },
    ]);
    const second = await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversation.id,
      },
    ]);

    const rows = await prisma.userUpdate.findMany({
      where: { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_RECEIPTS },
    });
    assert.equal(rows.length, 1);
    assert.equal(rows[0].id, second[0].id);
    assert.notEqual(rows[0].id, first[0].id);
    assert.equal(Number(rows[0].seq), second[0].seq);

    // The unrelated joined Update survives.
    const joined = await prisma.userUpdate.findMany({
      where: { userId: alice.id, kind: UPDATE_KINDS.CONVERSATION_JOINED },
    });
    assert.equal(joined.length, 1);
  });

  it("doesn't coalesce receipts across different recipients or Conversations", async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversationA = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
    });
    const conversationB = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
    });

    await writeUpdates(prisma, [
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversationA.id,
      },
      {
        userId: bob.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversationA.id,
      },
      {
        userId: alice.id,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
        conversationId: conversationB.id,
      },
    ]);

    const rows = await prisma.userUpdate.findMany({
      where: { kind: UPDATE_KINDS.CONVERSATION_RECEIPTS },
    });
    assert.equal(rows.length, 3);
  });

  it('invokes the wake callback once per affected User, and only once the write has committed', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const conversation = await createConversation(prisma, {
      participantIds: [alice.id, bob.id],
    });
    const woken = [];

    await writeUpdates(prisma, updatesForUsers([alice.id, bob.id, alice.id], conversation.id), {
      onWake: (userId) => woken.push(userId),
    });

    assert.deepEqual(woken.sort(), [alice.id, bob.id].sort());
    // Committed by the time onWake ran, not just queued.
    const rows = await prisma.userUpdate.findMany({ where: { userId: alice.id } });
    assert.equal(rows.length, 2);
  });

  it('rolls every Update back with the rest of its transaction', async () => {
    const alice = await createUser(prisma);
    const conversation = await createConversation(prisma, { participantIds: [alice.id] });

    await assert.rejects(
      prisma.$transaction(async (tx) => {
        await writeUpdatesInTx(tx, [
          {
            userId: alice.id,
            kind: UPDATE_KINDS.CONVERSATION_JOINED,
            conversationId: conversation.id,
          },
        ]);
        throw new Error('boom');
      }),
      { message: 'boom' },
    );

    const rows = await prisma.userUpdate.findMany({ where: { userId: alice.id } });
    assert.equal(rows.length, 0);
    const seq = await prisma.userSeq.findUnique({ where: { userId: alice.id } });
    assert.equal(seq, null);
  });

  it('rejects an Update with an unknown kind or no userId', async () => {
    const alice = await createUser(prisma);

    await assert.rejects(writeUpdates(prisma, [{ userId: alice.id, kind: 'not.a.kind' }]));
    await assert.rejects(
      writeUpdates(prisma, [{ userId: undefined, kind: UPDATE_KINDS.CONVERSATION_JOINED }]),
    );
  });

  it('is a no-op for an empty Updates list', async () => {
    assert.deepEqual(await writeUpdates(prisma, []), []);
  });
});
