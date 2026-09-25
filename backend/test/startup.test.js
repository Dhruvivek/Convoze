import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const serverEntry = fileURLToPath(new URL('../src/server.js', import.meta.url));

function startServer(env) {
  return spawnSync(process.execPath, [serverEntry], {
    env: { PATH: process.env.PATH, DATABASE_URL: 'postgresql://unused', ...env },
    encoding: 'utf8',
    timeout: 10_000,
  });
}

describe('server startup guard', () => {
  it('refuses to start in e2e mode when NODE_ENV is production', () => {
    const result = startServer({ E2E_MODE: 'true', NODE_ENV: 'production' });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /E2E_MODE/);
  });

  it('refuses to start in e2e mode on Render', () => {
    const result = startServer({ E2E_MODE: 'true', RENDER: 'true' });

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /E2E_MODE/);
  });

  it('refuses to start outside e2e mode without a JWT secret', () => {
    const result = startServer({});

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /JWT_SECRET/);
  });
});
