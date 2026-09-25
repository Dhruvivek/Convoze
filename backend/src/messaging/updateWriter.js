import { ALL_UPDATE_KINDS, UPDATE_KINDS } from './kinds.js';

// Locks `userIds`' UserSeq rows (creating any that don't exist yet) in
// sorted order, so concurrent writers touching overlapping sets of Users
// never deadlock (ADR 0008), and returns each one's current `lastSeq`.
async function lockUserSeqs(tx, userIds) {
  // One atomic multi-row insert, not a per-user upsert: two concurrent
  // first writers for the same User both running `INSERT ... ON CONFLICT DO
  // NOTHING` is race-safe (the second blocks on the first's row lock, then
  // sees the row and no-ops); Prisma's `upsert()` isn't guaranteed to be.
  await tx.$executeRaw`
    INSERT INTO "UserSeq" ("userId", "lastSeq")
    SELECT unnest(${userIds}::uuid[]), 0
    ON CONFLICT ("userId") DO NOTHING
  `;
  const lastSeqByUser = new Map();
  for (const userId of userIds) {
    const [row] = await tx.$queryRaw`
      SELECT "lastSeq" FROM "UserSeq" WHERE "userId" = ${userId}::uuid FOR UPDATE
    `;
    lastSeqByUser.set(userId, BigInt(row.lastSeq));
  }
  return lastSeqByUser;
}

// Bumps every affected User's per-User seq counter and inserts their
// UserUpdate rows, in the caller's transaction `tx` — the one shared path
// ADR 0008 requires every durable write to go through, so a write that skips
// it is invisible to other Devices until a resync. Each `updates` entry is
// `{ userId, kind, conversationId?, messageId? }`; refs only, per Update
// kind (`kinds.js`).
//
// Coalesces `conversation.receipts`: writing one for a (recipient,
// conversation) that already has an undrained row deletes it first, so at
// most one survives per pair. Safe under concurrent writers because the
// delete only runs after this transaction holds that recipient's UserSeq
// lock, which serialises every write touching them.
export async function writeUpdatesInTx(tx, updates) {
  if (updates.length === 0) return [];
  for (const { userId, kind } of updates) {
    if (!userId || !ALL_UPDATE_KINDS.has(kind)) {
      throw new Error(`writeUpdatesInTx: invalid update ${JSON.stringify({ userId, kind })}`);
    }
  }

  const userIds = [...new Set(updates.map((u) => u.userId))].sort();
  const nextSeq = await lockUserSeqs(tx, userIds);

  for (const update of updates) {
    if (update.kind !== UPDATE_KINDS.CONVERSATION_RECEIPTS) continue;
    await tx.userUpdate.deleteMany({
      where: {
        userId: update.userId,
        conversationId: update.conversationId,
        kind: UPDATE_KINDS.CONVERSATION_RECEIPTS,
      },
    });
  }

  const created = [];
  for (const update of updates) {
    const seq = nextSeq.get(update.userId) + 1n;
    nextSeq.set(update.userId, seq);
    created.push(
      await tx.userUpdate.create({
        data: {
          userId: update.userId,
          seq,
          kind: update.kind,
          conversationId: update.conversationId ?? null,
          messageId: update.messageId ?? null,
        },
      }),
    );
  }

  for (const userId of userIds) {
    await tx.userSeq.update({ where: { userId }, data: { lastSeq: nextSeq.get(userId) } });
  }

  return created.map((row) => ({ ...row, seq: Number(row.seq) }));
}

// Runs `writeUpdatesInTx` in its own transaction and, once it has committed,
// calls `onWake(userId)` once for every affected User — the hook a later
// ticket wires to the connected pumps (ADR 0008); this one just guarantees
// it fires, and with the right User ids. Use `writeUpdatesInTx` directly
// instead when the Updates must commit atomically with other writes (e.g.
// the Message row a `message.new` Update refers to).
export async function writeUpdates(prisma, updates, { onWake } = {}) {
  // Above Prisma's 5s/2s defaults: a busy group serialises writers across
  // its (up to 256, ADR 0008) members on their UserSeq locks, so a writer
  // queued behind several others needs longer than the default budget.
  const created = await prisma.$transaction((tx) => writeUpdatesInTx(tx, updates), {
    timeout: 20_000,
    maxWait: 10_000,
  });
  if (onWake) {
    for (const userId of new Set(created.map((u) => u.userId))) onWake(userId);
  }
  return created;
}
