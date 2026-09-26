import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// The signed-in shell's overflow menu — deliberately just the one action.
/// Everything else account-related (profile, other devices) has its own
/// home in the bottom-nav tabs now, not buried in a dropdown.
class LogoutMenu extends ConsumerWidget {
  const LogoutMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'More',
      onSelected: (_) => ref.read(authStateProvider.notifier).signOut(),
      itemBuilder: (context) => const [PopupMenuItem(value: 'logout', child: Text('Log out'))],
    );
  }
}
