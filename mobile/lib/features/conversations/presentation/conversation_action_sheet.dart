import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/conversation_list_item.dart';
import '../data/conversation_prefs_repository.dart';
import 'mute_duration_sheet.dart';

/// The long-press action sheet for a conversation row: pin/unpin,
/// mute/unmute, archive/unarchive, clear and delete (#45) — each callback
/// backed by the real `ConversationPrefsRepository`.
Future<void> showConversationActions(
  BuildContext context, {
  required ConversationListItem conversation,
  required VoidCallback onTogglePin,
  required void Function(MuteDuration duration) onMute,
  required VoidCallback onUnmute,
  required VoidCallback onToggleArchive,
  required VoidCallback onClear,
  required VoidCallback onDelete,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                conversation.title,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              conversation.pinned ? Icons.push_pin : Icons.push_pin_outlined,
            ),
            title: Text(conversation.pinned ? 'Unpin chat' : 'Pin chat'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onTogglePin();
            },
          ),
          ListTile(
            leading: Icon(
              conversation.muted
                  ? Icons.notifications_off
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('Mute chat'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showMuteDurationSheet(
                context,
                alreadyMuted: conversation.muted,
                mutedUntil: conversation.mutedUntil,
                onMute: onMute,
                onUnmute: onUnmute,
              );
            },
          ),
          ListTile(
            leading: Icon(
              conversation.archived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
            ),
            title: Text(
              conversation.archived ? 'Unarchive chat' : 'Archive chat',
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onToggleArchive();
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear chat'),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              if (await _confirmClear(context)) onClear();
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(sheetContext).colorScheme.error,
            ),
            title: Text(
              'Delete chat',
              style: TextStyle(color: Theme.of(sheetContext).colorScheme.error),
            ),
            onTap: () async {
              Navigator.of(sheetContext).pop();
              if (await _confirmDelete(context, conversation.title)) onDelete();
            },
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmClear(BuildContext context) async {
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
  return confirmed ?? false;
}

Future<bool> _confirmDelete(BuildContext context, String title) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Delete chat with $title?'),
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
  return confirmed ?? false;
}
