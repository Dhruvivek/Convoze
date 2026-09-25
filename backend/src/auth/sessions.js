import {
  formatRefreshToken,
  generateRefreshSecret,
  hashRefreshSecret,
  parseRefreshToken,
  signAccessToken,
} from './tokens.js';

function sessionExpiry(now, tokenTtls) {
  return new Date(now.getTime() + tokenTtls.refreshTokenSeconds * 1000);
}

function issuePair({ userId, sessionId, secret }, { jwtSecret, now, tokenTtls }) {
  return {
    accessToken: signAccessToken(
      { userId, sessionId },
      { jwtSecret, now, ttlSeconds: tokenTtls.accessTokenSeconds },
    ),
    refreshToken: formatRefreshToken(sessionId, secret),
  };
}

// Signs a verified phone number in on one Device: finds or creates its User
// and opens a new Session, leaving the User's other Sessions untouched.
export async function signIn(
  prisma,
  { phoneNumber, deviceId, platform },
  { clock, jwtSecret, tokenTtls },
) {
  const now = clock.now();
  const secret = generateRefreshSecret();

  const { user, session } = await prisma.$transaction(async (tx) => {
    // A single-unique-field upsert runs as INSERT ... ON CONFLICT, so two
    // first-time verifies racing for one number both land on the same User.
    const user = await tx.user.upsert({
      where: { phoneNumber },
      create: { phoneNumber, phoneVerifiedAt: now },
      update: { phoneVerifiedAt: now },
    });
    const session = await tx.session.create({
      data: {
        userId: user.id,
        deviceId,
        platform,
        refreshTokenHash: hashRefreshSecret(secret),
        issuedAt: now,
        expiresAt: sessionExpiry(now, tokenTtls),
        lastUsedAt: now,
      },
    });
    return { user, session };
  });

  return {
    ...issuePair({ userId: user.id, sessionId: session.id, secret }, { jwtSecret, now, tokenTtls }),
    user: { id: user.id, phoneNumber: user.phoneNumber, displayName: user.displayName },
  };
}

// Trades a refresh token for a new pair, rotating the secret on the same
// Session row. Null when the token can't be refreshed.
export async function refreshSession(
  prisma,
  refreshToken,
  { clock, jwtSecret, tokenTtls, sessionRevoked },
) {
  const now = clock.now();
  const parsed = parseRefreshToken(refreshToken);
  if (!parsed) return null;
  const { sessionId, secret } = parsed;
  const session = await prisma.session.findUnique({ where: { id: sessionId } });
  if (!session || session.revokedAt || session.expiresAt <= now) return null;
  if (session.refreshTokenHash !== hashRefreshSecret(secret)) {
    await revokeSession(prisma, session, now, sessionRevoked);
    return null;
  }

  // Conditional on the hash just checked, so of several concurrent refreshes
  // with one token only the first rotates; the rest find the hash already
  // changed, which is reuse like any other.
  const nextSecret = generateRefreshSecret();
  const { count } = await prisma.session.updateMany({
    where: { id: sessionId, refreshTokenHash: session.refreshTokenHash, revokedAt: null },
    data: {
      refreshTokenHash: hashRefreshSecret(nextSecret),
      lastUsedAt: now,
      expiresAt: sessionExpiry(now, tokenTtls),
    },
  });
  if (count === 0) {
    await revokeSession(prisma, session, now, sessionRevoked);
    return null;
  }

  return issuePair(
    { userId: session.userId, sessionId, secret: nextSecret },
    { jwtSecret, now, tokenTtls },
  );
}

// Signs one Device out: ends the Session the caller is using, and no other.
export async function logout(prisma, { sessionId, userId }, { clock, sessionRevoked }) {
  await revokeSession(prisma, { id: sessionId, userId }, clock.now(), sessionRevoked);
}

// Every revocation goes through here, so the hook fires for each one: on
// logout, and on reuse of a secret that isn't the Session's current one,
// which has already been rotated away, so someone else may hold the Session
// and it ends for everyone (ADR 0003). Conditional on the Session still being
// open, so of several concurrent revocations only one fires the hook.
async function revokeSession(prisma, { id, userId }, now, sessionRevoked) {
  const { count } = await prisma.session.updateMany({
    where: { id, revokedAt: null },
    data: { revokedAt: now },
  });
  if (count > 0) sessionRevoked.fire({ sessionId: id, userId });
}
