import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/backend_process.dart';
import 'support/e2e.dart';
import 'support/realtime_helpers.dart';

// Run this file on its own (`flutter test integration_test/realtime_backend_restart_test.dart`),
// not as part of a `flutter test integration_test/` sweep: it starts and
// restarts its own backend process on API_BASE_URL's port instead of
// assuming one is already running there (see support/backend_process.dart).

const _reconnectTimeout = Duration(seconds: 40);

void main() {
  setUpE2e();

  late BackendProcess backendProcess;
  setUpAll(() async => backendProcess = await BackendProcess.start());
  tearDownAll(() => backendProcess.stop());

  testWidgets('restarting the backend process reconnects the app', (
    tester,
  ) async {
    await launchApp(tester);
    await signIn(tester);
    await untilStatus(tester, ConnectionStatus.connected);
    final sessionId = await currentSessionId();

    await backendProcess.restart();

    await pumpUntil(
      tester,
      () async =>
          connection(tester).status == ConnectionStatus.connecting ||
          connection(tester).status == ConnectionStatus.reconnecting,
      reason: 'the app to notice the connection is gone',
      timeout: _reconnectTimeout,
    );
    expect(find.text('Connecting…'), findsOneWidget);

    await untilStatus(
      tester,
      ConnectionStatus.connected,
      timeout: _reconnectTimeout,
    );
    await tester.pump();
    expect(find.text('Connecting…'), findsNothing);
    expect(await backend.socketCount(sessionId), 1);
  });
}
