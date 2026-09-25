import jwt from 'jsonwebtoken';

import { sendError } from '../http/errors.js';
import { isUuid } from './tokens.js';

// Turns a raw access token into who is calling: `{ userId, sessionId }`, or
// null. A valid signature isn't enough: the Session it names must still be
// open, which is what makes revocation take effect immediately (ADR 0003).
export function createAuthenticator({ prisma, jwtSecret, clock }) {
  return async function authenticate(accessToken) {
    let claims;
    try {
      claims = jwt.verify(accessToken, jwtSecret, {
        algorithms: ['HS256'],
        clockTimestamp: Math.floor(clock.now().getTime() / 1000),
      });
    } catch {
      return null;
    }
    const { sub: userId, sessionId } = claims;
    if (!isUuid(userId) || !isUuid(sessionId)) return null;

    const session = await prisma.session.findUnique({ where: { id: sessionId } });
    if (!session || session.revokedAt || session.userId !== userId) return null;
    return { userId, sessionId };
  };
}

// Guards a route: sets `req.auth` from the `Authorization: Bearer` header,
// or answers 401 unauthenticated.
export function requireAuth(authenticate) {
  return async (req, res, next) => {
    const match = /^Bearer (\S+)$/.exec(req.get('Authorization') ?? '');
    const auth = match && (await authenticate(match[1]));
    if (!auth) {
      sendError(res, 401, 'unauthenticated', 'A valid access token is required');
      return;
    }
    req.auth = auth;
    next();
  };
}
