import 'dart:io';

import 'package:flutter/services.dart';

const _channel = MethodChannel('convoze/db_backup');

/// Excludes the replica's sqlite file (and its `-wal`/`-shm` journal
/// siblings, best-effort — they may not exist yet) from the iCloud backup:
/// ADR 0009 says it's fully rebuildable, so a restore should resync rather
/// than restore a stale copy. Android's exclusion is declared in
/// `AndroidManifest.xml`/`res/xml/backup_rules.xml` instead, so this is a
/// no-op there. Best-effort everywhere: a failure here is never a reason to
/// fail startup, only a future backup that includes the file.
Future<void> excludeFromBackup(String sqliteFilePath) async {
  if (!Platform.isIOS && !Platform.isMacOS) return;
  for (final suffix in const ['', '-wal', '-shm']) {
    try {
      await _channel.invokeMethod<void>('excludeFromBackup', {
        'path': '$sqliteFilePath$suffix',
      });
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }
}
