# Local-first client data layer: drift Local replica, sync engine & Conversation preferences

**Status:** accepted

## Context

Issue #18 (part of the Signal study map, #10, and absorbing #7) decides how the Flutter client stores data locally. It covers the storage package, encryption at rest, how data flows in from the socket, where on-device search and chat list controls live, where cached participant profiles live, and how all of this fits ADR 0001's Riverpod + repository structure. ADR 0008 already fixed the server side: a per-user Update log, a Device-held Sync cursor, transactional batch apply before ack, and `sync:reset` rebuilding over REST. This ADR is the client half of that contract, plus the server changes it turned up.

Convoze is server-trusted (ADR 0007). Everything on the device except unsent messages can be rebuilt from the server, and that shapes most of the decisions below.

## Decisions

- **The UI reads only from the Local replica (`CONTEXT.md`).** Screens never read from the network. Socket and REST traffic write into the replica, and Riverpod providers watch replica queries. This is the SimpleX / TDLib / Element X shape (#14 research, P0-7).
- **Storage: drift (SQLite).** Queries can be watched as streams, which map directly onto `StreamProvider`. The chat list ("latest message + unread + prefs per conversation") is a join. Drift has typed migrations, and SQLCipher is a library swap away. Rejected Isar/ObjectBox (no joins, shaky upkeep) and Hive/sembast (key-value only).
- **Layout (extends ADR 0001):**
  - `lib/core/db/` holds the single drift database, with every table defined there.
  - `lib/core/sync/` holds the **sync engine**. It owns the socket's `sync:*` handlers, the transaction that applies each batch, the Sync cursor, reset/snapshot, pending reads, and the Outbox drainer.
  - Each feature's `data/` repositories expose drift watch streams plus commands (for example, `send()` inserts into the Outbox).
  - Rejected tables per feature with a per-feature "applier": a batch applies in one transaction across every table, so splitting it adds only indirection.
- **Encryption at rest: deferred.** The replica is protected by the OS sandbox and the phone's own disk encryption. The database is opened only through one `openReplica()`, so SQLCipher (random key in `flutter_secure_storage`) is a one-file change later. Because the replica can be thrown away, turning encryption on later is a wipe-and-resync (after the Outbox drains), not a data migration. **The database file is excluded from iCloud/Android auto-backup now**, since it can be rebuilt anyway.
- **Profiles: a local users table fed by a `users` side-list, with no profile Update kind.** Every `sync:batch`, snapshot page and message page carries the *current* profile of every user it refers to (Telegram's `users` vector), and the client upserts them. Opening a profile or chat-info screen refetches over REST. Rejected a `user.profile` Update fanned out to every co-participant (one avatar change writes hundreds of rows) and time-to-live refetching. Accepted cost: an avatar in a chat that has gone quiet stays stale until that user is referred to again.
- **Conversation preferences (`CONTEXT.md`) live on the server, per Participant, and never only on the device.** Local-only settings would be lost at logout (which wipes the replica), wouldn't sync across Devices, and couldn't filter push. A change is a `conversation.prefs` Update written **only to that user's own log**.
  - **Mute:** 8 hours, 1 week or always (`mutedUntil`, with a far-future sentinel for "always"). A muted conversation gets **no push**, and its unread count doesn't count toward the app badge (it still shows in the list).
  - **Pin:** at most 5 pinned conversations, which sort first by pin time.
  - **Archive:** a new message does **not** unarchive.
  - **Delete chat:** sets `hidden` plus a **history-cleared watermark** (a message id). For that user, messages at or before the watermark are filtered out, both by the server when hydrating and by the client when showing messages. A new message clears `hidden` but not the watermark. **Clear chat** sets only the watermark.
  - **Folders are out of scope.**
- **Search: server-only for messages.** The search UI calls a `SearchRepository` backed by REST (Postgres full-text search, feature 13), and shows "search needs a connection" when offline. A local index would be incomplete anyway, because the replica holds only the history that has been paged in. The chat list's name filter is a plain local query over conversations and users.
- **Outbox (`CONTEXT.md`): one serial, first-in first-out drainer across all conversations**, which runs only while the socket is connected. This keeps "I sent A, then B" true app-wide.
  - `RATE_LIMITED` retries with backoff. Any other error code marks the message **failed** ("tap to retry or delete").
  - For media, the Outbox row holds a local file path. Uploading to Cloudinary is a step in the Outbox before `message:send`, and it is redone after an app restart. The local file is deleted once the upload is acked.
  - Logout with a non-empty Outbox warns: "N unsent messages will be lost".
  - **Background grace, amending ADR 0005:** if the Outbox isn't empty when the app goes to the background, the disconnect is held until it drains, capped at about 20s (iOS `beginBackgroundTask`).
- **Other actions made offline.** Edit, delete and reaction need a connection: the controls are disabled while disconnected, and they use `emitWithAck` directly. **Read** moves the local read watermark at once, and the sync engine keeps **one pending read per conversation** (only the latest), sent as `conversation:read` on reconnect. Rejected turning the Outbox into a general queue of operations: queued edits and deletes can conflict, while a read is a value that only moves forward and merges safely.
- **Pending messages sort below every confirmed message**, in the order they were composed. On ack, a message takes its server timestamp and may move above a message from someone else that arrived meanwhile. This way every Device converges on the same order.
- **Unread count comes from the server.** Every hydration of a conversation (snapshot, `conversation.receipts`, `conversation.prefs`) includes *my* `unreadCount`, which the client stores. Between hydrations it adds 1 for each `message.new` from others. Deriving it locally undercounts after a reset, because only recent messages are local.
- **Reset and schema changes wipe everything except the Outbox.** On `sync:reset`, messages already in the replica may have been edited or deleted during the gap without the client learning of it. So the client drops every table except the Outbox and rebuilds. A local **schema version change does the same**: only the Outbox gets hand-written drift migrations. The result is an invariant: **each conversation's local history is always one unbroken run ending at the newest message.** Scrolling up only extends it backwards, so there is never a hole to track. Edits and deletes reach every Participant whatever the message's age, so this run stays current.
- **The snapshot is shallow (amends ADR 0008).** A reset or first login fetches the **paged conversation list only** (50 per page). Each row carries its last message, my `unreadCount`, my Conversation preferences, and the `users` side-list. A conversation's first page of messages is fetched when it's opened, or ahead of time for the top ~10 conversations. Rejected ADR 0008's "latest page per conversation", which costs one request per conversation before the app is usable.
- **Conversations the user has left stay, read-only.** After `conversation.left`, local history is kept with a "You're no longer a participant" banner. The server's conversation list **includes conversations the user has left** (flagged), so they survive a reset. Removing one is the server-side "Delete chat" above, never a local-only deletion that a reset would bring back.
- **Media bytes stay outside the database.** Downloaded media and thumbnails go into an LRU disk cache that can be evicted (`flutter_cache_manager`, about 500 MB). The database holds only attachment metadata.

## Consequences

- **Backend:** `Participant` gains the Conversation preferences columns (amending ADR 0004): `pinnedAt`, `archivedAt`, `mutedUntil`, `hiddenAt`, `historyClearedMessageId`. There's a new Update kind `conversation.prefs`, written to the owner's log only. Conversation hydration includes the caller's `unreadCount` and preferences. Message hydration and paging drop anything at or before the caller's history-cleared watermark. Every batch and REST page carries a `users` side-list. The conversation list includes conversations the user has left.
- **Push (amends ADR 0006/0008):** `buildPush()` is skipped for a recipient whose `mutedUntil` is in the future, which is the filter ADR 0008 anticipated.
- **ADR 0005's `lib/core/` scope grows:** the sync engine in `lib/core/sync/` owns the `sync:*` and send events centrally, instead of each feature repository parsing its own slice. Ephemeral events (typing, presence) stay in feature repositories as ADR 0005 describes.
- Only the Outbox table needs migration code and migration tests. A change to any other table's schema must bump the schema version, which triggers the wipe and rebuild.
- Logout, reset and schema changes all funnel through one "wipe everything except the Outbox" path (logout wipes the Outbox too, after the warning).
- Turning on encryption later means swapping in `sqlcipher_flutter_libs`, generating a key in secure storage, and doing one wipe and rebuild. No data migration is needed.
