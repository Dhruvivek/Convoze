# Convoze

A real-time 1:1 and group chat app: Flutter mobile client (`mobile/`), Node.js backend (`backend/`), PostgreSQL. Domain language lives in `CONTEXT.md`; architecture decisions live in `docs/adr/`.

## Development

### Prerequisites

- Node.js 22.18+
- Flutter (see `mobile/pubspec.yaml` for the SDK constraint), plus an Android emulator or iOS simulator for the e2e suite
- **PostgreSQL 18+**, because primary keys default to Postgres's native `uuidv7()` (ADR 0004)

### Start Postgres

Any PostgreSQL 18+ server works. With Docker:

```sh
docker run -d --name convoze-pg -e POSTGRES_PASSWORD=postgres -p 5432:5432 postgres:18
```

### Backend

```sh
cd backend
cp .env.example .env     # adjust DATABASE_URL / TEST_DATABASE_URL if needed
npm install
npm run db:migrate       # creates the dev database if missing and applies migrations
npm run dev              # http://localhost:3000
```

**Backend tests** drive the real HTTP API with supertest against the Postgres database in `TEST_DATABASE_URL`, using a fake OTP verifier and a controllable clock. `npm test` applies migrations to that database first. The tests truncate it, so never point it at data you care about.

```sh
npm test
```

### E2E mode

```sh
npm run start:e2e
```

This sets `E2E_MODE=true`, which:

- replaces Twilio Verify with a fake that accepts only `E2E_OTP_CODE` (default `000000`);
- mounts test-only endpoints: `POST /__e2e__/reset` empties the database, and `POST /__e2e__/faults` with `{ method, path, count }` makes the next `count` calls to that endpoint fail with 503.

The server refuses to start in e2e mode when `NODE_ENV=production`.

### Flutter e2e suite

The Flutter client is tested end to end: `mobile/integration_test/` runs the real `ConvozeApp` on an emulator or simulator against the backend in e2e mode, and resets the backend before each test. With the backend running via `npm run start:e2e`:

```sh
cd mobile
# iOS simulator
flutter test integration_test
# Android emulator (the emulator reaches the host at 10.0.2.2)
flutter test integration_test --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Pick a device with `-d <device-id>` if more than one is connected.
