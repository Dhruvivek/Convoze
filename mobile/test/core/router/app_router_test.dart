import 'package:convoze/app.dart';
import 'package:convoze/core/realtime/socket_factory.dart';
import 'package:convoze/core/router/splash_screen.dart';
import 'package:convoze/core/storage/token_store.dart';
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
      ],
      child: const ConvozeApp(),
    ),
  );
  await tester.pump();
  return tokenStore;
}

final _login = find.text('Sign in');
final _conversations = find.text('Conversations');
final _splash = find.byType(SplashScreen);

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
    expect(_conversations, findsNothing);
  });

  testWidgets('goes from splash straight to conversations when signed in', (
    tester,
  ) async {
    final tokenStore = await _launch(tester);

    tokenStore.refreshTokenRead.complete('session.secret');
    await tester.pumpAndSettle();

    expect(_conversations, findsOneWidget);
    expect(_splash, findsNothing);
    expect(_login, findsNothing);
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
