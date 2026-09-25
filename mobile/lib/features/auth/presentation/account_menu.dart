import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/display_name.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

/// The signed-in UI's account menu: who is signed in on this Device, "Log
/// out other devices", and "Log out".
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only shown behind the signed-in routes, but may still build for a
    // frame after a sign-out.
    final auth = ref.watch(authStateProvider);
    if (auth is! Authenticated) return const SizedBox.shrink();
    final user = auth.user;

    return MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            displayName(
              displayName: user.displayName,
              phoneNumber: user.phoneNumber,
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        const Divider(),
        MenuItemButton(
          leadingIcon: const Icon(Icons.devices_other),
          onPressed: () => _logOutOtherDevices(context, ref),
          child: const Text('Log out other devices'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => ref.read(authStateProvider.notifier).signOut(),
          child: const Text('Log out'),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.account_circle),
        tooltip: 'Account',
        onPressed: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// This Device stays signed in whatever happens, so the outcome is only
  /// reported.
  Future<void> _logOutOtherDevices(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    String message;
    try {
      await ref.read(authRepositoryProvider).logoutOthers();
      message = 'Logged out of your other devices';
    } catch (_) {
      message = "Couldn't log out your other devices. Try again.";
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}
