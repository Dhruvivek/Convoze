import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/chat_message_view.dart';

/// The long-press action sheet for a message: "Copy" for any text message,
/// plus "Edit" and "Delete" (#56) for the sender's own, already-landed text
/// messages — a still-pending Outbox row's `id` is its `clientMsgId`, not a
/// real `messageId` either call can reference, and media/others' messages
/// get neither. Whether the two calls actually go through is decided at tap
/// time (see `ensureConnected`/`message_action.dart`), not here: this sheet
/// is pure UI, unaware of the connection.
Future<void> showMessageActions(
  BuildContext context, {
  required ChatMessageView message,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final text = message.content ?? '';
  final canModify = message.fromMe &&
      message.type == 'text' &&
      !message.isDeleted &&
      message.tick != MessageTick.clock &&
      message.tick != MessageTick.failed;
  if (text.isEmpty && !canModify) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Copy'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                Clipboard.setData(ClipboardData(text: text));
              },
            ),
          if (canModify)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onEdit?.call();
              },
            ),
          if (canModify)
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onDelete?.call();
              },
            ),
        ],
      ),
    ),
  );
}
