import 'package:convoze/app.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/features/auth/presentation/otp_entry_screen.dart';
import 'package:convoze/features/auth/presentation/phone_entry_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';

const _alice = '+14155550100';
const _bob = '+14155550101';

Future<void> _signIn(WidgetTester tester) async {
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

ConnectionManager _connection(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(connectionManagerProvider);

/// Pumps until [condition] holds, failing after [timeout].
Future<void> _pumpUntil(
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

Future<void> _untilStatus(WidgetTester tester, ConnectionStatus status) =>
    _pumpUntil(
      tester,
      () async => _connection(tester).status == status,
      reason: 'connection status $status',
    );

Future<String> _sessionId() async => sessionIdOf(
  (await const FlutterSecureStorage().read(key: 'access_token'))!,
);

void main() {
  setUpE2e();

  final others = <OtherDevice>[];
  tearDown(() {
    for (final other in others) {
      other.dispose();
    }
    others.clear();
  });

  testWidgets('after sign-in the app connects', (tester) async {
    await launchApp(tester);
    expect(_connection(tester).status, ConnectionStatus.offline);

    await _signIn(tester);

    await _untilStatus(tester, ConnectionStatus.connected);
    expect(await backend.socketCount(await _sessionId()), 1);
  });

  testWidgets("an event sent to one of the user's Conversations reaches the "
      'app', (tester) async {
    final conversationId = await backend.seedConversation([_alice, _bob]);
    final bob = await OtherDevice.signIn(_bob);
    others.add(bob);
    final bobSocket = await bob.connectSocket();
    await launchApp(tester);
    await _signIn(tester);
    await _untilStatus(tester, ConnectionStatus.connected);

    final appReceived = nextEvent(_connection(tester).socket!, 'e2e:test');
    final bobReceived = nextEvent(bobSocket, 'e2e:test');
    await backend.emitTestEvent('conversation:$conversationId', {'n': 1});

    expect(await appReceived, {'n': 1});
    expect(await bobReceived, {'n': 1});
  });

  testWidgets('logging out disconnects the app', (tester) async {
    await launchApp(tester);
    await _signIn(tester);
    await _untilStatus(tester, ConnectionStatus.connected);
    final sessionId = await _sessionId();

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(_connection(tester).status, ConnectionStatus.offline);
    expect(_connection(tester).socket, isNull);
    await _pumpUntil(
      tester,
      () async => await backend.socketCount(sessionId) == 0,
      reason: 'the server to drop the socket',
    );
  });
}
