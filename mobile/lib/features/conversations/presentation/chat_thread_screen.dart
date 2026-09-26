import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_message_view.dart';
import '../data/messages_repository.dart';
import '../data/typing_repository.dart';
import 'chat_message_list.dart';
import 'chat_thread_providers.dart';

/// The chat screen (#53/#55): messages from the bottom, grouped by day,
/// paging older history on scroll-to-top. Reads only from the replica via
/// [chatMessagesProvider]; sending and paging go through
/// [MessagesRepository]/[ChatThreadController].
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({super.key, required this.conversationId});

  final String conversationId;

  static const composerFieldKey = Key('chat-composer-field');
  static const sendButtonKey = Key('chat-send-button');
  static const retryFailedKey = Key('chat-retry-failed');
  static const discardFailedKey = Key('chat-discard-failed');

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

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
    _composer.clear();
    // `TextEditingController.clear()` doesn't fire `onChanged`, so this
    // needs its own explicit call (#35: "stopTyping is emitted on send").
    _typingRepository.stopTyping(widget.conversationId);
    await ref.read(messagesRepositoryProvider).send(widget.conversationId, text);
  }

  void _onComposerChanged(String text) {
    _typingRepository.composerChanged(widget.conversationId, text);
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
          Expanded(
            child: switch (messagesAsync) {
              AsyncData(:final value) => MessageList(
                views: value,
                scrollController: _scroll,
                isLoadingOlder: threadState.isLoadingOlder,
                reachedStart: threadState.reachedStart,
                onTapFailed: (clientMsgId) => unawaited(_handleFailedTap(clientMsgId)),
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
            onSend: _send,
            onChanged: _onComposerChanged,
          ),
        ],
      ),
    );
  }
}

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
    required this.onSend,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Key fieldKey;
  final Key sendKey;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
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
      ),
    );
  }
}

enum _FailedMessageAction { retry, discard }
