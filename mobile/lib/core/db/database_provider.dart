import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'database.dart';

part 'database_provider.g.dart';

/// The app's one local replica (ADR 0009: "opened only through one
/// `openReplica()`"). Kept alive for the app's lifetime, like
/// `connectionManagerProvider`.
@Riverpod(keepAlive: true)
AppDatabase appDatabase(Ref ref) {
  final db = openReplica();
  ref.onDispose(db.close);
  return db;
}
