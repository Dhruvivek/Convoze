import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/presentation/auth_state.dart';
import '../../features/auth/presentation/otp_entry_screen.dart';
import '../../features/auth/presentation/phone_entry_screen.dart';
import '../../features/conversations/presentation/archived_conversations_screen.dart';
import '../../features/conversations/presentation/chat_thread_screen.dart';
import '../../features/conversations/presentation/contact_info_screen.dart';
import '../../features/conversations/presentation/new_conversation_screen.dart';
import '../../features/conversations/presentation/search_conversations_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import 'splash_screen.dart';

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
      final location = state.matchedLocation;
      final atSplash = location == '/splash';
      // Everything under /login is the unauthenticated area.
      final atLogin = location.startsWith('/login');

      return switch (ref.read(authStateProvider)) {
        Restoring() => atSplash ? null : '/splash',
        Unauthenticated() => atLogin ? null : '/login',
        Authenticated() => atSplash || atLogin ? '/' : null,
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
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
        builder: (context, state) => const HomeShell(),
        routes: [
          GoRoute(
            path: 'new',
            builder: (context, state) => const NewConversationScreen(),
          ),
          GoRoute(
            path: 'search',
            builder: (context, state) => const SearchConversationsScreen(),
          ),
          GoRoute(
            path: 'archived',
            builder: (context, state) => const ArchivedConversationsScreen(),
          ),
          GoRoute(
            path: 'thread/:id',
            builder: (context, state) => ChatThreadScreen(
              conversationId: state.pathParameters['id']!,
              title: state.extra as String?,
            ),
            routes: [
              GoRoute(
                path: 'info',
                builder: (context, state) => ContactInfoScreen(
                  conversationId: state.pathParameters['id']!,
                  title: state.extra as String? ?? 'Conversation',
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
