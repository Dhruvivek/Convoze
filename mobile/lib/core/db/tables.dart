import 'package:drift/drift.dart';

/// The local `users` side-list (ADR 0009): every batch, snapshot page and
/// message page carries the *current* profile of every User it refers to,
/// and this table is just the upsert target. No profile Update kind exists;
/// a profile only refreshes when it's referred to again.
///
/// `@DataClassName('LocalUser')`: drift would otherwise name the generated
/// row class `User`, colliding with `core/models/user.dart`'s `User`.
@DataClassName('LocalUser')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get phoneNumber => text()();
  TextColumn get displayName => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors the server's Conversation row plus this Device's own view of it
/// (`unreadCount`, `left`) — both carried on every hydration, never derived
/// locally (ADR 0009: deriving `unreadCount` locally undercounts after a
/// reset).
class Conversations extends Table {
  TextColumn get id => text()();

  /// `'direct'` or `'group'`.
  TextColumn get type => text()();
  TextColumn get name => text().nullable()();
  TextColumn get createdById => text().nullable()();

  /// Null when this row came from `GET /conversations` (#50's list payload
  /// doesn't carry it) rather than a live `conversation.joined` Update
  /// (which does); nothing reads it, so this is harmless.
  DateTimeColumn get createdAt => dateTime().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// Set once this User's Participant row carries a `leftAt` (ADR 0009: a
  /// left Conversation stays, read-only, rather than disappearing).
  BoolColumn get left => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Membership plus both watermarks (`CONTEXT.md`; ADR 0008), one row per
/// (conversation, user) — including rows for other Participants, needed to
/// compute "delivered to N" / "seen by N" locally.
class Participants extends Table {
  TextColumn get conversationId => text()();
  TextColumn get userId => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  TextColumn get lastReadMessageId => text().nullable()();
  TextColumn get lastDeliveredMessageId => text().nullable()();
  DateTimeColumn get leftAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {conversationId, userId};
}

/// Mirrors `messagePayload()`'s wire shape (`backend/src/messaging/messagePayload.js`).
/// `reactions` and `linkPreview` are stored as JSON text (drift has no native
/// JSON column on sqlite) — small, read-mostly, and never queried by field,
/// so this is simpler than a side table. A message's "reply preview" isn't a
/// stored column: the server never sends one, only `replyToMessageId`, so a
/// reply preview is a self-join read at query time.
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();

  /// The id this Message was sent under from this Device (or another of this
  /// User's Devices), used to dedupe against a confirming `message.new`
  /// against an Outbox row. Null for a Message from someone else.
  TextColumn get clientMsgId => text().nullable()();
  TextColumn get replyToMessageId => text().nullable()();

  /// JSON `{url, title, description}` or null.
  TextColumn get linkPreview => text().nullable()();
  TextColumn get type => text().withDefault(const Constant('text'))();
  TextColumn get content => text().nullable()();

  /// JSON `[{userId, emoji}]` — the current list, not a diff (mirrors
  /// `reaction.changed`'s hydration).
  TextColumn get reactions => text().withDefault(const Constant('[]'))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get editedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Single row (`id = 0`): the Device-held Sync cursor (ADR 0008) — the
/// highest `seq` durably applied. No row (rather than a `cursor: 0` row)
/// means "send no `since`", which is also what a schema-version bump leaves
/// behind (`AppDatabase.migration` drops this table along with every other
/// rebuildable one): the server then reads `since` as missing and emits
/// `sync:reset`, reusing the exact same REST-rebuild path a retention gap
/// uses, rather than a second "rebuild on schema bump" code path.
class SyncState extends Table {
  IntColumn get id => integer().withDefault(const Constant(0))();
  IntColumn get cursor => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// At most one row per Conversation (ADR 0009: "only the latest"): the read
/// watermark move waiting to be sent as `conversation:read` on reconnect. A
/// newer read replaces the row rather than queuing another one.
class PendingReads extends Table {
  TextColumn get conversationId => text()();
  TextColumn get messageId => text()();

  @override
  Set<Column> get primaryKey => {conversationId};
}

/// The one table `sync:reset` and a schema bump never wipe (ADR 0009): every
/// other table is a rebuildable copy of server state, this is the only
/// server doesn't have yet. Keyed by `clientMsgId`, which is also the id a
/// pending Message row uses locally until the real one arrives.
class Outbox extends Table {
  TextColumn get clientMsgId => text()();
  TextColumn get conversationId => text()();
  TextColumn get content => text()();
  TextColumn get replyToMessageId => text().nullable()();

  /// JSON `{url, title, description}` or null.
  TextColumn get linkPreview => text().nullable()();

  /// `'pending'` (queued or awaiting ack), `'sending'` (ack in flight) or
  /// `'failed'` ("tap to retry or delete", ADR 0009). `RATE_LIMITED` retries
  /// in place rather than moving to `'failed'`.
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {clientMsgId};
}
