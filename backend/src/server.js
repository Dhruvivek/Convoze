import { createApp } from './app.js';
import { systemClock } from './clock.js';
import { loadConfig } from './config.js';
import { createPrismaClient } from './db.js';
import { startRetentionJob } from './messaging/retention.js';
import { createFakeVerifyClient } from './verify/fakeVerifyClient.js';
import { createTwilioVerifyClient } from './verify/twilioVerifyClient.js';

let config;
try {
  config = loadConfig(process.env);
} catch (err) {
  console.error(`Refusing to start: ${err.message}`);
  process.exit(1);
}

const hasTwilioCredentials = Boolean(
  config.twilio.accountSid && config.twilio.authToken && config.twilio.verifyServiceSid,
);

const prisma = createPrismaClient(config.databaseUrl);
const verifyClient = config.e2eMode || !hasTwilioCredentials
  ? createFakeVerifyClient({ code: config.e2eOtpCode })
  : createTwilioVerifyClient(config.twilio);

const { httpServer, realtime } = createApp({
  prisma,
  verifyClient,
  clock: systemClock,
  jwtSecret: config.jwtSecret,
  e2eMode: config.e2eMode,
});

const retentionJob = startRetentionJob({ prisma, clock: systemClock });

httpServer.listen(config.port, () => {
  const mode = config.e2eMode ? ' in E2E MODE (test-only endpoints, fake OTP verifier)' : '';
  console.log(`Convoze backend listening on port ${config.port}${mode}`);
});

async function shutdown() {
  retentionJob.stop();
  // Presence's graceful-shutdown pass (#34): every currently online User's
  // `lastSeenAt` is written before their sockets close, so a deliberate
  // restart doesn't leave "last seen" stuck at an earlier disconnect.
  await realtime.presence.markAllOfflineForShutdown();
  // Closes the sockets and the HTTP server under them.
  realtime.io.close();
  await prisma.$disconnect();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
