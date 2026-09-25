import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/conversation_list_item.dart';
import '../data/conversation_prefs_repository.dart';
import '../data/conversations_repository.dart';
import 'conversation_prefs_action.dart';
import 'mute_duration_sheet.dart';

/// The chat's menu (#45): mute, clear and delete, all backed by the real
/// `ConversationPrefsRepository`. Block is UI-only for now — there's no
/// backend concept for it yet, unlike the other three.
class ContactInfoScreen extends ConsumerStatefulWidget {
  const ContactInfoScreen({
    super.key,
    required this.conversationId,
    required this.title,
  });

  final String conversationId;
  final String title;

  @override
  ConsumerState<ContactInfoScreen> createState() => _ContactInfoScreenState();
}

class _ContactInfoScreenState extends ConsumerState<ContactInfoScreen> {
  ConversationListItem? _findCurrent() {
    for (final list in [
      ref.watch(conversationListProvider()).value ??
          const <ConversationListItem>[],
      ref.watch(conversationListProvider(archived: true)).value ??
          const <ConversationListItem>[],
    ]) {
      for (final item in list) {
        if (item.id == widget.conversationId) return item;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _findCurrent();
    final muted = current?.muted ?? false;
    final prefs = ref.read(conversationPrefsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contact info')),
      body: ListView(
        children: [
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: AppAvatar(
              label: widget.title,
              seed: widget.conversationId,
              size: 96,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: Text(widget.title, style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.xxl),
          SwitchListTile(
            secondary: Icon(
              muted
                  ? Icons.notifications_off
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('Mute notifications'),
            value: muted,
            onChanged: (_) => showMuteDurationSheet(
              context,
              alreadyMuted: muted,
              mutedUntil: current?.mutedUntil,
              onMute: (duration) => runConversationPrefsAction(
                context,
                ref,
                () => prefs.mute(widget.conversationId, duration),
              ),
              onUnmute: () => runConversationPrefsAction(
                context,
                ref,
                () => prefs.unmute(widget.conversationId),
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear chat'),
            onTap: () => _confirmClear(context, prefs),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
            title: Text(
              'Delete chat',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmDelete(context, prefs),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.block, color: theme.colorScheme.error),
            title: Text(
              'Block contact',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmBlock(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(
    BuildContext context,
    ConversationPrefsRepository prefs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this chat?'),
        content: const Text(
          'Messages will be removed from your view of this chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await runConversationPrefsAction(context, ref, () async {
        await prefs.clear(widget.conversationId);
        if (context.mounted) context.pop();
      });
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ConversationPrefsRepository prefs,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete chat with ${widget.title}?'),
        content: const Text(
          "This removes it from your list. If they message you again, it'll come back with "
          'only the new message.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      await runConversationPrefsAction(context, ref, () async {
        await prefs.delete(widget.conversationId);
        // The chat is now hidden from the list — leave both the info screen
        // and the chat thread behind it.
        if (context.mounted) context.go('/');
      });
    }
  }

  Future<void> _confirmBlock(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Block ${widget.title}?'),
        content: const Text("You won't receive messages from this contact."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if ((confirmed ?? false) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} is blocked on this device')),
      );
    }
  }
}
