// Applies migrations to the test database before `npm test`.
import { execFileSync } from 'node:child_process';

try {
  process.loadEnvFile();
} catch {
  // No .env file; rely on the real environment.
}

const url = process.env.TEST_DATABASE_URL;
if (!url) {
  console.error('TEST_DATABASE_URL must be set to run the backend tests');
  process.exit(1);
}

execFileSync('npx', ['prisma', 'migrate', 'deploy'], {
  stdio: 'inherit',
  env: { ...process.env, DATABASE_URL: url },
});
