import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_state.dart';
import '../data/app_preferences.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.embedded = false, this.onOpenProfile});

  /// True when shown as a bottom-nav tab body (no own app bar).
  final bool embedded;

  /// Called when the profile row is tapped. In the shell this switches to
  /// the Profile tab.
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final themeMode = ref.watch(themeModeProvider);
    final notificationsEnabled = ref.watch(notificationsEnabledProvider);
    final theme = Theme.of(context);

    final content = ListView(
      children: [
        if (auth is Authenticated) ...[
          ListTile(
            leading: AppAvatar(
              label: displayName(
                displayName: auth.user.displayName,
                phoneNumber: auth.user.phoneNumber,
              ),
              seed: auth.user.id,
              size: 44,
            ),
            title: Text(
              displayName(displayName: auth.user.displayName, phoneNumber: auth.user.phoneNumber),
            ),
            subtitle: Text(auth.user.phoneNumber),
            trailing: onOpenProfile == null ? null : const Icon(Icons.chevron_right),
            onTap: onOpenProfile,
          ),
          const Divider(height: 1),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Text('Appearance', style: theme.textTheme.titleSmall),
        ),
        RadioGroup<ThemeMode>(
          groupValue: themeMode,
          onChanged: (mode) => ref.read(themeModeProvider.notifier).set(mode!),
          child: const Column(
            children: [
              RadioListTile<ThemeMode>(title: Text('System'), value: ThemeMode.system),
              RadioListTile<ThemeMode>(title: Text('Light'), value: ThemeMode.light),
              RadioListTile<ThemeMode>(title: Text('Dark'), value: ThemeMode.dark),
            ],
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          secondary: const Icon(Icons.notifications_outlined),
          title: const Text('Message notifications'),
          value: notificationsEnabled,
          onChanged: (_) => ref.read(notificationsEnabledProvider.notifier).toggle(),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.devices_other),
          title: const Text('Log out other devices'),
          onTap: () => _logOutOtherDevices(context, ref),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('Help & support'),
          onTap: () => _showHelp(context),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('About Convoze'),
          subtitle: Text('Version 1.0.0'),
        ),
      ],
    );

    if (embedded) return content;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: content,
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

  void _showHelp(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help & support', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              const _HelpItem(
                question: 'How do I start a conversation?',
                answer: 'Tap the compose button on Chats and pick someone to message.',
              ),
              const _HelpItem(
                question: "I didn't get my verification code",
                answer:
                    'Wait for the resend cooldown to finish, then tap "Resend code". Check that '
                    'your number is entered correctly.',
              ),
              const _HelpItem(
                question: 'How do I change my name?',
                answer: 'Open the Profile tab, update your display name, and save.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpItem extends StatelessWidget {
  const _HelpItem({required this.question, required this.answer});

  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(answer, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
