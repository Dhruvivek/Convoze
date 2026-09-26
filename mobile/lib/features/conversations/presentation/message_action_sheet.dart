import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_chat_message.dart';

/// The long-press action sheet for a message. Reduced to "Copy" for this
/// pass: edit/delete/react have no real backend wiring yet (out of scope
/// here), and offering them against the real, read-only replica would be a
/// dead end that looks like it did something. Extending this once
/// edit/delete/react are real is a matter of adding rows back, not
/// redesigning the sheet.
Future<void> showMessageActions(BuildContext context, {required LocalChatMessage message}) {
  final text = message.content ?? '';
  if (text.isEmpty) return Future.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Clipboard.setData(ClipboardData(text: text));
            },
          ),
        ],
      ),
    ),
  );
}
