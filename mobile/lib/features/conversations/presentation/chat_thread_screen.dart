import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/chat_message_view.dart';
import '../data/messages_repository.dart';
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

  static const _loadOlderThreshold = 200.0;

  @override
  void initState() {
    super.initState();
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
    await ref.read(messagesRepositoryProvider).send(widget.conversationId, text);
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
              AsyncData(:final value) => _MessageList(
                views: value,
                scrollController: _scroll,
                isLoadingOlder: threadState.isLoadingOlder,
                reachedStart: threadState.reachedStart,
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
          ),
        ],
      ),
    );
  }
}

sealed class _ThreadRow {
  const _ThreadRow();
}

class _DateRow extends _ThreadRow {
  const _DateRow(this.day);
  final DateTime day;
}

class _MessageRow extends _ThreadRow {
  const _MessageRow(this.view);
  final ChatMessageView view;
}

List<_ThreadRow> _buildRows(List<ChatMessageView> views) {
  final rows = <_ThreadRow>[];
  DateTime? lastDay;
  for (final view in views) {
    final createdAt = view.createdAt.toLocal();
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    if (lastDay == null || day != lastDay) {
      rows.add(_DateRow(day));
      lastDay = day;
    }
    rows.add(_MessageRow(view));
  }
  return rows;
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.views,
    required this.scrollController,
    required this.isLoadingOlder,
    required this.reachedStart,
  });

  final List<ChatMessageView> views;
  final ScrollController scrollController;
  final bool isLoadingOlder;
  final bool reachedStart;

  @override
  Widget build(BuildContext context) {
    final rows = _buildRows(views);
    if (rows.isEmpty) {
      return isLoadingOlder
          ? const Center(child: CircularProgressIndicator())
          : const Center(child: Text('Say hi 👋'));
    }

    final hasTopSlot = reachedStart || isLoadingOlder;
    return ListView.builder(
      controller: scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: rows.length + (hasTopSlot ? 1 : 0),
      itemBuilder: (context, index) {
        if (hasTopSlot && index == rows.length) {
          return reachedStart
              ? const _BeginningOfConversation()
              : const _LoadingOlderIndicator();
        }
        final row = rows[rows.length - 1 - index];
        return switch (row) {
          _DateRow(:final day) => _DateSeparator(day: day),
          _MessageRow(:final view) => _MessageBubble(view: view),
        };
      },
    );
  }
}

class _BeginningOfConversation extends StatelessWidget {
  const _BeginningOfConversation();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: Text(
          'Beginning of conversation',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _LoadingOlderIndicator extends StatelessWidget {
  const _LoadingOlderIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_dayLabel(day), style: Theme.of(context).textTheme.labelSmall),
        ),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _dayLabel(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return 'Today';
  if (day == yesterday) return 'Yesterday';
  return '${_months[day.month - 1]} ${day.day}, ${day.year}';
}

String _timeLabel(DateTime utc) {
  final local = utc.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return '$hour12:$minute $period';
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.view});

  final ChatMessageView view;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = view.fromMe;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: view.isDeleted
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : mine
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                view.isDeleted
                    ? 'This message was deleted'
                    : (view.content ?? ''),
                style: TextStyle(
                  color: view.isDeleted
                      ? scheme.onSurfaceVariant
                      : mine
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                  fontStyle: view.isDeleted ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _timeLabel(view.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: mine
                          ? scheme.onPrimary.withValues(alpha: 0.7)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                  if (view.tick != null) ...[
                    const SizedBox(width: 4),
                    _TickIcon(tick: view.tick!, onPrimary: mine),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TickIcon extends StatelessWidget {
  const _TickIcon({required this.tick, required this.onPrimary});

  final MessageTick tick;
  final bool onPrimary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseColor = onPrimary
        ? scheme.onPrimary.withValues(alpha: 0.7)
        : scheme.onSurfaceVariant;
    final (icon, color) = switch (tick) {
      MessageTick.clock => (Icons.access_time, baseColor),
      MessageTick.failed => (Icons.error_outline, scheme.error),
      MessageTick.sent => (Icons.check, baseColor),
      MessageTick.delivered => (Icons.done_all, baseColor),
      MessageTick.read => (Icons.done_all, scheme.tertiary),
    };
    return Icon(icon, size: 14, color: color);
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
  });

  final TextEditingController controller;
  final Key fieldKey;
  final Key sendKey;
  final VoidCallback onSend;

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
