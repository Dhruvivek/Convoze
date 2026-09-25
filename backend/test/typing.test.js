import { afterEach, after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import request from 'supertest';

import { signIn } from './support/auth.js';
import { connect, nextEvent, startTestServer, timedOut } from './support/realtime.js';
import { createTestPrisma, resetDatabase } from './support/testApp.js';

// Covers #35: the typing relay is stateless, excludes the sender, attaches
// the sender's userId, and is dropped silently for a Conversation the
// sender isn't actually in.

const prisma = createTestPrisma();
after(() => prisma.$disconnect());
beforeEach(() => resetDatabase(prisma));

let server;
afterEach(() => server?.stop());

const ALICE = '+14155550100';
const BOB = '+14155550101';
const CAROL = '+14155550102';

function seedConversation(participantPhoneNumbers, type = 'group') {
  return request(server.app)
    .post('/__e2e__/conversations')
    .send({ type, participantPhoneNumbers });
}

async function connectAs(phoneNumber) {
  const { accessToken, user } = await signIn(server.app, { phoneNumber });
  const socket = await connect(server.client({ auth: { token: accessToken } }));
  return { socket, userId: user.id };
}

describe('typing relay', () => {
  it("relays typing to other participants with the sender's userId, not echoed back", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB, CAROL]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    const bobReceived = nextEvent(bob.socket, 'typing');
    const aliceMissed = nextEvent(alice.socket, 'typing');
    alice.socket.emit('typing', { conversationId: conversation.body.id });

    assert.deepEqual(await bobReceived, {
      conversationId: conversation.body.id,
      userId: alice.userId,
    });
    assert.equal(await aliceMissed, timedOut);
  });

  it("relays stopTyping the same way", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    const bobReceived = nextEvent(bob.socket, 'stopTyping');
    alice.socket.emit('stopTyping', { conversationId: conversation.body.id });

    assert.deepEqual(await bobReceived, {
      conversationId: conversation.body.id,
      userId: alice.userId,
    });
  });

  it("drops typing for a Conversation the sender isn't in", async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const notAlices = await seedConversation([BOB, CAROL]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    const missed = nextEvent(bob.socket, 'typing');
    alice.socket.emit('typing', { conversationId: notAlices.body.id });

    assert.equal(await missed, timedOut);
  });

  it('drops a malformed payload rather than throwing, and keeps relaying afterwards', async () => {
    server = await startTestServer({ prisma, e2eMode: true });
    const conversation = await seedConversation([ALICE, BOB]);
    const alice = await connectAs(ALICE);
    const bob = await connectAs(BOB);

    const received = nextEvent(bob.socket, 'typing');
    alice.socket.emit('typing', {});
    alice.socket.emit('typing', { conversationId: conversation.body.id });

    // Only the second, well-formed emit gets through — proving the
    // malformed one didn't crash the handler (or the socket) rather than
    // just being silently swallowed by coincidence.
    assert.deepEqual(await received, {
      conversationId: conversation.body.id,
      userId: alice.userId,
    });
  });
});
