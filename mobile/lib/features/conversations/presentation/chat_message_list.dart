import 'package:flutter/material.dart';

import '../data/chat_message_view.dart';

/// The chat screen's message list (#53/#55): a reversed [ListView] of
/// day-separated [ChatMessageView]s, with a "beginning of conversation"
/// marker or a loading row at the top slot.
class MessageList extends StatelessWidget {
  const MessageList({
    super.key,
    required this.views,
    required this.scrollController,
    required this.isLoadingOlder,
    required this.reachedStart,
    this.onTapFailed,
  });

  final List<ChatMessageView> views;
  final ScrollController scrollController;
  final bool isLoadingOlder;
  final bool reachedStart;

  /// Called with a failed Outbox row's `clientMsgId` when its bubble is
  /// tapped ("failed — tap to retry or delete", ADR 0009).
  final void Function(String clientMsgId)? onTapFailed;

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
          _MessageRow(:final view) => _MessageBubble(view: view, onTapFailed: onTapFailed),
        };
      },
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
  const _MessageBubble({required this.view, this.onTapFailed});

  final ChatMessageView view;
  final void Function(String clientMsgId)? onTapFailed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = view.fromMe;
    final failed = view.tick == MessageTick.failed;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        child: GestureDetector(
          onTap: failed && view.clientMsgId != null
              ? () => onTapFailed?.call(view.clientMsgId!)
              : null,
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
                  children: failed
                      ? [
                          Text(
                            'Failed — tap to retry or delete',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                          const SizedBox(width: 4),
                          _TickIcon(tick: MessageTick.failed, onPrimary: mine),
                        ]
                      : [
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
