import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/database_provider.dart';
import '../../../core/formatting/display_name.dart';
import '../data/auth_repository.dart';
import 'auth_state.dart';

/// The signed-in UI's account menu: who is signed in on this Device, "Log
/// out other devices", and "Log out".
class AccountMenu extends ConsumerWidget {
  const AccountMenu({super.key});

  static const logOutKey = Key('account-menu-log-out');
  static const confirmLogOutKey = Key('account-menu-confirm-log-out');

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
          key: AccountMenu.logOutKey,
          leadingIcon: const Icon(Icons.logout),
          onPressed: () => _confirmAndSignOut(context, ref),
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

  /// "Logout with a non-empty Outbox warns: 'N unsent messages will be
  /// lost'" (ADR 0009/#54) — asked before [AuthState.signOut] runs, since
  /// signing out wipes the Outbox along with the rest of the replica.
  Future<void> _confirmAndSignOut(BuildContext context, WidgetRef ref) async {
    final pending = await ref.read(appDatabaseProvider).outboxCount();
    if (!context.mounted) return;
    if (pending > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Log out?'),
          content: Text(
            '$pending unsent message${pending == 1 ? '' : 's'} will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              key: AccountMenu.confirmLogOutKey,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Log out'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await ref.read(authStateProvider.notifier).signOut();
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
