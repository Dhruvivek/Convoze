import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:convoze/core/network/session_refresher.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/conversations/presentation/message_action.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_jwt.dart';
import '../../../support/fake_socket_factory.dart';

/// A [ConnectionManager] a test can put straight into [ConnectionStatus]
/// [connected] (via [fakeSocketFactory]'s socket, which connects on its own
/// next microtask) or leave at its default, [ConnectionStatus.offline] —
/// without the full signed-in app cold-start `conversations_screen_test.dart`
/// uses, since [ensureConnected] only ever reads `.status`.
ConnectionManager _manager() {
  final tokenStore = TokenStore(const FlutterSecureStorage());
  return ConnectionManager(
    createSocket: fakeSocketFactory(),
    tokenStore: tokenStore,
    sessionRefresher: SessionRefresher(
      refreshDio: Dio(),
      tokenStore: tokenStore,
      onSessionEnded: () {},
    ),
    onSessionEnded: () {},
    readSyncCursor: () async => null,
    onSocketCreated: (_) {},
    isOutboxEmpty: () async => true,
  );
}

Future<bool?> _pumpAndTapEnsureConnected(WidgetTester tester, ConnectionManager manager) async {
  bool? result;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [connectionManagerProvider.overrideWith((ref) => manager)],
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => ElevatedButton(
              onPressed: () => result = ensureConnected(context, ref),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  return result;
}

void main() {
  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('ensureConnected refuses with a snackbar while offline', (tester) async {
    final result = await _pumpAndTapEnsureConnected(tester, _manager());

    expect(result, isFalse);
    expect(find.text('Needs a connection'), findsOneWidget);
  });

  testWidgets('ensureConnected proceeds silently once connected', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': fakeJwt(secondsFromNow: 3600),
      'refresh_token': 'refresh-1',
    });
    final manager = _manager();
    await manager.connect();

    final result = await _pumpAndTapEnsureConnected(tester, manager);

    expect(result, isTrue);
    expect(find.text('Needs a connection'), findsNothing);
  });
}
