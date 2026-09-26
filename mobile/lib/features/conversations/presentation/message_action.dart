import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_manager.dart';
import '../data/message_action_failure.dart';

/// True while connected; otherwise shows the same "Needs a connection"
/// refusal #45 uses for offline preference actions and answers false (#56:
/// edit/delete are "disabled — not silently failing — while disconnected").
/// Checked up front, before composing a dialog or an edit, since neither
/// call is queued in the Outbox (ADR 0009) — there's nothing to resume once
/// reconnected, only something to refuse now.
bool ensureConnected(BuildContext context, WidgetRef ref) {
  if (ref.read(connectionManagerProvider).status == ConnectionStatus.connected) {
    return true;
  }
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Needs a connection')));
  return false;
}

/// A confirmation dialog before deleting a message (#56: "confirms").
Future<bool> confirmDeleteMessage(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete message?'),
      content: const Text("This can't be undone."),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// A snackbar-ready message for a failed edit/delete.
String messageForMessageActionFailure(MessageActionFailure failure) => switch (failure) {
  MessageActionNotFound() => "This message isn't available any more.",
  MessageActionForbidden() => "You can't do that.",
  MessageActionTooLarge() => 'That message is too long.',
  MessageActionRateLimited() => 'Too many changes — try again in a moment.',
  MessageActionNetworkFailure() => 'Needs a connection. Try again.',
  UnexpectedMessageActionFailure() => 'Something went wrong. Try again.',
};

/// Runs an edit/delete [action], mapping any [MessageActionFailure] it
/// throws to a snackbar. The connectivity gate itself is separate
/// ([ensureConnected]) — callers check that up front, before this runs.
Future<void> runMessageAction(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
  } on MessageActionFailure catch (failure) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(messageForMessageActionFailure(failure))));
  }
}
