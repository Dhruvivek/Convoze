# Signal: local storage & on-device search, and the Flutter equivalent

Issue: #14 (part of map #10). Informs: **Local-first client data layer**.
Researched 2026-09-17 against primary sources (Signal source on `main`, pub.dev, drift/sqlite3.dart docs, SQLite/SQLCipher docs).
Signal is AGPLv3: this note describes design choices only. It copies no code.

---

## 1. Encrypted local DB and key storage

### Android
- The DB runs on SQLCipher through `net.zetetic.database.sqlcipher.SQLiteOpenHelper`, with foreign keys turned on when it opens. — [SignalDatabase.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/SignalDatabase.kt)
- Cipher pragmas: `cipher_compatibility = 3`, `kdf_iter = 1`, `cipher_page_size = 4096`. KDF iterations are set to 1 because the key is already a random 32-byte secret, not a password. — [SqlCipherDatabaseHook.java](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/SqlCipherDatabaseHook.java)
- The DB secret is 32 bytes from `SecureRandom`. It is sealed with an Android Keystore key and the sealed blob goes into SharedPreferences. The plaintext is cached in memory after the first unseal. Older plaintext secrets get migrated to the sealed form. — [DatabaseSecretProvider.java](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/crypto/DatabaseSecretProvider.java)
- The Keystore key uses AES/GCM/NoPadding with the alias `SignalSecret`, in the `AndroidKeyStore` provider. It does not require user authentication. — [KeyStoreHelper.java](https://github.com/signalapp/Signal-Android/blob/main/core/util/src/main/java/org/signal/core/util/crypto/KeyStoreHelper.java)

### iOS
- The DB uses a GRDB `DatabasePool` over SQLCipher, in WAL mode. Pragmas are `PRAGMA key`, `cipher_plaintext_header_size = 32` and `checkpoint_fullfsync = ON`. The key is 48 bytes (256-bit key plus 128-bit salt), passed as an `x'…'` blob. It lives in the Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. — [GRDBDatabaseStorageAdapter.swift](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Storage/Database/GRDBDatabaseStorageAdapter.swift)
- Why the plaintext header: iOS only lets a background app keep its lock on a WAL database if it can recognize the SQLite/WAL header. — [SQLCipher API: cipher_plaintext_header_size](https://www.zetetic.net/sqlcipher/sqlcipher-api/)
- A raw `x'hex'` key skips PBKDF2, so the app is responsible for making the key strong. — [SQLCipher API: PRAGMA key](https://www.zetetic.net/sqlcipher/sqlcipher-api/)

### Desktop
- The DB uses `@signalapp/sqlcipher`, with a hex raw key (`key = "x'…'"`), `journal_mode = WAL`, `synchronous = FULL` and `foreign_keys = ON`. — [ts/sql/Server.node.ts](https://github.com/signalapp/Signal-Desktop/blob/main/ts/sql/Server.node.ts)
- The key is `randomBytes(32)` in hex. It is encrypted with Electron `safeStorage` and saved as `encryptedKey` in the user config. A legacy plaintext `key` is still accepted and gets migrated. — [app/main.main.ts](https://github.com/signalapp/Signal-Desktop/blob/main/app/main.main.ts)

**Pattern on all three clients:** the DB key is a random key, not a passphrase. The OS keystore holds it, or a keystore-sealed copy of it. The KDF is skipped or kept minimal.

## 2. Schema shape (Android as reference)
- About 50 table classes. The core ones are `ThreadTable`, `MessageTable`, `AttachmentTable`, `RecipientTable`, `GroupTable` and `ReactionTable`. Protocol state (`IdentityTable`, `SessionTable`, `SenderKeyTable`) lives in the same DB. — [SignalDatabase.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/SignalDatabase.kt)
- **thread** (one row per chat): `recipient_id`, `date`, `read`, `unread_count`, `unread_self_mention_count`, `snippet`, `snippet_type`, `pinned_order` (null means not pinned), `archived`, `meaningful_messages`, `active`, `last_seen`, `last_scrolled` and `expires_in`. These are denormalized summary columns so the chat list never has to aggregate over messages. — [ThreadTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/ThreadTable.kt)
- **message**: `thread_id`, `from_recipient_id`, `to_recipient_id`, `date_sent`, `date_received`, `date_server`, `type`, `body`, `read`, receipt flags, `remote_deleted`, `quote_id`, `original_message_id` / `latest_revision_id` (edit history) and `expires_in`. It has composite indexes starting with `thread_id` for counts and unread counts. — [MessageTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/MessageTable.kt)
- **attachment**: the row holds metadata (`message_id`, content type and so on). The file itself sits on disk in a `parts` directory, encrypted with a per-file random value (`data_random`). `data_hash_end` lets identical files share one data file. — [AttachmentTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/AttachmentTable.kt)

## 3. The local DB is the source of truth: write, notify, observe
- Writes that affect a chat also update the thread summary (`threads.update(threadId, …)`), then call `notifyConversationListeners(threadId)`. — [MessageTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/MessageTable.kt)
- Every table sends its notifications to a single `DatabaseObserver` singleton. — [DatabaseTable.java](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/DatabaseTable.java)
- `DatabaseObserver` fires only **after a transaction succeeds** (`runPostSuccessfulTransaction`). Notifications are deduplicated by key (for example `Conversation:<threadId>`) and delivered on a serial executor. Listeners are scoped: conversation list, one conversation, message inserts per thread, attachments and so on. They receive a "changed" signal, not data. — [DatabaseObserver.java](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/DatabaseObserver.java)
- `RxDatabaseObserver` turns those signals into `Flowable<Unit>` streams with `BackpressureStrategy.LATEST` and `replay(1).refCount()`. The UI re-queries when a signal arrives. — [RxDatabaseObserver.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/RxDatabaseObserver.kt)
- On iOS, the `DatabaseChangeObserver` plays this role, plus Darwin notifications for changes made by other processes such as the NSE. — [GRDBDatabaseStorageAdapter.swift](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Storage/Database/GRDBDatabaseStorageAdapter.swift)

**Takeaway:** network code never pushes data into the UI. It writes to the DB inside a transaction. After commit, a coarse "table/thread X changed" signal goes out and the UI re-reads.

## 4. Message search (SQLite FTS5)
- **Android** keeps an FTS5 external-content table `message_fts(body, thread_id UNINDEXED)` over the message table. Its tokenizer is `unicode61 categories 'L* N* Co Sc So'`, so currency symbols and emoji are searchable too. Insert, delete and update triggers keep it in sync. The query is split on spaces, each term is quoted with `"` escaped, and each gets a prefix `*` (`"hello"* "world"*`). Results are capped at 500. Joins are deferred until after the FTS filter. `snippet()` is deliberately not computed in SQL; the app builds the preview. — [SearchTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/SearchTable.kt)
- **Desktop** uses `messages_fts USING fts5(body, tokenize = 'signal_tokenizer')`. View-once messages and stories are left out of the index. — [migration 77](https://github.com/signalapp/Signal-Desktop/blob/main/ts/sql/migrations/77-signal-tokenizer.std.ts). Search tokenizes the query the same way and adds a prefix `*`. It collects matching rowids into a temp table first, then sorts and limits on indexed message columns. — [Server.node.ts](https://github.com/signalapp/Signal-Desktop/blob/main/ts/sql/Server.node.ts)
- `signal_tokenizer` is a Rust FTS5 tokenizer (AGPLv3). It segments words by Unicode rules, which covers CJK, removes diacritics and lowercases. — [Signal-FTS5-Extension](https://github.com/signalapp/Signal-FTS5-Extension)
- **iOS** uses `indexable_text_fts` over a separate `indexable_text` content table. The app indexes rows explicitly, with no triggers, and skips view-once messages, group story replies and past edit revisions. It also uses a prefix-`*` query, `SNIPPET(…, 15 tokens)`, `ORDER BY rank` and a `LIMIT`. — [FullTextSearchIndexer.swift](https://github.com/signalapp/Signal-iOS/blob/main/SignalServiceKit/Search/FullTextSearchIndexer.swift)
- **Limits, from the FTS5 docs:**
  - External-content tables only stay correct if triggers keep them in sync; the `'rebuild'` command repairs them.
  - `unicode61` does not split CJK text, which is why Signal ships its own tokenizer.
  - The `trigram` tokenizer allows substring matches but needs at least 3 characters.
  - `detail=column` or `detail=none` shrinks the index a lot (743 → 340 → 134 MiB in their example), at the cost of phrase and NEAR queries.
  - `prefix=` indexes speed up prefix queries.
  - `optimize` and `automerge` control index merging.
  — [sqlite.org/fts5.html](https://www.sqlite.org/fts5.html)

## 5. Chat list state: pin, archive, mute, folders
- Pin (`pinned_order`) and archive (`archived`) are **thread** columns. Mute is **not** stored on the thread; it is `mute_until` on the **recipient**. — [ThreadTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/ThreadTable.kt)
- Folders use a `chat_folder` table with `name`, `position` and filter flags (`show_unread`, `show_muted`, `show_individual`, `show_groups`), plus `folder_type` (ALL or CUSTOM), a UUID `chat_folder_id`, `storage_service_id`, `storage_service_proto` (keeps unknown fields) and a soft-delete `deleted_timestamp_ms`. A `chat_folder_membership(chat_folder_id, thread_id, membership_type INCLUDED|EXCLUDED)` table holds explicit members. The flags act as dynamic filters. — [ChatFolderTables.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/ChatFolderTables.kt)
- **Sync across devices goes through the Storage Service, not the message stream.**
  - The server holds a manifest with an increasing version number, plus encrypted records with immutable IDs. Changing a record means deleting its old ID and writing a new one.
  - The client diffs record IDs between local and remote. It fetches and merges the remote-only records inside a transaction, then uploads the local-only ones.
  - Records are encrypted with a `StorageKey`.
  - Record types include Contact, GroupV2, Account, Story Distribution List, Call Link, Chat Folder, Notification Profile and Sticker Pack.
  - The sync runs after local changes and to pull remote ones.
  — [StorageSyncJob.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/jobs/StorageSyncJob.kt)
- The thread table applies incoming sync updates through `applyStorageSyncUpdate()`. — [ThreadTable.kt](https://github.com/signalapp/Signal-Android/blob/main/app/src/main/java/org/thoughtcrime/securesms/database/ThreadTable.kt)

For Convoze, the server is trusted with plaintext and isn't end-to-end encrypted. The same split still helps: sync pin, archive, mute and folders as small per-user settings records with versions, separate from message traffic.

## 6. Flutter options (checked 2026-09-17)
| Option | Status | Notes |
|---|---|---|
| `drift` + `package:sqlite3` 3.x with the `source: sqlite3mc` hook | **Recommended by drift for new apps** | Set `PRAGMA key` in `NativeDatabase.createInBackground(setup:)`. Check the `cipher` pragma at runtime to confirm the encrypted build is bundled. `sqlcipher_flutter_libs` is no longer needed from drift 2.32.0. — [drift encryption docs](https://drift.simonbinder.eu/platforms/encryption/) |
| `sqlcipher_flutter_libs` | **Discontinued** (0.7.0+eol, does nothing) | Its page says to migrate to `package:sqlite3` 3.x. — [pub.dev](https://pub.dev/packages/sqlcipher_flutter_libs) |
| `package:sqlite3` hook sources | active | Sources: `sqlite3` (default), `sqlite3mc`, `sqlcipher`, `system` and others. Bundled builds compile in `SQLITE_ENABLE_FTS5`. The maintainers prefer sqlite3mc over their SQLCipher build because the SQLCipher build may lag on SQLite version and links OpenSSL. SQLite3MC and SQLCipher have their own licenses. — [hook.md](https://github.com/simolus3/sqlite3.dart/blob/main/sqlite3/doc/hook.md), [pub.dev/packages/sqlite3](https://pub.dev/packages/sqlite3) |
| SQLite3MultipleCiphers | — | Pick a scheme with `PRAGMA cipher`; `'sqlcipher'` plus `legacy` gives SQLCipher-compatible files. Set the key before any other SQL. `PRAGMA key` returns ok even when the key is wrong, so check with a read. Use `hexkey` for binary keys. — [SQLite3MC pragmas](https://utelle.github.io/SQLite3MultipleCiphers/docs/configuration/config_sql_pragmas/) |
| `sqflite_sqlcipher` 3.4.1 | active | A sqflite fork on SQLCipher 4 for Android, iOS and macOS. You pass `password` to `openDatabase`. There are no reactive queries and no codegen. — [pub.dev](https://pub.dev/packages/sqflite_sqlcipher) |
| `encrypted_drift` | legacy alternative | Older SQLCipher-based route mentioned in the drift docs. — [drift encryption docs](https://drift.simonbinder.eu/platforms/encryption/) |
| `flutter_secure_storage` 11.2.0 | active | Android (since v10): RSA-OAEP key cipher plus AES-GCM storage cipher, replacing the deprecated EncryptedSharedPreferences. iOS: Keychain with an `accessibility` option (`first_unlock`, …). Android Auto Backup can cause `InvalidKeyException` after a restore, so exclude its prefs from backup. — [pub.dev](https://pub.dev/packages/flutter_secure_storage) |

- **FTS5 in drift:** the bundled sqlite3 includes fts5. Declare FTS5 tables in `.drift` files (not possible in Dart) and enable `fts5` under `sqlite_modules` in build options. — [drift extensions](https://drift.simonbinder.eu/sql_api/extensions/). `.drift` files also support `CREATE TRIGGER` and named queries that generate `Selectable`s with `.watch()`. — [drift files](https://drift.simonbinder.eu/sql_api/drift_files/)
- **Reactivity in drift:**
  - `watch()` streams emit right away and re-run after any write made through drift to a table they depend on. The granularity is per table, so they fire more often than strictly needed.
  - Writes from outside drift are not detected unless you call `notifyUpdates` or `tableUpdates`.
  - Watched queries should stay cheap.
  — [drift streams](https://drift.simonbinder.eu/dart_api/streams/)
- This is the same shape as Signal's "commit, then signal, then re-query" model, with the plumbing done for you.

---

## Summary
- All three Signal clients keep a single SQLCipher DB with a **random raw key held in the OS keystore**: Keystore-sealed on Android, Keychain `AfterFirstUnlockThisDeviceOnly` on iOS, `safeStorage` on Desktop. KDF work is skipped because the key is not a password.
- Attachments are **encrypted files on disk**; the DB holds only their metadata.
- **The local DB is the source of truth.** Network and sync code write in transactions. After commit, deduplicated per-thread or per-list change signals go out, and the UI re-queries. A denormalized `thread` row (snippet, date, unread count, pin, archive) keeps the chat list cheap.
- **Search is FTS5 over message bodies:** an external-content table kept in sync by triggers (Android) or explicit indexing (iOS), quoted prefix queries, a result cap, and snippets built by the app or by `snippet()`. Android uses `unicode61` with emoji and currency categories added. Desktop uses a custom Rust tokenizer for CJK and diacritics.
- **Pin and archive are thread columns, mute is a recipient column, folders are their own tables.** They sync across devices through the versioned, encrypted **Storage Service**, not through messages.

## Recommended Flutter stack: "Local-first client data layer"
1. **`drift` + `package:sqlite3` 3.x with `hooks.user_defines.sqlite3.source: sqlite3mc`** for an encrypted DB with FTS5 built in. Open it with `NativeDatabase.createInBackground`. In `setup`, run `PRAGMA hexkey`/`key` first, then assert that the `cipher` pragma exists and that a test read works. Do **not** add `sqlcipher_flutter_libs`, which is discontinued. Keep `sqflite_sqlcipher` only as a fallback; it has no reactive queries or codegen, which fits ADR 0001's codegen style poorly.
2. **Key:** generate 32 random bytes on first launch and store them with **`flutter_secure_storage`**: Keychain `first_unlock_this_device` on iOS, the default ciphers on Android. Exclude its prefs from Android Auto Backup. If the key is lost, treat the local DB as a disposable cache and re-sync from the server, which is the source of truth for Convoze.
3. **Schema (drift tables, one feature-first `data/` layer):**
   - `conversations`: server id, denormalized `last_message_snippet`, `last_message_at`, `unread_count`, `pinned_order`, `archived_at`, `muted_until`
   - `messages`: server id plus a client-generated id for optimistic sends, `conversation_id`, `sender_id`, `body`, `status`, `sent_at`/`server_at`, `edited_of`, `deleted_at`
   - `attachments`: metadata plus a local file path
   - `folders` and `folder_members`
   - Add composite indexes on `(conversation_id, server_at)`.
4. **Data flow:** Socket.IO and REST handlers are writers only. They upsert into drift inside a transaction and update the conversation summary in the same transaction. Repositories expose drift `.watch()` streams, which Riverpod `@riverpod` Stream providers hand to widgets. The UI never reads socket payloads directly. Do all writes through drift so streams fire.
5. **Search:** a `.drift` file with `CREATE VIRTUAL TABLE message_fts USING fts5(body, content='messages', content_rowid='id', tokenize="unicode61 remove_diacritics 2")` plus insert, delete and update triggers. Enable `fts5` in `sqlite_modules`. Sanitize queries into quoted prefix terms, cap results (for example 500), order by `rank`, and use `snippet()` for previews. Consider `trigram` later if substring or CJK search matters.
6. **Chat list state:** keep pin, archive, mute and folders locally for instant UI. Sync them to the Node server as per-user settings rows with an `updated_at` or version, last-write-wins, pushed over Socket.IO to the user's other sessions. This is a lightweight stand-in for Signal's Storage Service.
