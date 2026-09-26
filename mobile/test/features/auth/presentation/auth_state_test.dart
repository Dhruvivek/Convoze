import 'dart:async';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/db/database_provider.dart';
import 'package:convoze/core/models/user.dart';
import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/auth/data/auth_failure.dart';
import 'package:convoze/features/auth/data/auth_repository.dart';
import 'package:convoze/features/auth/presentation/auth_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/gated_token_store.dart';

const _user = User(id: 'u1', phoneNumber: '+14155554821', displayName: null);

class _FakeAuthRepository implements AuthRepository {
  int logouts = 0;

  /// When set, logout throws it.
  Object? logoutError;

  @override
  Future<void> requestOtp(String phoneNumber) async {}

  @override
  Future<SignInResult> verifyOtp(String phoneNumber, String code) async =>
      const SignInResult(
        accessToken: 'access',
        refreshToken: 'session.secret',
        user: _user,
      );

  @override
  Future<void> logout() async {
    logouts++;
    if (logoutError case final error?) throw error;
  }

  @override
  Future<void> logoutOthers() async {}
}

ProviderContainer _container({
  TokenStore? tokenStore,
  AuthRepository? repository,
}) {
  final container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(
        tokenStore ?? TokenStore(const FlutterSecureStorage()),
      ),
      authRepositoryProvider.overrideWithValue(
        repository ?? _FakeAuthRepository(),
      ),
      // In memory: signOut() wipes the replica (#54) — never touch real
      // disk here.
      appDatabaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
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

const _signedInStorage = {
  'access_token': 'access',
  'refresh_token': 'session.secret',
  'user': '{"id":"u1","phoneNumber":"+14155554821","displayName":null}',
  'device_id': 'device-1',
};

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test('starts out restoring on a cold start', () {
    final container = _container(tokenStore: GatedTokenStore());

    expect(container.read(authStateProvider), isA<Restoring>());
  });

  test('restores the signed-in User when a Session is stored', () async {
    FlutterSecureStorage.setMockInitialValues({..._signedInStorage});

    final restored = await _restored(_container());

    expect(restored, isA<Authenticated>());
    expect((restored as Authenticated).user.phoneNumber, '+14155554821');
  });

  test('becomes unauthenticated when no tokens are stored', () async {
    expect(await _restored(_container()), isA<Unauthenticated>());
  });

  test('forgets tokens stored without a User', () async {
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'access',
      'refresh_token': 'session.secret',
      'device_id': 'device-1',
    });

    expect(await _restored(_container()), isA<Unauthenticated>());
    expect(await const FlutterSecureStorage().readAll(), {
      'device_id': 'device-1',
    });
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

  test('signing in keeps the User for the next cold start', () async {
    final container = _container();
    await _restored(container);

    await container
        .read(authStateProvider.notifier)
        .verifyOtp('+14155554821', '000000');

    final signedIn = container.read(authStateProvider);
    expect((signedIn as Authenticated).user.id, 'u1');
    expect(await _restored(_container()), isA<Authenticated>());
  });

  group('signing out', () {
    Future<Map<String, String>> storage() =>
        const FlutterSecureStorage().readAll();

    test('ends the Session on the server and forgets it here', () async {
      FlutterSecureStorage.setMockInitialValues({..._signedInStorage});
      final repository = _FakeAuthRepository();
      final container = _container(repository: repository);
      await _restored(container);

      await container.read(authStateProvider.notifier).signOut();

      expect(repository.logouts, 1);
      expect(container.read(authStateProvider), isA<Unauthenticated>());
      expect(await storage(), {'device_id': 'device-1'});
    });

    test('a second tap while logging out does not log out again', () async {
      FlutterSecureStorage.setMockInitialValues({..._signedInStorage});
      final repository = _FakeAuthRepository();
      final container = _container(repository: repository);
      await _restored(container);
      final notifier = container.read(authStateProvider.notifier);

      await Future.wait([notifier.signOut(), notifier.signOut()]);

      expect(repository.logouts, 1);
    });

    for (final (reason, error) in [
      ('the server is unreachable', const AuthNetworkFailure()),
      ('the server fails', const UnexpectedAuthFailure()),
      ('something unexpected goes wrong', StateError('boom')),
    ]) {
      test('still forgets the Session when $reason', () async {
        FlutterSecureStorage.setMockInitialValues({..._signedInStorage});
        final repository = _FakeAuthRepository()..logoutError = error;
        final container = _container(repository: repository);
        await _restored(container);

        await container.read(authStateProvider.notifier).signOut();

        expect(container.read(authStateProvider), isA<Unauthenticated>());
        expect(await storage(), {'device_id': 'device-1'});
      });
    }
  });
}
