import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { createDirectConversationStarter } from '../src/messaging/directConversation.js';
import { UPDATE_KINDS } from '../src/messaging/kinds.js';
import { createUser } from './support/messaging.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

function buildStarter(overrides = {}) {
  return createDirectConversationStarter({
    prisma,
    onWake: () => {},
    joinUserToConversation: () => {},
    ...overrides,
  });
}

describe('startDirectConversation', () => {
  it('creates a direct Conversation between the caller and the target', async () => {
    const alice = await createUser(prisma, { displayName: 'Alice' });
    const bob = await createUser(prisma, { displayName: 'Bob' });
    const start = buildStarter();

    const result = await start(alice.id, { userId: bob.id });

    assert.equal(result.ok, true);
    assert.equal(result.created, true);
    assert.equal(result.conversation.type, 'direct');
    assert.deepEqual(
      result.participants.map((p) => p.userId).sort(),
      [alice.id, bob.id].sort(),
    );
    assert.deepEqual(
      result.users.map((u) => u.id).sort(),
      [alice.id, bob.id].sort(),
    );
    const participants = await prisma.participant.findMany({
      where: { conversationId: result.conversation.id },
    });
    assert.deepEqual(
      participants.map((p) => p.userId).sort(),
      [alice.id, bob.id].sort(),
    );
  });

  it('writes conversation.joined to both Users and wakes both', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const woken = [];
    const start = buildStarter({ onWake: (userId) => woken.push(userId) });

    const result = await start(alice.id, { userId: bob.id });

    const updates = await prisma.userUpdate.findMany({
      where: { conversationId: result.conversation.id },
    });
    assert.equal(updates.length, 2);
    assert.ok(updates.every((u) => u.kind === UPDATE_KINDS.CONVERSATION_JOINED));
    assert.deepEqual(woken.sort(), [alice.id, bob.id].sort());
  });

  it('joins both Users into the room via joinUserToConversation', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const joined = [];
    const start = buildStarter({ joinUserToConversation: (args) => joined.push(args) });

    const result = await start(alice.id, { userId: bob.id });

    assert.deepEqual(
      joined.map((j) => j.userId).sort(),
      [alice.id, bob.id].sort(),
    );
    assert.ok(joined.every((j) => j.conversationId === result.conversation.id));
  });

  it('returns the existing Conversation instead of creating a second one', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const start = buildStarter();
    const first = await start(alice.id, { userId: bob.id });

    const second = await start(alice.id, { userId: bob.id });
    const reverse = await start(bob.id, { userId: alice.id });

    assert.equal(second.created, false);
    assert.equal(second.conversation.id, first.conversation.id);
    assert.equal(reverse.conversation.id, first.conversation.id);
    // The "already exists" path still returns real participants, not
    // fabricated from the request.
    assert.deepEqual(
      second.participants.map((p) => p.userId).sort(),
      [alice.id, bob.id].sort(),
    );
    const count = await prisma.conversation.count({ where: { type: 'direct' } });
    assert.equal(count, 1);
  });

  it('is idempotent under two concurrent calls: exactly one Conversation results', async () => {
    const alice = await createUser(prisma);
    const bob = await createUser(prisma);
    const start = buildStarter();

    const [a, b] = await Promise.all([
      start(alice.id, { userId: bob.id }),
      start(bob.id, { userId: alice.id }),
    ]);

    assert.equal(a.ok, true);
    assert.equal(b.ok, true);
    assert.equal(a.conversation.id, b.conversation.id);
    const count = await prisma.conversation.count({ where: { type: 'direct' } });
    assert.equal(count, 1);
    const participants = await prisma.participant.findMany({
      where: { conversationId: a.conversation.id },
    });
    assert.equal(participants.length, 2);
  });

  it('rejects a target User that does not exist', async () => {
    const alice = await createUser(prisma);
    const start = buildStarter();

    const result = await start(alice.id, { userId: randomUUID() });

    assert.deepEqual(result, { ok: false, code: 'NOT_FOUND' });
  });

  it('rejects starting a Conversation with yourself', async () => {
    const alice = await createUser(prisma);
    const start = buildStarter();

    const result = await start(alice.id, { userId: alice.id });

    assert.deepEqual(result, { ok: false, code: 'SELF' });
  });

  it('rejects a malformed request', async () => {
    const alice = await createUser(prisma);
    const start = buildStarter();

    assert.deepEqual(await start(alice.id, {}), { ok: false, code: 'INVALID' });
    assert.deepEqual(await start(alice.id, { userId: 'not-a-uuid' }), {
      ok: false,
      code: 'INVALID',
    });
  });
});
