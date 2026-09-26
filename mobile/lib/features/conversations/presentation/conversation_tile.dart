import 'package:flutter/material.dart';

import '../../../core/formatting/relative_time.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/conversation_list_item.dart';

/// One conversation row. Presence and "typing…" aren't rendered here: #21
/// (realtime presence & typing) hasn't shipped yet, so there's no provider
/// to read them from — a deliberate, temporary gap, not an oversight.
class ConversationTile extends StatelessWidget {
  const ConversationTile({
    super.key,
    required this.item,
    required this.onTap,
    this.onLongPress,
    this.onSwipeTogglePin,
    this.onSwipeToggleArchive,
  });

  final ConversationListItem item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Swipe right-to-left toggles pin, left-to-right toggles archive (#45).
  /// Null on screens where that gesture doesn't apply (e.g. search results).
  final VoidCallback? onSwipeTogglePin;
  final VoidCallback? onSwipeToggleArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = item.unreadCount > 0;
    final label = StringBuffer(item.title)
      ..write(unread ? ', ${item.unreadCount} unread' : '')
      ..write(item.pinned ? ', pinned' : '')
      ..write(item.muted ? ', muted' : '')
      ..write(item.left ? ', left' : '')
      ..write(item.previewText.isEmpty ? '' : ', ${item.previewText}');

    final row = Opacity(
      // A left Conversation stays, dimmed, rather than disappearing (#52).
      opacity: item.left ? 0.5 : 1,
      child: Semantics(
        button: true,
        label: label.toString(),
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: theme.colorScheme.primary.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                AppAvatar(label: item.title, seed: item.avatarSeed, size: 48),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: theme.textTheme.titleMedium,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (item.muted) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.notifications_off,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                          if (item.pinned) ...[
                            const SizedBox(width: AppSpacing.xs),
                            Icon(
                              Icons.push_pin,
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                          if (item.lastMessageAt != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              relativeTime(item.lastMessageAt!),
                              // Accent the timestamp on unread rows so it reads
                              // as a signal, not just flat metadata gray.
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: unread
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.previewText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: unread
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurfaceVariant,
                                fontWeight: unread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: AppSpacing.sm),
                            _UnreadBadge(
                              count: item.unreadCount,
                              muted: item.muted,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (onSwipeTogglePin == null && onSwipeToggleArchive == null) return row;

    return Dismissible(
      key: ValueKey(item.id),
      // Neither gesture removes the row itself — the underlying stream drops
      // it from this list on its next emission once the toggle lands.
      confirmDismiss: (direction) async {
        switch (direction) {
          case DismissDirection.startToEnd:
            onSwipeTogglePin?.call();
          case DismissDirection.endToStart:
            onSwipeToggleArchive?.call();
          default:
            break;
        }
        return false;
      },
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        icon: Icons.push_pin,
        color: theme.colorScheme.primaryContainer,
        iconColor: theme.colorScheme.onPrimaryContainer,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        icon: Icons.archive,
        color: theme.colorScheme.secondaryContainer,
        iconColor: theme.colorScheme.onSecondaryContainer,
      ),
      child: row,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.icon,
    required this.color,
    required this.iconColor,
  });

  final Alignment alignment;
  final IconData icon;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Icon(icon, color: iconColor),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count, required this.muted});

  final int count;

  /// Grey rather than the accent color while muted (#45: "a grey unread
  /// count"), so a muted chat still shows activity without demanding
  /// attention the way an unmuted badge does.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = muted ? scheme.surfaceContainerHighest : scheme.primary;
    final foreground = muted ? scheme.onSurfaceVariant : scheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      constraints: const BoxConstraints(minWidth: 20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: foreground,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
