import { randomUUID } from 'node:crypto';

import { v2 as cloudinary } from 'cloudinary';

// The only module that touches the Cloudinary SDK/secret (#40, reduced
// scope: photos & documents only, no video). Everything else calls through
// `signUpload`/`verifyUploadResponse`/`deliveryUrls`.

let configured = false;
function configure() {
  if (configured) return;
  const { CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET } = process.env;
  if (!CLOUDINARY_CLOUD_NAME || !CLOUDINARY_API_KEY || !CLOUDINARY_API_SECRET) {
    throw new Error(
      'CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY and CLOUDINARY_API_SECRET are required to sign media uploads/URLs',
    );
  }
  cloudinary.config({
    cloud_name: CLOUDINARY_CLOUD_NAME,
    api_key: CLOUDINARY_API_KEY,
    api_secret: CLOUDINARY_API_SECRET,
  });
  configured = true;
}

// Images: jpg/png/webp, ≤10MB. Documents: pdf/doc/docx/zip/txt, ≤25MB
// (ADR 0002's limits, minus video — out of scope for this pass). Enforced
// here, server-side, rather than by a Cloudinary upload preset: this
// account has no presets configured (they're dashboard-created, nothing an
// agent can provision), so the signed upload omits `upload_preset` and
// `sendMessage.js` checks `media.bytes`/format against these limits itself
// instead — a deliberate, documented deviation from #40's preset-based
// enforcement.
export const MEDIA_LIMITS = {
  image: { resourceType: 'image', maxBytes: 10 * 1024 * 1024, formats: ['jpg', 'jpeg', 'png', 'webp'] },
  file: { resourceType: 'raw', maxBytes: 25 * 1024 * 1024, formats: ['pdf', 'doc', 'docx', 'zip', 'txt'] },
};

// Profile avatars (#43): unlike chat media, these are public — shown in
// lists, notifications and contact matches for anyone who can see the
// person — so they're `type: 'upload'` rather than `'authenticated'`, under
// an unguessable `avatars/<uuid>` id rather than the uploader's own folder.
export const AVATAR_LIMITS = { resourceType: 'image', maxBytes: 5 * 1024 * 1024, formats: ['jpg', 'jpeg', 'png', 'webp'] };

/// A short-lived, signed upload request for `kind` ('image' | 'file' | 'avatar').
/// For 'image'/'file', the server picks `publicId` as `u/<userId>/<uuid>`, so
/// every asset lives in its uploader's own folder — `sendMessage.js` checks
/// that prefix as proof of ownership, with no Cloudinary Admin API call
/// needed (ADR 0002/#40). For 'avatar', `publicId` is `avatars/<uuid>`
/// instead — no per-user folder, and the upload itself is public
/// (`type: 'upload'`) rather than `'authenticated'` (#43).
export function signUpload({ userId, kind }) {
  configure();
  const isAvatar = kind === 'avatar';
  const limits = isAvatar ? AVATAR_LIMITS : MEDIA_LIMITS[kind];
  if (!limits) throw new Error(`signUpload: unknown kind ${kind}`);

  const publicId = isAvatar ? `avatars/${randomUUID()}` : `u/${userId}/${randomUUID()}`;
  const timestamp = Math.floor(Date.now() / 1000);
  const type = isAvatar ? 'upload' : 'authenticated';
  const paramsToSign = { public_id: publicId, timestamp, type };
  const signature = cloudinary.utils.api_sign_request(paramsToSign, cloudinary.config().api_secret);

  return {
    uploadUrl: `https://api.cloudinary.com/v1_1/${cloudinary.config().cloud_name}/${limits.resourceType}/upload`,
    apiKey: cloudinary.config().api_key,
    timestamp,
    signature,
    publicId,
    uploadType: type,
    resourceType: limits.resourceType,
    maxBytes: limits.maxBytes,
    allowedFormats: limits.formats,
  };
}

/// Recomputes Cloudinary's upload-response signature locally (the SDK's own
/// helper, not a hand-rolled hash) — proof this asset really was stored,
/// without an Admin API round trip.
export function verifyUploadResponse({ publicId, version, signature }) {
  configure();
  if (!publicId || !version || !signature) return false;
  return cloudinary.utils.verify_api_response_signature(publicId, version, signature);
}

/// Signed `authenticated` delivery URLs for `publicId` — never persisted,
/// always signed fresh at read time. A `resourceType: 'raw'` (document)
/// asset has no thumbnail concept, so `thumbnailUrl` is the same as `url`.
///
/// ADR 0002 called for these to hard-expire after ~1h via `auth_token`, but
/// that only actually 403s past its `duration` if this Cloudinary account
/// has "Token-based authentication" enabled in its dashboard security
/// settings — confirmed directly (not assumed) that this account does not:
/// every `auth_token` URL came back 401 "Unauthenticated access" even
/// immediately after upload. So delivery relies on `sign_url` alone, which
/// doesn't hard-expire but still requires the API secret to construct, so
/// URLs aren't guessable.
export function deliveryUrls({ publicId, resourceType }) {
  configure();
  const url = cloudinary.url(publicId, {
    resource_type: resourceType,
    type: 'authenticated',
    sign_url: true,
    secure: true,
  });
  if (resourceType !== 'image') return { url, thumbnailUrl: url };
  const thumbnailUrl = cloudinary.url(publicId, {
    resource_type: resourceType,
    type: 'authenticated',
    sign_url: true,
    secure: true,
    transformation: [{ width: 480, crop: 'limit' }],
  });
  return { url, thumbnailUrl };
}

/// The public, unsigned delivery URL for an avatar (#43) — `type: 'upload'`,
/// so unlike `deliveryUrls` this never needs re-signing at read time; it's
/// stored as-is in `User.avatarUrl`. Cropped to a square around its center
/// (`c_fill,g_auto`) so it always fits a round avatar without client-side
/// cropping.
export function avatarDeliveryUrl(publicId) {
  configure();
  return cloudinary.url(publicId, {
    resource_type: 'image',
    type: 'upload',
    secure: true,
    transformation: [{ width: 512, height: 512, crop: 'fill', gravity: 'auto' }],
  });
}

/// Best-effort delete of a replaced/removed asset (#43: "an old avatar
/// deleted from storage when it's replaced or removed"). Callers await this
/// but never fail the request over it — a stray orphaned asset is a cheaper
/// mistake than a user-facing 500 on their own profile edit.
export async function destroyAsset(publicId, resourceType) {
  configure();
  try {
    await cloudinary.uploader.destroy(publicId, {
      resource_type: resourceType,
      type: publicId.startsWith('avatars/') ? 'upload' : 'authenticated',
    });
  } catch (err) {
    console.error(`destroyAsset(${publicId}) failed`, err);
  }
}
