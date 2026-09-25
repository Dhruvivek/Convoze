import { parseRefreshToken } from '../auth/tokens.js';

// Counts calls to POST /auth/refresh per Session, whatever their outcome, so
// e2e tests can check the client refreshes exactly as often as it should.
export function createRefreshCounter() {
  const counts = new Map();

  return {
    count(sessionId) {
      return counts.get(sessionId) ?? 0;
    },
    clear() {
      counts.clear();
    },
    middleware(req, _res, next) {
      const token = req.body?.refreshToken;
      const sessionId = typeof token === 'string' && parseRefreshToken(token)?.sessionId;
      if (sessionId) counts.set(sessionId, (counts.get(sessionId) ?? 0) + 1);
      next();
    },
  };
}
