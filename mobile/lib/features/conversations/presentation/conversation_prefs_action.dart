import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/realtime/connection_manager.dart';
import '../data/conversation_prefs_failure.dart';

/// Runs a [ConversationPrefsRepository] call, refusing up front while
/// offline (#45: "Preference actions are disabled offline, with a snackbar
/// saying 'Needs a connection'") and mapping any [ConversationPrefsFailure]
/// to a snackbar otherwise. Shared by the list's long-press/swipe actions
/// and the chat menu (`ContactInfoScreen`) so this gating exists once.
Future<void> runConversationPrefsAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  if (ref.read(connectionManagerProvider).status !=
      ConnectionStatus.connected) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Needs a connection')));
    return;
  }
  try {
    await action();
  } on ConversationPrefsFailure catch (failure) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_messageFor(failure))));
  }
}

String _messageFor(ConversationPrefsFailure failure) => switch (failure) {
  PinLimitReached() => 'You can pin up to 5 chats — unpin one first.',
  MustLeaveGroup() => 'Leave the group first.',
  ConversationPrefsNotFound() => "This chat isn't available any more.",
  ConversationPrefsNetworkFailure() => 'Needs a connection. Try again.',
  UnexpectedConversationPrefsFailure() => 'Something went wrong. Try again.',
};
