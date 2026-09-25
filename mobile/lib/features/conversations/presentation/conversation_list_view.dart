import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/conversation_list_item.dart';
import '../data/conversation_prefs_repository.dart';
import 'conversation_action_sheet.dart';
import 'conversation_prefs_action.dart';
import 'conversation_tile.dart';

/// The tappable/long-press/swipe-able list of [items], shared by the main
/// Chats tab and the Archived screen (#45) so pin/mute/archive/clear/delete
/// wiring exists in exactly one place.
class ConversationListView extends ConsumerWidget {
  const ConversationListView({super.key, required this.items});

  final List<ConversationListItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.read(conversationPrefsRepositoryProvider);

    Future<void> run(Future<void> Function() action) =>
        runConversationPrefsAction(context, ref, action);

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: items.length,
      separatorBuilder: (context, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final item = items[index];
        void togglePin() =>
            run(() => item.pinned ? prefs.unpin(item.id) : prefs.pin(item.id));
        void toggleArchive() => run(
          () =>
              item.archived ? prefs.unarchive(item.id) : prefs.archive(item.id),
        );

        return ConversationTile(
          item: item,
          onTap: () => context.push('/thread/${item.id}', extra: item.title),
          onLongPress: () => showConversationActions(
            context,
            conversation: item,
            onTogglePin: togglePin,
            onMute: (duration) => run(() => prefs.mute(item.id, duration)),
            onUnmute: () => run(() => prefs.unmute(item.id)),
            onToggleArchive: toggleArchive,
            onClear: () => run(() => prefs.clear(item.id)),
            onDelete: () => run(() => prefs.delete(item.id)),
          ),
          onSwipeTogglePin: togglePin,
          onSwipeToggleArchive: toggleArchive,
        );
      },
    );
  }
}
