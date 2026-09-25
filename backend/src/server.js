import { createApp } from './app.js';
import { systemClock } from './clock.js';
import { loadConfig } from './config.js';
import { createPrismaClient } from './db.js';
import { createFakeVerifyClient } from './verify/fakeVerifyClient.js';

let config;
try {
  config = loadConfig(process.env);
} catch (err) {
  console.error(`Refusing to start: ${err.message}`);
  process.exit(1);
}

const prisma = createPrismaClient(config.databaseUrl);
// Outside e2e mode the Twilio Verify client is wired in by #23.
const verifyClient = config.e2eMode ? createFakeVerifyClient({ code: config.e2eOtpCode }) : null;

const app = createApp({
  prisma,
  verifyClient,
  clock: systemClock,
  jwtSecret: config.jwtSecret,
  e2eMode: config.e2eMode,
});

const server = app.listen(config.port, () => {
  const mode = config.e2eMode ? ' in E2E MODE (test-only endpoints, fake OTP verifier)' : '';
  console.log(`Convoze backend listening on port ${config.port}${mode}`);
});

async function shutdown() {
  server.close();
  await prisma.$disconnect();
}
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
