import 'dart:async';

import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/auth/presentation/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/gated_token_store.dart';

ProviderContainer _container({TokenStore? tokenStore}) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(
        tokenStore ?? TokenStore(const FlutterSecureStorage()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Reads the auth state once, then waits for it to leave [Restoring].
Future<AuthStatus> _restored(ProviderContainer container) async {
  final settled = Completer<AuthStatus>();
  final sub = container.listen(authStateProvider, (_, next) {
    if (next is! Restoring && !settled.isCompleted) settled.complete(next);
  }, fireImmediately: true);
  addTearDown(sub.close);
  return settled.future;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts out restoring on a cold start', () {
    final container = _container(tokenStore: GatedTokenStore());

    expect(container.read(authStateProvider), isA<Restoring>());
  });

  test('becomes authenticated when a refresh token is stored', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'access',
      'refresh_token': 'session.secret',
    });

    expect(await _restored(_container()), isA<Authenticated>());
  });

  test('becomes unauthenticated when no tokens are stored', () async {
    expect(await _restored(_container()), isA<Unauthenticated>());
  });

  test('becomes unauthenticated when stored tokens cannot be read', () async {
    final tokenStore = GatedTokenStore();
    final container = _container(tokenStore: tokenStore);
    final restored = _restored(container);

    tokenStore.refreshTokenRead.completeError(
      StateError('keystore unavailable'),
    );

    expect(await restored, isA<Unauthenticated>());
  });

  test('a sign-out while restoring is not undone by the restore', () async {
    final tokenStore = GatedTokenStore();
    final container = _container(tokenStore: tokenStore);
    container.read(authStateProvider);

    await container.read(authStateProvider.notifier).signOut();
    tokenStore.refreshTokenRead.complete('session.secret');
    await pumpEventQueue();

    expect(container.read(authStateProvider), isA<Unauthenticated>());
  });
}
