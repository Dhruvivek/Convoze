import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';

part 'auth_state.g.dart';

sealed class AuthStatus {
  const AuthStatus();
}

/// Cold start: stored tokens are still being read, so it isn't yet known
/// whether there is a Session.
class Restoring extends AuthStatus {
  const Restoring();
}

class Unauthenticated extends AuthStatus {
  const Unauthenticated();
}

/// There is a Session on this Device. Its access token may have expired; the
/// first 401 refreshes it.
class Authenticated extends AuthStatus {
  const Authenticated();
}

/// The one source of truth for whether the app is signed in; the router
/// gates screens on it.
@Riverpod(keepAlive: true)
class AuthState extends _$AuthState {
  @override
  AuthStatus build() {
    _restore();
    return const Restoring();
  }

  /// A stored refresh token means the Device is still signed in. Nothing is
  /// checked over the network, so the app opens straight onto its screens.
  Future<void> _restore() async {
    AuthStatus restored;
    try {
      final refreshToken = await ref
          .read(tokenStoreProvider)
          .readRefreshToken();
      restored = refreshToken == null
          ? const Unauthenticated()
          : const Authenticated();
    } catch (_) {
      restored = const Unauthenticated();
    }
    // A sign-in or sign-out while restoring is newer than what was stored.
    if (state is Restoring) state = restored;
  }

  Future<void> requestOtp(String phoneNumber) =>
      ref.read(authRepositoryProvider).requestOtp(phoneNumber);

  Future<void> verifyOtp(String phoneNumber, String code) async {
    final result = await ref
        .read(authRepositoryProvider)
        .verifyOtp(phoneNumber, code);
    await ref
        .read(tokenStoreProvider)
        .saveTokens(
          accessToken: result.accessToken,
          refreshToken: result.refreshToken,
        );
    state = const Authenticated();
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clearTokens();
    state = const Unauthenticated();
  }
}
