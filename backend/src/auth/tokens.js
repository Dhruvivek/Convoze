import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';

// Short-lived and stateless; `sessionId` ties it back to the Session that
// can be revoked (ADR 0003).
export function signAccessToken({ userId, sessionId }, { jwtSecret, now, ttlSeconds }) {
  const iat = Math.floor(now.getTime() / 1000);
  return jwt.sign({ sessionId, iat, exp: iat + ttlSeconds }, jwtSecret, {
    algorithm: 'HS256',
    subject: userId,
  });
}

// 256 bits of randomness. Only its hash is stored.
export function generateRefreshSecret() {
  return randomBytes(32).toString('base64url');
}

export function hashRefreshSecret(secret) {
  return createHash('sha256').update(secret).digest('hex');
}

// The Session id travels in the clear so the server can find the row to
// compare the secret's hash against.
export function formatRefreshToken(sessionId, secret) {
  return `${sessionId}.${secret}`;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// The Session id is checked here because Postgres rejects a malformed uuid
// outright rather than finding nothing.
export function isUuid(value) {
  return typeof value === 'string' && UUID.test(value);
}

// The inverse of formatRefreshToken; null when the token isn't of that form.
export function parseRefreshToken(token) {
  const dot = token.indexOf('.');
  if (dot < 0) return null;
  const sessionId = token.slice(0, dot);
  const secret = token.slice(dot + 1);
  return isUuid(sessionId) && secret ? { sessionId, secret } : null;
}
