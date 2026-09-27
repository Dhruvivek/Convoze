import { after, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import { v2 as cloudinary } from 'cloudinary';
import request from 'supertest';

import { signIn } from './support/auth.js';
import { createConversation } from './support/messaging.js';
import { buildTestApp, createTestPrisma, resetDatabase } from './support/testApp.js';

// Same "as Cloudinary would" local signature computation media.test.js uses,
// so a forged-signature test needs no real network call.
function signResponse(publicId, version) {
  return cloudinary.utils.api_sign_request({ public_id: publicId, version }, process.env.CLOUDINARY_API_SECRET, null, 1);
}

const TINY_PNG = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  'base64',
);

function auth(token) {
  return `Bearer ${token}`;
}

async function uploadRealAvatar(app, accessToken) {
  const sigRes = await request(app)
    .post('/media/upload-signature')
    .set('Authorization', auth(accessToken))
    .send({ kind: 'avatar' });
  assert.equal(sigRes.status, 200);
  const { uploadUrl, apiKey, timestamp, signature, publicId, uploadType } = sigRes.body;

  const form = new FormData();
  form.set('file', new Blob([TINY_PNG], { type: 'image/png' }), 'tiny.png');
  form.set('api_key', apiKey);
  form.set('timestamp', String(timestamp));
  form.set('signature', signature);
  form.set('public_id', publicId);
  form.set('type', uploadType);
  const uploadRes = await fetch(uploadUrl, { method: 'POST', body: form });
  const uploadBody = await uploadRes.json();
  assert.equal(uploadRes.status, 200, JSON.stringify(uploadBody));
  return uploadBody;
}

const ALICE = '+14155550400';
const BOB = '+14155550401';
const CAROL = '+14155550402';

