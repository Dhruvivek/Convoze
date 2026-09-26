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

Outside e2e mode the server sends real SMS codes through Twilio Verify, so it needs `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` and `TWILIO_VERIFY_SERVICE_SID` (see `.env.example`), and refuses to start without them.

**Backend tests** drive the real HTTP API with supertest, and the realtime Socket.IO server with real `socket.io-client` connections to a server on a random port, against the Postgres database in `TEST_DATABASE_URL`, using a fake OTP verifier and a controllable clock. `npm test` applies migrations to that database first. The tests truncate it, so never point it at data you care about.

```sh
npm test
```

### E2E mode

```sh
npm run start:e2e
```

This sets `E2E_MODE=true`, which:

- replaces Twilio Verify with a fake that accepts only `E2E_OTP_CODE` (default `000000`);
- mounts test-only endpoints: `POST /__e2e__/reset` empties the database, and `POST /__e2e__/faults` with `{ method, path, count, status?, code? }` makes the next `count` calls to that endpoint fail with that status and error code (503 `fault_injected` by default; e.g. 502 `otp_provider_unavailable` stands in for an SMS provider outage).
- mounts test-only auth endpoints: `POST /__e2e__/token-ttls` with `{ accessTokenSeconds?, refreshTokenSeconds? }` shortens token lifetimes until the next reset; `GET /__e2e__/echo` sits behind the real auth middleware and answers `{ userId, sessionId }`; `GET /__e2e__/sessions/:sessionId/refresh-count` answers `{ count }` of `POST /auth/refresh` calls made for that Session.
- mounts test-only realtime endpoints: `POST /__e2e__/conversations` with `{ type: "direct" | "group", name?, participantPhoneNumbers }` seeds a Conversation, creating any Users that don't exist yet, joins any already-connected participant's live sockets to its room right away, and answers `{ id, type, participants: [{ userId, phoneNumber }] }`; `POST /__e2e__/conversations/:conversationId/messages/seed` with `{ count, senderId }` fast-fills that Conversation with `count` Messages from `senderId`, bypassing the Update log (used to seed a long history for pagination tests, #55); `DELETE /__e2e__/conversations/:conversationId/participants/:userId` removes that Participant, taking any of their live sockets out of the room right away; `POST /__e2e__/emit` with `{ room, payload? }` sends an `e2e:test` event to a room (`conversation:<id>` or `user:<id>`); `GET /__e2e__/sessions/:sessionId/sockets` answers `{ count }` of live sockets the server holds for that Session. `POST /__e2e__/reset` also closes every live socket.

The server refuses to start in e2e mode when `NODE_ENV=production`.

### Flutter e2e suite

The Flutter client is tested end to end: `mobile/integration_test/` runs the real `ConvozeApp` on an emulator or simulator against the backend in e2e mode, and resets the backend before each test. With the backend running via `npm run start:e2e`:

```sh
cd mobile
# iOS simulator
flutter test integration_test
# Android emulator (the emulator reaches the host at 10.0.2.2)
flutter test integration_test --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=SOCKET_URL=http://10.0.2.2:3000
```

Pick a device with `-d <device-id>` if more than one is connected.
