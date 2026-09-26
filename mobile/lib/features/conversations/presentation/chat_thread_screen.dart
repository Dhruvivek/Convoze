import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../data/chat_message_view.dart';
import '../data/media_repository.dart';
import '../data/messages_repository.dart';
import '../data/typing_repository.dart';
import 'chat_message_list.dart';
import 'chat_thread_providers.dart';
import 'message_action.dart';
import 'message_action_sheet.dart';

/// The chat screen (#53/#55, extended by #40's media pass and #56's edit &
/// delete): messages from the bottom, grouped by day, paging older history
/// on scroll-to-top. Reads only from the replica via [chatMessagesProvider];
/// sending, editing, deleting and paging go through
/// [MessagesRepository]/[ChatThreadController].
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  static const composerFieldKey = Key('chat-composer-field');
  static const sendButtonKey = Key('chat-send-button');
  static const attachButtonKey = Key('chat-attach-button');
  static const retryFailedKey = Key('chat-retry-failed');
  static const discardFailedKey = Key('chat-discard-failed');

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  bool _uploading = false;

  /// The message currently being edited (#56), or null while composing a
  /// new one. Prefilled into [_composer] by [_startEdit]; [_send] branches
  /// on this instead of always sending a new Message.
  ChatMessageView? _editing;

  /// The newest message id [markRead] has already been called for, so a
  /// rebuild triggered by something else (e.g. a tick changing) doesn't
  /// call it again.
  String? _readThrough;

  /// Read once in [initState], not via `ref.read` in [dispose]: by the time
  /// `dispose()` runs, this widget is already unmounted (`State.mounted` is
  /// false), and Riverpod's `ref` refuses to resolve a provider against an
  /// unmounted widget's `BuildContext` — it throws rather than risk stale
  /// state.
  late final TypingRepository _typingRepository;

  static const _loadOlderThreshold = 200.0;

  @override
  void initState() {
    super.initState();
    _typingRepository = ref.read(typingRepositoryProvider);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(chatThreadControllerProvider(widget.conversationId).notifier)
          .ensureInitialPage();
      unawaited(
        ref.read(messagesRepositoryProvider).markRead(widget.conversationId),
      );
    });
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_onScroll)
      ..dispose();
    _composer.dispose();
    // Leaving the chat is one of #35's own "stop typing" triggers.
    _typingRepository.stopTyping(widget.conversationId);
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
        _scroll.position.maxScrollExtent - _loadOlderThreshold) {
      ref
          .read(chatThreadControllerProvider(widget.conversationId).notifier)
          .loadOlder();
    }
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (text.trim().isEmpty) return;
    final editing = _editing;
    if (editing != null) {
      _composer.clear();
      _typingRepository.stopTyping(widget.conversationId);
      setState(() => _editing = null);
      await runMessageAction(
        context,
        () => ref
            .read(messagesRepositoryProvider)
            .editMessage(editing.id, text.trim()),
      );
      return;
    }
    _composer.clear();
    // `TextEditingController.clear()` doesn't fire `onChanged`, so this
    // needs its own explicit call (#35: "stopTyping is emitted on send").
    _typingRepository.stopTyping(widget.conversationId);
    await ref.read(messagesRepositoryProvider).send(widget.conversationId, text);
  }

  void _onComposerChanged(String text) {
    _typingRepository.composerChanged(widget.conversationId, text);
  }

  /// Enters edit mode for [message], refusing up front while disconnected
  /// (#56) — the same gating point [_confirmAndDelete] checks before its
  /// confirm dialog, since there's nothing useful to compose an edit for
  /// without a connection to send it over.
  void _startEdit(ChatMessageView message) {
    if (!ensureConnected(context, ref)) return;
    setState(() {
      _editing = message;
      _composer.text = message.content ?? '';
      _composer.selection = TextSelection.collapsed(offset: _composer.text.length);
    });
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _composer.clear();
  }

  Future<void> _confirmAndDelete(ChatMessageView message) async {
    if (!ensureConnected(context, ref)) return;
    final confirmed = await confirmDeleteMessage(context);
    if (!confirmed || !mounted) return;
    await runMessageAction(
      context,
      () => ref.read(messagesRepositoryProvider).deleteMessage(message.id),
    );
  }

  void _onMessageLongPress(ChatMessageView message) {
    unawaited(
      showMessageActions(
        context,
        message: message,
        onEdit: () => _startEdit(message),
        onDelete: () => _confirmAndDelete(message),
      ),
    );
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
    final extension = picked.single.extension;
    final caption = await _promptCaption();
    if (!mounted) return;
    await _upload(
      () => ref.read(mediaRepositoryProvider).uploadDocument(File(path), extension: extension),
      (upload) {
        return ref
            .read(messagesRepositoryProvider)
            .sendMedia(
              widget.conversationId,
              kind: MediaKind.file,
              upload: upload,
              fileName: fileName,
              caption: caption,
            );
      },
    );
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

  /// "failed — tap to retry or delete" (ADR 0009): offers both, then acts on
  /// the choice through [MessagesRepository].
  Future<void> _handleFailedTap(String clientMsgId) async {
    final repository = ref.read(messagesRepositoryProvider);
    final choice = await showModalBottomSheet<_FailedMessageAction>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: ChatThreadScreen.retryFailedKey,
              leading: const Icon(Icons.refresh),
              title: const Text('Retry'),
              onTap: () =>
                  Navigator.pop(context, _FailedMessageAction.retry),
            ),
            ListTile(
              key: ChatThreadScreen.discardFailedKey,
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () =>
                  Navigator.pop(context, _FailedMessageAction.discard),
            ),
          ],
        ),
      ),
    );
    switch (choice) {
      case _FailedMessageAction.retry:
        await repository.retry(clientMsgId);
      case _FailedMessageAction.discard:
        await repository.discard(clientMsgId);
      case null:
        break;
    }
  }

  void _markReadIfNewer(List<ChatMessageView> views) {
    if (views.isEmpty) return;
    final newest = views.last.id;
    if (newest == _readThrough) return;
    _readThrough = newest;
    unawaited(
      ref.read(messagesRepositoryProvider).markRead(widget.conversationId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        ref.watch(chatThreadTitleProvider(widget.conversationId)).value ??
        '';
    final messagesAsync = ref.watch(chatMessagesProvider(widget.conversationId));
    final threadState = ref.watch(
      chatThreadControllerProvider(widget.conversationId),
    );

    ref.listen(chatMessagesProvider(widget.conversationId), (_, next) {
      final views = next.value;
      if (views != null) _markReadIfNewer(views);
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _InitialsAvatar(seed: widget.conversationId, label: title),
            const SizedBox(width: 12),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_uploading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: switch (messagesAsync) {
              AsyncData(:final value) => MessageList(
                views: value,
                scrollController: _scroll,
                isLoadingOlder: threadState.isLoadingOlder,
                reachedStart: threadState.reachedStart,
                onTapFailed: (clientMsgId) => unawaited(_handleFailedTap(clientMsgId)),
                onLongPress: _onMessageLongPress,
              ),
              AsyncError() => const Center(
                child: Text('Couldn\'t load this conversation'),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
          _Composer(
            controller: _composer,
            fieldKey: ChatThreadScreen.composerFieldKey,
            sendKey: ChatThreadScreen.sendButtonKey,
            attachKey: ChatThreadScreen.attachButtonKey,
            onSend: _send,
            onChanged: _onComposerChanged,
            onAttach: _uploading ? null : _attach,
            onCancelEdit: _editing == null ? null : _cancelEdit,
          ),
        ],
      ),
    );
  }
}

enum _AttachChoice { photo, document }

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.seed, required this.label});

  final String seed;
  final String label;

  static const _palette = [
    Color(0xFF6750A4),
    Color(0xFF386A20),
    Color(0xFFB3261E),
    Color(0xFF006874),
    Color(0xFF9C4146),
    Color(0xFF4A6363),
  ];

  @override
  Widget build(BuildContext context) {
    final color = _palette[seed.hashCode.abs() % _palette.length];
    final trimmed = label.trim();
    final initial = trimmed.isEmpty ? '' : trimmed.substring(0, 1).toUpperCase();
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.16),
      child: Text(initial, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.fieldKey,
    required this.sendKey,
    required this.attachKey,
    required this.onSend,
    required this.onChanged,
    this.onAttach,
    this.onCancelEdit,
  });

  final TextEditingController controller;
  final Key fieldKey;
  final Key sendKey;
  final Key attachKey;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAttach;

  /// Non-null while editing a message (#56) — shows a cancel banner above
  /// the input instead of the plain composer.
  final VoidCallback? onCancelEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final editing = onCancelEdit != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
                child: Row(
                  children: [
                    Icon(Icons.edit_outlined, size: 16, color: scheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Editing message',
                        style: TextStyle(color: scheme.primary, fontSize: 12.5),
                      ),
                    ),
                    IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: onCancelEdit,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                IconButton(
                  key: attachKey,
                  onPressed: editing ? null : onAttach,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Expanded(
                  child: TextField(
                    key: fieldKey,
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onChanged: onChanged,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(hintText: 'Message'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: sendKey,
                  onPressed: onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _FailedMessageAction { retry, discard }