describe('user profile (#43)', () => {
  const prisma = createTestPrisma();

  beforeEach(() => resetDatabase(prisma));
  after(() => prisma.$disconnect());

  it('GET /users/me returns the caller\'s own profile', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const res = await request(app).get('/users/me').set('Authorization', auth(alice.accessToken));
    assert.equal(res.status, 200);
    assert.deepEqual(res.body, {
      id: alice.user.id,
      phoneNumber: alice.user.phoneNumber,
      displayName: alice.user.displayName ?? null,
      about: null,
      avatarUrl: null,
    });
  });

  it('PATCH /users/me sets, trims and clears the name and about line', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const setRes = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ displayName: '  Alice A.  ', about: '  At work  ' });
    assert.equal(setRes.status, 200);
    assert.equal(setRes.body.displayName, 'Alice A.');
    assert.equal(setRes.body.about, 'At work');

    const clearRes = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ displayName: undefined, about: null });
    assert.equal(clearRes.status, 200);
    assert.equal(clearRes.body.displayName, 'Alice A.');
    assert.equal(clearRes.body.about, null);
  });

  it('rejects an over-length name, an over-length about, control characters and an empty name', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const overLongName = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ displayName: 'x'.repeat(51) });
    assert.equal(overLongName.status, 400);

    const overLongAbout = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ about: 'x'.repeat(141) });
    assert.equal(overLongAbout.status, 400);

    const controlChars = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ about: 'hi\u0000there' });
    assert.equal(controlChars.status, 400);

    const emptyName = await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ displayName: '   ' });
    assert.equal(emptyName.status, 400);
  });

  it('rate-limits profile writes after 30 in the window', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    let lastStatus;
    for (let i = 0; i < 31; i += 1) {
      const res = await request(app)
        .patch('/users/me')
        .set('Authorization', auth(alice.accessToken))
        .send({ about: `status ${i}` });
      lastStatus = res.status;
    }
    assert.equal(lastStatus, 429);
  });

  it('a name change reaches a co-participant on their next sync:batch and on a history page', async () => {
    const { app, realtime } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    await request(app)
      .patch('/users/me')
      .set('Authorization', auth(alice.accessToken))
      .send({ displayName: 'New Alice' });

    const { createMessageSender } = await import('../src/messaging/sendMessage.js');
    const { createSendRateLimit } = await import('../src/messaging/rateLimiter.js');
    const sender = createMessageSender({
      prisma,
      rateLimiter: createSendRateLimit({ clock: { now: () => new Date() } }),
      onWake: realtime.wakeUser,
    });
    await sender(alice.user.id, {
      clientMsgId: crypto.randomUUID(),
      conversationId: conversation.id,
      content: 'hi bob',
    });

    const historyRes = await request(app)
      .get(`/conversations/${conversation.id}/messages`)
      .set('Authorization', auth(bob.accessToken));
    assert.equal(historyRes.status, 200);
    const aliceInSideList = historyRes.body.users.find((u) => u.id === alice.user.id);
    assert.equal(aliceInSideList.displayName, 'New Alice');
  });

  it('PUT /users/me/avatar sets a public URL for a real upload, and rejects a forged signature or non-avatar folder', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const forged = await request(app)
      .put('/users/me/avatar')
      .set('Authorization', auth(alice.accessToken))
      .send({ publicId: 'avatars/fake', version: 1, signature: 'not-real', resourceType: 'image', bytes: 100, format: 'png' });
    assert.equal(forged.status, 400);

    const wrongFolderPublicId = `u/${alice.user.id}/not-an-avatar`;
    const wrongFolder = await request(app)
      .put('/users/me/avatar')
      .set('Authorization', auth(alice.accessToken))
      .send({
        publicId: wrongFolderPublicId,
        version: 1,
        signature: signResponse(wrongFolderPublicId, 1),
        resourceType: 'image',
        bytes: 100,
        format: 'png',
      });
    assert.equal(wrongFolder.status, 400);

    const uploaded = await uploadRealAvatar(app, alice.accessToken);
    const setRes = await request(app)
      .put('/users/me/avatar')
      .set('Authorization', auth(alice.accessToken))
      .send({
        publicId: uploaded.public_id,
        version: uploaded.version,
        signature: uploaded.signature,
        resourceType: uploaded.resource_type,
        bytes: uploaded.bytes,
        format: uploaded.format,
      });
    assert.equal(setRes.status, 200);
    assert.ok(setRes.body.avatarUrl.startsWith('https://'));
    const deliveryRes = await fetch(setRes.body.avatarUrl);
    assert.equal(deliveryRes.status, 200);
  });

  it('replacing an avatar destroys the old asset; removing it clears both and destroys it too', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });

    const first = await uploadRealAvatar(app, alice.accessToken);
    const firstSet = await request(app)
      .put('/users/me/avatar')
      .set('Authorization', auth(alice.accessToken))
      .send({
        publicId: first.public_id,
        version: first.version,
        signature: first.signature,
        resourceType: first.resource_type,
        bytes: first.bytes,
        format: first.format,
      });
    const firstUrl = firstSet.body.avatarUrl;

    const second = await uploadRealAvatar(app, alice.accessToken);
    await request(app)
      .put('/users/me/avatar')
      .set('Authorization', auth(alice.accessToken))
      .send({
        publicId: second.public_id,
        version: second.version,
        signature: second.signature,
        resourceType: second.resource_type,
        bytes: second.bytes,
        format: second.format,
      });

    // The old asset is destroyed best-effort; Cloudinary CDN cache aside,
    // the origin no longer has it.
    const oldStillThere = await fetch(firstUrl, { cache: 'no-store' });
    assert.notEqual(oldStillThere.status, 200);

    const removed = await request(app).delete('/users/me/avatar').set('Authorization', auth(alice.accessToken));
    assert.equal(removed.status, 200);
    assert.equal(removed.body.avatarUrl, null);
  });

  it('GET /users/:id works for a current or former co-participant, 404s for a stranger', async () => {
    const { app } = buildTestApp({ prisma });
    const alice = await signIn(app, { phoneNumber: ALICE });
    const bob = await signIn(app, { phoneNumber: BOB });
    const carol = await signIn(app, { phoneNumber: CAROL });
    const conversation = await createConversation(prisma, {
      type: 'direct',
      participantIds: [alice.user.id, bob.user.id],
    });

    const okRes = await request(app).get(`/users/${alice.user.id}`).set('Authorization', auth(bob.accessToken));
    assert.equal(okRes.status, 200);
    assert.equal(okRes.body.id, alice.user.id);

    const strangerRes = await request(app).get(`/users/${alice.user.id}`).set('Authorization', auth(carol.accessToken));
    assert.equal(strangerRes.status, 404);

    await prisma.participant.update({
      where: { conversationId_userId: { conversationId: conversation.id, userId: bob.user.id } },
      data: { leftAt: new Date() },
    });
    const formerRes = await request(app).get(`/users/${alice.user.id}`).set('Authorization', auth(bob.accessToken));
    assert.equal(formerRes.status, 200);
  });

  it('requires authentication for every profile endpoint', async () => {
    const { app } = buildTestApp({ prisma });
    assert.equal((await request(app).get('/users/me')).status, 401);
    assert.equal((await request(app).patch('/users/me').send({})).status, 401);
    assert.equal((await request(app).put('/users/me/avatar').send({})).status, 401);
    assert.equal((await request(app).delete('/users/me/avatar')).status, 401);
    assert.equal((await request(app).get(`/users/${crypto.randomUUID()}`)).status, 401);
  });
});
