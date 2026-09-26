import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database_provider.dart';
import '../../../core/models/user.dart';
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
  const Authenticated(this.user);

  /// Who is signed in, as they were at sign-in.
  final User user;
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

  /// A stored refresh token and User mean the Device is still signed in.
  /// Nothing is checked over the network, so the app opens straight onto its
  /// screens.
  Future<void> _restore() async {
    AuthStatus restored;
    try {
      final tokenStore = ref.read(tokenStoreProvider);
      final refreshToken = await tokenStore.readRefreshToken();
      final user = refreshToken == null ? null : await tokenStore.readUser();
      if (user != null) {
        restored = Authenticated(user);
      } else {
        // Tokens without their User are half a Session; don't leave them
        // behind for the next sign-in to overwrite.
        if (refreshToken != null) await tokenStore.clearSession();
        restored = const Unauthenticated();
      }
    } catch (_) {
      restored = const Unauthenticated();
    }
    // A sign-in or sign-out while restoring is newer than what was stored.
    if (state is Restoring) state = restored;
  }

  Future<void> requestOtp(String phoneNumber) =>
      ref.read(authRepositoryProvider).requestOtp(phoneNumber);

  /// Sets this Device's cached display name. Local-only for now — stands in
  /// until there's a real profile-update endpoint to call before saving
  /// (mirrors how the User is already cached locally after sign-in).
  Future<void> updateDisplayName(String? name) async {
    final current = state;
    if (current is! Authenticated) return;
    final trimmed = name?.trim();
    final updated = User(
      id: current.user.id,
      phoneNumber: current.user.phoneNumber,
      displayName: (trimmed == null || trimmed.isEmpty) ? null : trimmed,
    );
    await ref.read(tokenStoreProvider).saveUser(updated);
    state = Authenticated(updated);
  }

  Future<void> verifyOtp(String phoneNumber, String code) async {
    final result = await ref.read(authRepositoryProvider).verifyOtp(phoneNumber, code);
    final tokenStore = ref.read(tokenStoreProvider);
    await tokenStore.saveTokens(accessToken: result.accessToken, refreshToken: result.refreshToken);
    await tokenStore.saveUser(result.user);
    state = Authenticated(result.user);
  }

  /// The Session can no longer be renewed and its tokens are already gone:
  /// back to login.
  void sessionEnded() => state = const Unauthenticated();

  /// Logs this Device out: ends the Session on the server if it can, then
  /// forgets it here and goes back to login whatever the server said, so
  /// being offline never leaves the user stuck signed in.
  ///
  /// A second call while one is in flight waits on that one.
  Future<void> signOut() => _signingOut ??= _signOut().whenComplete(() => _signingOut = null);

  Future<void>? _signingOut;

  Future<void> _signOut() async {
    try {
      await ref.read(authRepositoryProvider).logout();
    } catch (_) {
      // Best effort: the Session still ends on this Device.
    }
    await ref.read(tokenStoreProvider).clearSession();
    // The replica is disposable except the Outbox (ADR 0009) — but logout
    // takes the Outbox with it too (#54): whatever this Device never
    // managed to send is gone with the Session, after the caller has
    // already warned the user how many messages that is.
    await ref.read(appDatabaseProvider).wipeAll();
    state = const Unauthenticated();
  }
}
