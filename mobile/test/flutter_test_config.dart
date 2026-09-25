import 'dart:async';

import 'package:drift/drift.dart';

/// Widget tests that sign in construct their own isolated in-memory
/// [AppDatabase] (#51) per test — many instances over a run by design, not
/// the accidental-reuse bug drift's warning looks for. Suppressing it here,
/// once, is what drift's own warning message suggests for this case.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  await testMain();
}
