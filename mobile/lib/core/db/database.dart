import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_exclusion.dart';
import 'tables.dart';

part 'database.g.dart';

const _dbFileName = 'convoze_replica';

/// Every table this bumps drops and recreates, except [Outbox] — the one
/// table that isn't a rebuildable copy of server state (ADR 0009).
List<TableInfo> _rebuildableTables(AppDatabase db) => [
  db.users,
  db.conversations,
  db.participants,
  db.messages,
  db.syncState,
  db.pendingReads,
];

@DriftDatabase(
  tables: [Users, Conversations, Participants, Messages, SyncState, PendingReads, Outbox],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump this when a table's definition changes; [migration] wipes and
  /// rebuilds everything except the Outbox, same as `sync:reset` (ADR 0009).
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      for (final table in _rebuildableTables(this)) {
        await m.deleteTable(table.actualTableName);
        await m.createTable(table);
      }
      // The Outbox itself survives every bump (it's the one table that
      // isn't rebuildable server state), so a column it gains has to be
      // added in place rather than recreated with the rest above.
      if (from < 3) {
        await m.addColumn(outbox, outbox.type);
        await m.addColumn(outbox, outbox.media);
      }
    },
  );

  /// Clears every table except the Outbox: `sync:reset`'s wipe path (ADR
  /// 0009). Dropping the [SyncState] row along with it means the next
  /// connect sends no `since`, which is exactly what should happen while a
  /// rebuild is in flight.
  Future<void> wipeExceptOutbox() {
    return transaction(() async {
      await delete(users).go();
      await delete(conversations).go();
      await delete(participants).go();
      await delete(messages).go();
      await delete(syncState).go();
      await delete(pendingReads).go();
    });
  }

  /// Logout's wipe path (#54, ADR 0009: "logout then wipes everything, the
  /// Outbox included") — the one time the Outbox itself is dropped, since
  /// this Device is giving up its Session and any Message it never managed
  /// to send is gone with it.
  Future<void> wipeAll() {
    return transaction(() async {
      await wipeExceptOutbox();
      await delete(outbox).go();
    });
  }

  /// How many Messages this Device has composed but not yet had confirmed or
  /// given up on — what the logout warning ("N unsent messages will be
  /// lost") counts (#54).
  Future<int> outboxCount() async {
    final row = await (selectOnly(
      outbox,
    )..addColumns([outbox.clientMsgId.count()])).getSingle();
    return row.read(outbox.clientMsgId.count()) ?? 0;
  }

  /// The stored Sync cursor, or null if there isn't one (a fresh install, or
  /// right after a wipe) — sent as `since` in the socket handshake.
  Future<int?> readCursor() async {
    final row = await (select(syncState)..where((t) => t.id.equals(0))).getSingleOrNull();
    return row?.cursor;
  }

  /// Advances the stored cursor. Called only after a batch's transaction has
  /// committed (ADR 0008: ack only after apply), so a crash mid-batch never
  /// leaves the cursor ahead of what's actually on disk.
  Future<void> writeCursor(int seq) {
    return into(syncState)
        .insertOnConflictUpdate(SyncStateCompanion.insert(id: const Value(0), cursor: seq));
  }
}

/// Opens the single replica database (ADR 0009: "opened only through one
/// `openReplica()`"), on native sqlite via `drift_flutter`, in the app's
/// support directory (never Documents, which is user-visible via the Files
/// app on iOS), and excluded from the iCloud/Android backup since it's fully
/// rebuildable.
AppDatabase openReplica() {
  return AppDatabase(
    driftDatabase(
      name: _dbFileName,
      native: DriftNativeOptions(
        databasePath: () async {
          final dir = await getApplicationSupportDirectory();
          final path = p.join(dir.path, '$_dbFileName.sqlite');
          unawaited(excludeFromBackup(path));
          return path;
        },
      ),
    ),
  );
}
