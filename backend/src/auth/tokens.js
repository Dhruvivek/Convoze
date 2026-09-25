import { createHash, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';

export const ACCESS_TOKEN_TTL_SECONDS = 15 * 60;

// Short-lived and stateless; `sessionId` ties it back to the Session that
// can be revoked (ADR 0003).
export function signAccessToken({ userId, sessionId }, { jwtSecret, now }) {
  const iat = Math.floor(now.getTime() / 1000);
  return jwt.sign({ sessionId, iat, exp: iat + ACCESS_TOKEN_TTL_SECONDS }, jwtSecret, {
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
