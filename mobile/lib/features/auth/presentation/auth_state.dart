import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/user.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';

part 'auth_state.g.dart';

sealed class AuthStatus {
  const AuthStatus();
}

class Unauthenticated extends AuthStatus {
  const Unauthenticated();
}

class Authenticated extends AuthStatus {
  const Authenticated(this.user);

  final User user;
}

/// The one source of truth for whether the app is signed in; the router
/// gates screens on it.
@Riverpod(keepAlive: true)
class AuthState extends _$AuthState {
  @override
  AuthStatus build() => const Unauthenticated();

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
    state = Authenticated(result.user);
  }

  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clearTokens();
    state = const Unauthenticated();
  }
}
