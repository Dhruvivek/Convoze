# Postgres schema & ORM

**Status:** accepted — amended by [ADR 0008](0008-message-delivery-pipeline-update-log-and-sync-cursor.md) (delivered state reinstated as a Delivery watermark); amended by [ADR 0009](0009-local-first-client-data-layer.md) (Conversation preferences columns on `Participant`); amended by [ADR 0005](0005-realtime-transport-and-flutter-socket-integration.md) (`User.lastSeenAt`, #34)

## Context

`docs/features.md` sketched a draft data model (`User`, `Conversation`, `Participant`, `Message`, `Reaction`, `Block`, `Report`) and left the ORM/query-layer choice open. ADR 0002 (media storage) and ADR 0003 (OTP auth & sessions) have since extended `Message` and redefined `User`, and added `Session`/`otp_requests`. Issue #5 (part of the build-ready spec map in #1) finalizes the ORM, closes two correctness gaps the draft left open — group-chat read state and duplicate direct conversations — and assembles the full schema.

## Decisions

- **Language: plain JavaScript, not TypeScript**, for the Node backend. A deliberate call — TS isn't known yet, and this build shouldn't create direct interview exposure on it.
- **ORM: Prisma.** Schema-first migrations and a generated client; still gives real autocomplete in plain JS via the generated `.d.ts` files, so plain JS doesn't forfeit Prisma's main advantage.
- **Read state: a per-participant watermark, not a per-message status.** `docs/features.md`'s draft `Message.status: sent|delivered|seen` is dropped — it's only coherent for 1:1 chat, not groups, where "seen" is inherently per-participant. Replaced with `Participant.lastReadMessageId` (nullable FK to `Message`), updated on `markAsRead`. "Seen by N" = count of participants whose watermark's message ID is `>=` the message in question. "Delivered" is dropped as a separate state entirely — a persisted message is delivered, since Socket.IO pushes it live to online participants and offline participants get it through the same history-fetch/pagination path. This mirrors real messenger architecture (`docs/research/messenger-architectures.md`: "read watermarks sync because they are server state") rather than the doc's own draft.
- **No push-notification table yet.** `Session.deviceId` (ADR 0003) is enough for #8 to later add a `DeviceToken` table without reworking this schema — not designed here, per issue #5's own instruction not to block on it.
- **Primary keys: UUIDv7 everywhere**, via Postgres's native `uuidv7()`. Rejected auto-increment integers (sequential/guessable) and UUIDv4 (opaque but not time-sortable, which would break the watermark's `id >=` comparison above). UUIDv7 is opaque like a UUID and sortable like an integer — both properties this schema actually needs.
- **Duplicate direct conversations: enforced by the database, not application logic.** `Conversation` gets a `directKey` column, populated only when `type = 'direct'`, computed as the two participants' user IDs sorted and concatenated (identical regardless of who initiated it), with a unique constraint. Closes a race condition a pure "check then create" application check wouldn't (two near-simultaneous requests both passing the check before either finishes creating).

## Schema

```
User
 ├─ id (uuidv7 pk), phoneNumber (unique), phoneVerifiedAt,
 │  displayName (nullable), avatarUrl (nullable), createdAt,
 │  lastSeenAt (nullable — #34: when this User's last live socket
 │  disconnected; "online" itself is derived from the live-connection
 │  registry, never stored)

Session
 ├─ id (uuidv7 pk), userId (fk User), deviceId, platform,
 │  refreshTokenHash, issuedAt, expiresAt, lastUsedAt, revokedAt (nullable)

otp_requests
 ├─ id (uuidv7 pk), phoneNumber, requestedAt
 │  [index: (phoneNumber, requestedAt)]

Conversation
 ├─ id (uuidv7 pk), type (direct | group), name (nullable, groups only),
 │  directKey (nullable, unique — direct only), createdAt

Participant
 ├─ id (uuidv7 pk), conversationId (fk Conversation), userId (fk User),
 │  role (admin | member), joinedAt,
 │  lastReadMessageId (nullable fk Message), lastDeliveredMessageId (nullable fk Message),
 │  leftAt (nullable),
 │  pinnedAt (nullable), archivedAt (nullable), mutedUntil (nullable),
 │  hiddenAt (nullable), historyClearedMessageId (nullable fk Message)
 │  — the last five are Conversation preferences (ADR 0009), visible only to
 │  this Participant

Message
 ├─ id (uuidv7 pk), conversationId (fk Conversation), senderId (fk User),
 │  content (nullable — required for type=text, optional caption otherwise),
 │  type (text | image | file — video deferred, #40's reduced scope),
 │  isDeleted, editedAt (nullable), createdAt,
 │  mediaPublicId (nullable), mediaResourceType (nullable, 'image' | 'raw'),
 │  mediaBytes (nullable), mediaWidth (nullable), mediaHeight (nullable),
 │  mediaFormat (nullable), mediaFileName (nullable)
 │  — never a stored URL: one is signed fresh at every read (#40)
 │  [index: (conversationId, createdAt)]

Reaction
 ├─ id (uuidv7 pk), messageId (fk Message), userId (fk User), emoji
 │  [unique: (messageId, userId, emoji)]

Block
 ├─ id (uuidv7 pk), blockerId (fk User), blockedId (fk User), createdAt
 │  [unique: (blockerId, blockedId)]

Report
 ├─ id (uuidv7 pk), reporterId (fk User), reportedUserId (fk User), reason, createdAt
```

## Consequences

- No endpoint or socket handler can report per-message delivered/seen status directly off `Message` anymore — read state is always read through `Participant.lastReadMessageId`, and any "seen by" UI is a count query over `Participant`, not a column read.
- Every new table follows the UUIDv7-primary-key convention; introducing an auto-increment or UUIDv4 table later would be an inconsistency worth questioning, not a neutral choice.
- Creating a direct conversation must always go through logic that computes and sets `directKey` — a direct conversation created without it bypasses the uniqueness guarantee entirely.
- Plain JavaScript means no compile-time type checking on Prisma queries — errors that TS would catch statically surface at runtime instead; this is an accepted tradeoff for interview-risk reasons (decision 1), not an oversight.
