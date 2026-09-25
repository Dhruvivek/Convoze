import {
  formatRefreshToken,
  generateRefreshSecret,
  hashRefreshSecret,
  signAccessToken,
} from './tokens.js';

export const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000;

// Signs a verified phone number in on one Device: finds or creates its User
// and opens a new Session, leaving the User's other Sessions untouched.
export async function signIn(prisma, { phoneNumber, deviceId, platform }, { clock, jwtSecret }) {
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
        expiresAt: new Date(now.getTime() + SESSION_TTL_MS),
        lastUsedAt: now,
      },
    });
    return { user, session };
  });

  return {
    accessToken: signAccessToken({ userId: user.id, sessionId: session.id }, { jwtSecret, now }),
    refreshToken: formatRefreshToken(session.id, secret),
    user: { id: user.id, phoneNumber: user.phoneNumber, displayName: user.displayName },
  };
}
