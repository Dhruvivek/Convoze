import 'package:convoze/app.dart';
import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/realtime/socket_factory.dart';
import 'package:convoze/core/router/splash_screen.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_socket_factory.dart';
import '../../support/gated_token_store.dart';

/// Cold-starts the real app over a gated TokenStore and shows its first frame.
Future<GatedTokenStore> _launch(WidgetTester tester) async {
  final tokenStore = GatedTokenStore();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokenStore),
        socketFactoryProvider.overrideWithValue(fakeSocketFactory()),
        // In memory: a widget test signing in triggers a real connect(),
        // which attaches the sync engine (#51) — never touch real disk here.
        appDatabaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
      ],
      child: const ConvozeApp(),
    ),
  );
  await tester.pump();
  return tokenStore;
}

final _login = find.text('Sign in');
final _home = find.descendant(of: find.byType(AppBar), matching: find.text('Convoze'));
final _splash = find.byType(SplashScreen);

/// The Chats tab holds a live drift stream (#52). A test that ends with the
/// signed-in app still mounted must unmount it (and pump once more) itself,
/// so its debounced stream-close timer (drift: `StreamQueryStore
/// .markAsClosed`) fires inside this test's fake-async zone rather than
/// tripping flutter_test's "pending timer" check — drift's own guidance for
/// exactly this.
Future<void> _disposeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

void main() {
  // The gated store holds back the refresh token; the rest of a Session is
  // stored as usual.
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"u1","phoneNumber":"+14155554821","displayName":null}',
    }),
  );

  testWidgets('shows the splash screen, not login, while restoring', (
    tester,
  ) async {
    await _launch(tester);

    expect(_splash, findsOneWidget);
    expect(_login, findsNothing);
    expect(_home, findsNothing);
  });

  testWidgets('goes from splash straight to conversations when signed in', (
    tester,
  ) async {
    final tokenStore = await _launch(tester);

    tokenStore.refreshTokenRead.complete('session.secret');
    await tester.pumpAndSettle();

    expect(_home, findsOneWidget);
    expect(_splash, findsNothing);
    expect(_login, findsNothing);
    await _disposeApp(tester);
  });

  testWidgets('goes from splash to login when nothing is stored', (
    tester,
  ) async {
    final tokenStore = await _launch(tester);

    tokenStore.refreshTokenRead.complete(null);
    await tester.pumpAndSettle();

    expect(_login, findsOneWidget);
    expect(_splash, findsNothing);
  });
}
