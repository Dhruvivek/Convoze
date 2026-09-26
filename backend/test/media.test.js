import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { v2 as cloudinary } from 'cloudinary';
import request from 'supertest';

import { createMessageDeleter } from '../src/messaging/deleteMessage.js';
import { messagePayload } from '../src/messaging/messagePayload.js';
import { createSendRateLimit } from '../src/messaging/rateLimiter.js';
import { createMessageSender } from '../src/messaging/sendMessage.js';
import { signIn } from './support/auth.js';
import { createConversation } from './support/messaging.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

// A synthetic "as Cloudinary would" upload-response signature, computed
// locally with the real account secret (#40's stated testing philosophy:
// verify signature math without a network call, reserving the one real
// upload below for proving the integration itself works end to end).
function signResponse(publicId, version) {
  return cloudinary.utils.api_sign_request(
    { public_id: publicId, version },
    process.env.CLOUDINARY_API_SECRET,
    null,
    1,
  );
}

// A minimal valid 1x1 transparent PNG, for the one real upload test.
const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

function auth(token) {
  return `Bearer ${token}`;
}

const ALICE = '+14155550300';
const BOB = '+14155550301';

describe('media sharing (#40, photos & documents)', () => {
  const prisma = createTestPrisma();

  beforeEach(() => resetDatabase(prisma));
  after(() => prisma.$disconnect());

  it('POST /media/upload-signature returns a signed request in the caller\'s own folder', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/media/upload-signature')
      .set('Authorization', auth(alice.accessToken))
      .send({ kind: 'image' });

    assert.equal(res.status, 200);
    assert.match(res.body.publicId, new RegExp(`^u/${alice.user.id}/`));
    assert.equal(res.body.resourceType, 'image');
    assert.equal(typeof res.body.signature, 'string');
    assert.ok(res.body.uploadUrl.includes('/image/upload'));
  });

  it('rejects an unknown kind', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app)
      .post('/media/upload-signature')
      .set('Authorization', auth(alice.accessToken))
      .send({ kind: 'video' });

    assert.equal(res.status, 400);
  });

  it('sends and hydrates a real photo end to end through Cloudinary', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const sigRes = await request(app)
      .post('/media/upload-signature')
      .set('Authorization', auth(alice.accessToken))
      .send({ kind: 'image' });
    assert.equal(sigRes.status, 200);
    const { uploadUrl, apiKey, timestamp, signature, publicId } = sigRes.body;

    const form = new FormData();
    form.set('file', new Blob([TINY_PNG], { type: 'image/png' }), 'tiny.png');
    form.set('api_key', apiKey);
    form.set('timestamp', String(timestamp));
    form.set('signature', signature);
    form.set('public_id', publicId);
    form.set('type', 'authenticated');
    const uploadRes = await fetch(uploadUrl, { method: 'POST', body: form });
    const uploadBody = await uploadRes.json();
    assert.equal(uploadRes.status, 200, JSON.stringify(uploadBody));

    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });
    const sendResult = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: 'look at this',
      media: {
        publicId: uploadBody.public_id,
        version: uploadBody.version,
        signature: uploadBody.signature,
        resourceType: uploadBody.resource_type,
        bytes: uploadBody.bytes,
        format: uploadBody.format,
        width: uploadBody.width,
        height: uploadBody.height,
      },
    });
    assert.equal(sendResult.ok, true);

    const message = await prisma.message.findUnique({ where: { id: sendResult.messageId } });
    const payload = messagePayload(message);
    assert.equal(payload.type, 'image');
    assert.equal(payload.content, 'look at this');
    assert.equal(payload.mediaPublicId, publicId);
    assert.ok(payload.mediaUrl.startsWith('https://'));
    assert.ok(payload.mediaThumbnailUrl.includes('w_480'));

    // Not just a string-shape check: the delivery URL must actually resolve.
    // A signed `authenticated` URL can look right and still 401 (e.g. a
    // stray `auth_token` param on an account without token-based auth
    // enabled), which a shape-only assertion would never catch.
    const deliveryRes = await fetch(payload.mediaUrl);
    assert.equal(deliveryRes.status, 200);
    const thumbRes = await fetch(payload.mediaThumbnailUrl);
    assert.equal(thumbRes.status, 200);
  });

  it('rejects a media message whose response signature is forged', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId: `u/${alice.user.id}/fake`,
        version: 1,
        signature: 'not-a-real-signature',
        resourceType: 'image',
        bytes: 1000,
      },
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it("rejects a media message referencing another user's publicId", async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${bob.user.id}/someone-elses-asset`;
    const version = 1700000000;
    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'image',
        bytes: 1000,
      },
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it('rejects an oversized image as TOO_LARGE', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${alice.user.id}/too-big`;
    const version = 1700000001;
    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'image',
        bytes: 11 * 1024 * 1024,
      },
    });
    assert.deepEqual(res, { ok: false, code: 'TOO_LARGE' });
  });

  it('rejects a resourceType that does not match the message type', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${alice.user.id}/mismatched`;
    const version = 1700000002;
    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'raw',
        bytes: 1000,
      },
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it('requires a fileName for a document message', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${alice.user.id}/a-doc`;
    const version = 1700000003;
    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'file',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'raw',
        bytes: 1000,
      },
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it('rejects an unsupported format even when resourceType and size are fine', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${alice.user.id}/wrong-format`;
    const version = 1700000005;
    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'image',
        bytes: 1000,
        format: 'gif',
      },
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it('still rejects an empty text message (regression)', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const res = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      content: '   ',
    });
    assert.deepEqual(res, { ok: false, code: 'INVALID' });
  });

  it('GET /messages/:id/media 404s for a non-participant', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: '+14155550302' });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });

    const publicId = `u/${alice.user.id}/for-media-get`;
    const version = 1700000004;
    const sendResult = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'image',
        bytes: 1000,
        format: 'jpg',
      },
    });
    assert.equal(sendResult.ok, true);

    const res = await request(app)
      .get(`/messages/${sendResult.messageId}/media`)
      .set('Authorization', auth(carol.accessToken));
    assert.equal(res.status, 404);

    const okRes = await request(app)
      .get(`/messages/${sendResult.messageId}/media`)
      .set('Authorization', auth(bob.accessToken));
    assert.equal(okRes.status, 200);
    assert.ok(okRes.body.url.startsWith('https://'));
  });

  it("deleting a media message clears its asset reference, so it's no longer signable", async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });
    const deleter = createMessageDeleter({ prisma, onWake: realtime.wakeUser });

    const publicId = `u/${alice.user.id}/to-be-deleted`;
    const version = 1700000006;
    const sendResult = await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      type: 'image',
      content: '',
      media: {
        publicId,
        version,
        signature: signResponse(publicId, version),
        resourceType: 'image',
        bytes: 1000,
        format: 'jpg',
      },
    });
    assert.equal(sendResult.ok, true);

    const deleteResult = await deleter(alice.user.id, { messageId: sendResult.messageId });
    assert.deepEqual(deleteResult, { ok: true });

    const message = await prisma.message.findUnique({ where: { id: sendResult.messageId } });
    assert.equal(message.mediaPublicId, null);
    assert.equal(message.mediaResourceType, null);
    assert.equal(messagePayload(message).mediaUrl, undefined);

    const res = await request(app)
      .get(`/messages/${sendResult.messageId}/media`)
      .set('Authorization', auth(bob.accessToken));
    assert.equal(res.status, 404);
  });
});
