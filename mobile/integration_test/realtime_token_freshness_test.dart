import 'package:convoze/app.dart';
import 'package:convoze/core/network/dio_provider.dart';
import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/realtime_helpers.dart';

// Covers #32: the realtime connection keeps its access token fresh across
// (re)connects, sharing #25's single-flight Dio refresh and #20's sign-out
// path. token_refresh_test.dart covers the same refresh for plain HTTP
// calls; this file is about the socket.

const _storage = FlutterSecureStorage();

/// The app's own API client, so a call goes through its auth interceptor.
Dio _api(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(ConvozeApp)))
        .read(dioProvider);

Future<Response<Map<String, dynamic>>> _echo(WidgetTester tester) =>
    _api(tester).get<Map<String, dynamic>>('/__e2e__/echo');

/// Backgrounds the app and waits for its socket to actually leave the server,
/// as a real background would eventually get the transport killed.
Future<void> _backgroundUntilDropped(
  WidgetTester tester,
  String sessionId,
) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await pumpUntil(
    tester,
    () async => await backend.socketCount(sessionId) == 0,
    reason: 'the server to drop the backgrounded socket',
  );
}

Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

void main() {
  setUpE2e();

  testWidgets(
    'backgrounding past the access token TTL refreshes before reconnecting '
    'on foreground, and the connection succeeds',
    (tester) async {
      await backend.setTokenTtls(accessTokenSeconds: 1);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();

      await _backgroundUntilDropped(tester, sessionId);
      await _wait(const Duration(seconds: 2));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await untilStatus(tester, ConnectionStatus.connected);

      expect(await backend.refreshCount(sessionId), 1);
      expect(await backend.socketCount(sessionId), 1);
    },
  );

  testWidgets(
    'a reconnect and a concurrent HTTP 401 after expiry share one refresh',
    (tester) async {
      await backend.setTokenTtls(accessTokenSeconds: 1);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();

      await _backgroundUntilDropped(tester, sessionId);
      await _wait(const Duration(seconds: 2));

      // Both the interceptor and the connection manager see the same expired
      // token at nearly the same moment and race to refresh it.
      final echo = _echo(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await echo;
      await untilStatus(tester, ConnectionStatus.connected);

      expect(await backend.refreshCount(sessionId), 1);
    },
  );

  testWidgets(
    'once the refresh token has expired, reconnecting lands on login with '
    'the Device ID kept',
    (tester) async {
      await backend.setTokenTtls(accessTokenSeconds: 1, refreshTokenSeconds: 2);
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final sessionId = await currentSessionId();
      final deviceId = await _storage.read(key: 'device_id');

      await _backgroundUntilDropped(tester, sessionId);
      await _wait(const Duration(seconds: 3));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Sign in'), findsOneWidget);
      expect(await _storage.read(key: 'access_token'), isNull);
      expect(await _storage.read(key: 'refresh_token'), isNull);
      expect(await _storage.read(key: 'device_id'), deviceId);
    },
  );
}
