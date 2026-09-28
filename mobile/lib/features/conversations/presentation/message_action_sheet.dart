import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/chat_message_view.dart';

/// The fixed quick-reaction set (#103) — a small, WhatsApp/Signal-style
/// shortlist rather than a full picker, so reacting is a single tap from
/// the long-press sheet.
const quickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// The long-press action sheet for a message: a quick-reaction row (#103,
/// any non-deleted, already-landed message), "Reply" (#102, same
/// landed-message restriction — there's no stable id to reply to before
/// then), "Copy" for any text message, plus "Edit" and "Delete" (#56) for
/// the sender's own, already-landed text messages. A still-pending Outbox
/// row's `id` is its `clientMsgId`, not a real `messageId` any of these
/// calls can reference. Whether the calls actually go through is decided at
/// tap time (see `ensureConnected`/`message_action.dart`), not here: this
/// sheet is pure UI, unaware of the connection.
Future<void> showMessageActions(
  BuildContext context, {
  required ChatMessageView message,
  VoidCallback? onReply,
  void Function(String emoji)? onReact,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  final text = message.content ?? '';
  final isLanded = message.tick != MessageTick.clock && message.tick != MessageTick.failed;
  final canModify = message.fromMe && message.type == 'text' && !message.isDeleted && isLanded;
  final canReplyOrReact = isLanded && !message.isDeleted;
  if (text.isEmpty && !canModify && !canReplyOrReact) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canReplyOrReact)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in quickReactionEmojis)
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        onReact?.call(emoji);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
                      ),
                    ),
                ],
              ),
            ),
          if (canReplyOrReact) const Divider(height: 1),
          if (canReplyOrReact)
            ListTile(
              leading: const Icon(Icons.reply_outlined),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onReply?.call();
              },
            ),
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
