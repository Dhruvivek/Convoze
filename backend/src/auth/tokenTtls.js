// How long tokens live (ADR 0003): a 15-minute access token, and a Session
// that ends after 30 days without a refresh.
export const DEFAULT_TOKEN_TTLS = Object.freeze({
  accessTokenSeconds: 15 * 60,
  refreshTokenSeconds: 30 * 24 * 60 * 60,
});

// One per app. Only E2E mode ever changes it, to make expiry testable
// without waiting.
export function createTokenTtls() {
  return { ...DEFAULT_TOKEN_TTLS };
}
