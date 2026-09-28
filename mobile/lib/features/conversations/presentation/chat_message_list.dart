import 'package:flutter/material.dart';

import '../data/chat_message_view.dart';
import 'media_viewer.dart';

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
    required this.keyFor,
    this.onTapFailed,
    this.onLongPress,
    this.onReplyTap,
    this.onReactionTap,
  });

  final List<ChatMessageView> views;
  final ScrollController scrollController;
  final bool isLoadingOlder;
  final bool reachedStart;

  /// A stable [GlobalKey] per Message id (#102's "tap the quote to scroll to
  /// the original"): the screen owns these across rebuilds so
  /// `Scrollable.ensureVisible` can resolve a target bubble's context.
  final Key Function(String messageId) keyFor;

  /// Called with a failed Outbox row's `clientMsgId` when its bubble is
  /// tapped ("failed — tap to retry or delete", ADR 0009).
  final void Function(String clientMsgId)? onTapFailed;

  /// Called on a bubble long-press, e.g. to open `showMessageActions` (#56).
  final void Function(ChatMessageView view)? onLongPress;

  /// Called with the original Message's id when a reply's quoted preview is
  /// tapped (#102).
  final void Function(String targetMessageId)? onReplyTap;

  /// Called with a reaction pill's emoji when tapped, to toggle it (#103).
  final void Function(ChatMessageView view, String emoji)? onReactionTap;

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
          _MessageRow(:final view) => _MessageBubble(
            key: keyFor(view.id),
            view: view,
            onTapFailed: onTapFailed,
            onLongPress: onLongPress == null ? null : () => onLongPress!(view),
            onReplyTap: onReplyTap,
            onReactionTap: onReactionTap == null ? null : (emoji) => onReactionTap!(view, emoji),
          ),
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
  const _MessageBubble({
    super.key,
    required this.view,
    this.onTapFailed,
    this.onLongPress,
    this.onReplyTap,
    this.onReactionTap,
  });

  final ChatMessageView view;
  final void Function(String clientMsgId)? onTapFailed;
  final VoidCallback? onLongPress;
  final void Function(String targetMessageId)? onReplyTap;
  final void Function(String emoji)? onReactionTap;

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
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: failed && view.clientMsgId != null
                  ? () => onTapFailed?.call(view.clientMsgId!)
                  : null,
              onLongPress: view.isDeleted ? null : onLongPress,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: view.isImage && !view.isDeleted
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    if (view.isDeleted)
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else ...[
                      if (view.replyToMessageId != null)
                        _ReplyQuoteBlock(
                          view: view,
                          mine: mine,
                          onTap: onReplyTap == null
                              ? null
                              : () => onReplyTap!(view.replyToMessageId!),
                        ),
                      if (view.isImage)
                        _ImageContent(view: view, mine: mine)
                      else if (view.isFile)
                        _FileContent(view: view, mine: mine)
                      else ...[
                        Text(
                          view.content ?? '',
                          style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurfaceVariant),
                        ),
                        if (view.editedAt != null)
                          Text(
                            '(edited)',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: (mine ? scheme.onPrimary : scheme.onSurfaceVariant)
                                  .withValues(alpha: 0.65),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                      ],
                    ],
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
            if (!view.isDeleted)
              _ReactionsRow(view: view, onTap: onReactionTap),
          ],
        ),
      ),
    );
  }
}

class _ReplyQuoteBlock extends StatelessWidget {
  const _ReplyQuoteBlock({required this.view, required this.mine, this.onTap});

  final ChatMessageView view;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = mine ? scheme.onPrimary : scheme.onSurfaceVariant;
    final preview = view.replyPreview;
    return GestureDetector(
      onTap: preview == null ? null : onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: foreground.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: foreground.withValues(alpha: 0.6), width: 3)),
        ),
        child: Text(
          preview?.snippet ?? 'Message',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground.withValues(alpha: 0.85),
            fontSize: 13,
            fontStyle: (preview?.isDeleted ?? false) ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}

/// Reaction pills below a bubble (#103), grouped by emoji with a count;
/// tapping one toggles *this* User's own reaction with that emoji — it
/// doesn't matter who else already reacted with it.
class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.view, this.onTap});

  final ChatMessageView view;
  final void Function(String emoji)? onTap;

  @override
  Widget build(BuildContext context) {
    if (view.reactions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final counts = <String, int>{};
    for (final reaction in view.reactions) {
      counts[reaction.emoji] = (counts[reaction.emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final entry in counts.entries)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap == null ? null : () => onTap!(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: view.reactedByMeWith(entry.key)
                      ? scheme.primary.withValues(alpha: 0.18)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: view.reactedByMeWith(entry.key)
                      ? Border.all(color: scheme.primary, width: 1)
                      : null,
                ),
                child: Text('${entry.key} ${entry.value}', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageContent extends StatelessWidget {
  const _ImageContent({required this.view, required this.mine});

  final ChatMessageView view;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = mine ? scheme.onPrimary : scheme.onSurfaceVariant;
    final url = view.mediaThumbnailUrl ?? view.mediaUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: view.mediaUrl == null
                ? null
                : () => showMediaViewer(context, url: view.mediaUrl!),
            child: AspectRatio(
              aspectRatio: (view.mediaWidth != null && view.mediaHeight != null)
                  ? view.mediaWidth! / view.mediaHeight!
                  : 1,
              child: url == null
                  ? Container(color: Colors.black12, child: const Icon(Icons.image_outlined))
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image_outlined),
                    ),
            ),
          ),
        ),
        if ((view.content ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(view.content!, style: TextStyle(color: foreground)),
          ),
      ],
    );
  }
}

class _FileContent extends StatelessWidget {
  const _FileContent({required this.view, required this.mine});

  final ChatMessageView view;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = mine ? scheme.onPrimary : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.insert_drive_file_outlined, color: foreground),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                view.mediaFileName ?? 'Document',
                style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              if (view.mediaBytes != null)
                Text(
                  _humanSize(view.mediaBytes!),
                  style: TextStyle(color: foreground.withValues(alpha: 0.7), fontSize: 12),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _humanSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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
