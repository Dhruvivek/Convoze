import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_state.g.dart';

enum AuthStatus { unauthenticated, authenticated }

// Placeholder until the phone+OTP flow (data layer + session persistence)
// lands; the router only needs to know when this flips to authenticated.
@Riverpod(keepAlive: true)
class AuthState extends _$AuthState {
  @override
  AuthStatus build() => AuthStatus.unauthenticated;

  void signIn() => state = AuthStatus.authenticated;

  void signOut() => state = AuthStatus.unauthenticated;
}
