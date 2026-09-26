import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/media_repository.dart';
import '../data/messages_repository.dart';
import 'message_action_sheet.dart';
import 'message_bubble.dart';

/// The chat screen (reduced-scope real wiring for #40's photos+documents
/// pass): messages come from the real replica via [chatMessagesProvider],
/// not from the old `mock_thread.dart`. Sending — text or media — goes
/// through [MessagesRepository], which inserts into the Outbox that the
/// already-real [SyncEngine] drains.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId, this.title});

  final String conversationId;
  final String? title;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _input = TextEditingController();
  bool _uploading = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    if (_input.text.trim().isEmpty) return;
    final text = _input.text;
    _input.clear();
    ref.read(messagesRepositoryProvider).sendText(widget.conversationId, text);
  }

  Future<void> _attach() async {
    final choice = await showModalBottomSheet<_AttachChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('Photo'),
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.photo),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              onTap: () => Navigator.of(sheetContext).pop(_AttachChoice.document),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case _AttachChoice.photo:
        await _sendPhoto();
      case _AttachChoice.document:
        await _sendDocument();
    }
  }

  Future<void> _sendPhoto() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    final caption = await _promptCaption();
    if (!mounted) return;
    await _upload(() => ref.read(mediaRepositoryProvider).uploadImage(File(picked.path)), (upload) {
      return ref
          .read(messagesRepositoryProvider)
          .sendMedia(
            widget.conversationId,
            kind: MediaKind.image,
            upload: upload,
            caption: caption,
          );
    });
  }

  Future<void> _sendDocument() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'zip', 'txt'],
    );
    final path = picked.isEmpty ? null : picked.single.path;
    if (path == null || !mounted) return;
    final fileName = picked.single.name;
    final caption = await _promptCaption();
    if (!mounted) return;
    await _upload(() => ref.read(mediaRepositoryProvider).uploadDocument(File(path)), (upload) {
      return ref
          .read(messagesRepositoryProvider)
          .sendMedia(
            widget.conversationId,
            kind: MediaKind.file,
            upload: upload,
            fileName: fileName,
            caption: caption,
          );
    });
  }

  /// An optional caption, collected right after picking and before
  /// uploading — a lighter stand-in for #40's full preview-with-caption
  /// screen, which this reduced scope doesn't build. Empty input means no
  /// caption, not an empty-string one.
  Future<String?> _promptCaption() async {
    final controller = TextEditingController();
    final caption = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add a caption?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'Caption (optional)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Skip')),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = caption?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> _upload(
    Future<CloudinaryUploadResult> Function() upload,
    Future<void> Function(CloudinaryUploadResult) send,
  ) async {
    setState(() => _uploading = true);
    try {
      final result = await upload();
      await send(result);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Couldn't send that. Try again.")));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(chatMessagesProvider(widget.conversationId));
    final title = widget.title ?? 'Conversation';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          onTap: () => context.push('/thread/${widget.conversationId}/info', extra: title),
          child: Row(
            children: [
              AppAvatar(label: title, seed: widget.conversationId, size: 34),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_uploading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: messagesAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (error, stackTrace) => Center(
                  child: Text(
                    "Couldn't load this chat.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                data: (messages) => messages.isEmpty
                    ? _EmptyThread(name: title)
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[messages.length - 1 - index];
                          return MessageBubble(
                            message: message,
                            onLongPress: () => showMessageActions(context, message: message),
                          );
                        },
                      ),
              ),
            ),
            _Composer(controller: _input, onSend: _send, onAttach: _uploading ? null : _attach),
          ],
        ),
      ),
    );
  }
}

enum _AttachChoice { photo, document }

class _EmptyThread extends StatelessWidget {
  const _EmptyThread({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Text(
          'Say hi to $name 👋',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend, required this.onAttach});

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(onPressed: onAttach, icon: const Icon(Icons.add_circle_outline)),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(
                hintText: 'Message',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton.filled(
            onPressed: onSend,
            icon: const Icon(Icons.arrow_upward_rounded),
            style: IconButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
