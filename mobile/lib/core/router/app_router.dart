import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_state.dart';
import '../../features/auth/presentation/otp_entry_screen.dart';
import '../../features/auth/presentation/phone_entry_screen.dart';
import '../../features/conversations/presentation/conversations_screen.dart';

part 'app_router.g.dart';

class _AuthRefreshListenable extends ChangeNotifier {
  _AuthRefreshListenable(Ref ref) {
    ref.listen(authStateProvider, (_, _) => notifyListeners());
  }
}

@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final refreshListenable = _AuthRefreshListenable(ref);
  ref.onDispose(refreshListenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final isAuthenticated = ref.read(authStateProvider) is Authenticated;
      // Everything under /login is the unauthenticated area.
      final isLoggingIn = state.matchedLocation.startsWith('/login');

      if (!isAuthenticated && !isLoggingIn) return '/login';
      if (isAuthenticated && isLoggingIn) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const PhoneEntryScreen(),
        routes: [
          GoRoute(
            path: 'otp',
            // The phone number comes from the phone-entry screen; without
            // one (e.g. a restored route) start over there.
            redirect: (context, state) =>
                state.extra is String ? null : '/login',
            builder: (context, state) =>
                OtpEntryScreen(phoneNumber: state.extra! as String),
          ),
        ],
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const ConversationsScreen(),
      ),
    ],
  );
}
