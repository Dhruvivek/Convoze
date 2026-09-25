import 'dart:convert';

import 'package:convoze/app.dart';
import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'e2e.dart';
import 'other_device.dart' show sessionIdOf;

/// Signs in as the seeded `+14155550100` Alice, ending on the conversations
/// screen.
Future<void> signIn(WidgetTester tester) async {
  await tester.enterText(find.byKey(PhoneEntryScreen.countryCodeFieldKey), '1');
  await tester.enterText(
    find.byKey(PhoneEntryScreen.numberFieldKey),
    '415 555 0100',
  );
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(OtpEntryScreen.codeFieldKey), e2eOtpCode);
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
  expect(find.text('Conversations'), findsOneWidget);
}

/// The app's [ConnectionManager], reached through its live provider tree.
ConnectionManager connection(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(connectionManagerProvider);

/// Pumps until [condition] holds, failing after [timeout].
Future<void> pumpUntil(
  WidgetTester tester,
  Future<bool> Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting: $reason');
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> untilStatus(
  WidgetTester tester,
  ConnectionStatus status, {
  Duration timeout = const Duration(seconds: 10),
}) => pumpUntil(
  tester,
  () async => connection(tester).status == status,
  reason: 'connection status $status',
  timeout: timeout,
);

/// The Session ID of the currently signed-in Device.
Future<String> currentSessionId() async => sessionIdOf(
  (await const FlutterSecureStorage().read(key: 'access_token'))!,
);

/// The id of the currently signed-in User.
Future<String> currentUserId() async {
  final json = (await const FlutterSecureStorage().read(key: 'user'))!;
  return (jsonDecode(json) as Map<String, dynamic>)['id'] as String;
}

/// The app's local replica (#51), reached through its live provider tree —
/// so a test can assert directly against what the sync engine has applied.
AppDatabase replica(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(appDatabaseProvider);
