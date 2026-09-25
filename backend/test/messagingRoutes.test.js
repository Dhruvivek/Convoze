import { randomUUID } from 'node:crypto';
import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { createConversation, createMessage } from './support/messaging.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

const ALICE = '+14155550100';
const BOB = '+14155550101';
const CAROL = '+14155550102';

function auth(token) {
  return `Bearer ${token}`;
}

describe('GET /conversations', () => {
  it('requires authentication', async () => {
    const { app } = buildTestApp({ prisma });
    const res = await request(app).get('/conversations');
    assert.equal(res.status, 401);
  });

  it("lists the caller's Conversations, hydrated", async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      participantIds: [alice.user.id, bob.user.id],
    });
    await createMessage(prisma, { conversationId: conversation.id, senderId: bob.user.id });

    const res = await request(app).get('/conversations').set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
    assert.equal(res.body.conversations.length, 1);
    assert.equal(res.body.conversations[0].id, conversation.id);
    assert.equal(typeof res.body.currentSeq, 'number');
    assert.ok(res.body.users.some((u) => u.id === bob.user.id));
  });

  it('rejects an invalid limit', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .get('/conversations?limit=0')
      .set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 400);
  });
});

describe('GET /conversations/:id/messages', () => {
  it('returns 404 for a non-Participant', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });
    const conversation = await createConversation(prisma, {
      participantIds: [alice.user.id, bob.user.id],
    });

    const res = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(carol.accessToken));

    assert.equal(res.status, 404);
  });

  it('returns paged history for a Participant', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      participantIds: [alice.user.id, bob.user.id],
    });
    const message = await createMessage(prisma, {
      conversationId: conversation.id,
      senderId: bob.user.id,
    });

    const res = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(alice.accessToken));

    assert.equal(res.status, 200);
    assert.equal(res.body.messages.length, 1);
    assert.equal(res.body.messages[0].id, message.id);
  });
});

describe('POST /conversations/direct', () => {
  it('creates a direct Conversation and returns 201', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });

    const res = await request(app)
      .post('/conversations/direct')
      .set('Authorization', auth(alice.accessToken))
      .send({ userId: bob.user.id });

    assert.equal(res.status, 201);
    assert.equal(res.body.type, 'direct');
    assert.deepEqual(
      res.body.participants.map((p) => p.userId).sort(),
      [alice.user.id, bob.user.id].sort(),
    );
    assert.ok(res.body.users.some((u) => u.id === bob.user.id));
  });

  it('returns 200 with the existing Conversation on a repeat call', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const first = await request(app)
      .post('/conversations/direct')
      .set('Authorization', auth(alice.accessToken))
      .send({ userId: bob.user.id });

    const second = await request(app)
      .post('/conversations/direct')
      .set('Authorization', auth(alice.accessToken))
      .send({ userId: bob.user.id });

    assert.equal(second.status, 200);
    assert.equal(second.body.id, first.body.id);
  });

  it('returns 404 for a User that does not exist', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/conversations/direct')
      .set('Authorization', auth(alice.accessToken))
      .send({ userId: randomUUID() });

    assert.equal(res.status, 404);
  });

  it('returns 400 for yourself', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/conversations/direct')
      .set('Authorization', auth(alice.accessToken))
      .send({ userId: alice.user.id });

    assert.equal(res.status, 400);
  });
});
