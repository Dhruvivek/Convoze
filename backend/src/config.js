// Reads and validates configuration from environment variables. Throws on
// anything that must stop the server from starting.
export function loadConfig(env) {
  const e2eMode = env.E2E_MODE === 'true';

  if (e2eMode && (env.NODE_ENV === 'production' || env.RENDER === 'true')) {
    throw new Error(
      'E2E_MODE must never be enabled in production: it mounts test-only endpoints and a fake OTP verifier.',
    );
  }

  if (!env.DATABASE_URL) {
    throw new Error('DATABASE_URL is required');
  }

  const jwtSecret = env.JWT_SECRET ?? (e2eMode ? 'e2e-only-jwt-secret' : undefined);
  if (!jwtSecret) {
    throw new Error('JWT_SECRET is required');
  }

  const twilio = {
    accountSid: env.TWILIO_ACCOUNT_SID,
    authToken: env.TWILIO_AUTH_TOKEN,
    verifyServiceSid: env.TWILIO_VERIFY_SERVICE_SID,
  };
  // E2E mode swaps in a fake Verify client, so only the real one needs these.
  if (!e2eMode && !(twilio.accountSid && twilio.authToken && twilio.verifyServiceSid)) {
    throw new Error(
      'TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_VERIFY_SERVICE_SID are required',
    );
  }

  return {
    port: Number(env.PORT ?? 3000),
    databaseUrl: env.DATABASE_URL,
    jwtSecret,
    e2eMode,
    twilio,
    e2eOtpCode: env.E2E_OTP_CODE ?? '000000',
  };
}
