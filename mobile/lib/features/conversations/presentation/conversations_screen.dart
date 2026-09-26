import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/shimmer_box.dart';
import '../data/conversations_repository.dart';
import 'conversation_list_view.dart';

/// The Chats tab body: loading/empty/error/populated states for the real,
/// replica-backed conversation list (#52) — reads only from the Local
/// replica (#51), so it shows immediately, even offline. The app bar,
/// search action, and FAB live in the signed-in shell (`HomeShell`), not
/// here, since they're shared chrome around every tab.
class ConversationsTabBody extends ConsumerWidget {
  const ConversationsTabBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final itemsAsync = ref.watch(conversationListProvider());
    final archivedItems =
        ref.watch(conversationListProvider(archived: true)).value ?? const [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Conversations', style: theme.textTheme.titleLarge),
          ),
        ),
        Expanded(
          child: itemsAsync.when(
            loading: () => const _ConversationsLoading(),
            error: (error, stackTrace) => _ConversationsError(
              onRetry: () => ref.invalidate(conversationListProvider),
            ),
            data: (items) => Column(
              children: [
                // Shown regardless of whether the main list is empty, so
                // archived-only users still have a way to reach it (#45).
                if (archivedItems.isNotEmpty)
                  _ArchivedSummaryRow(
                    unreadCount: archivedItems
                        .where((i) => i.unreadCount > 0)
                        .length,
                    onTap: () => context.push('/archived'),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? _ConversationsEmpty(onStart: () => context.push('/new'))
                      : ConversationListView(items: items),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ArchivedSummaryRow extends StatelessWidget {
  const _ArchivedSummaryRow({required this.unreadCount, required this.onTap});

  final int unreadCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archived'),
          trailing: unreadCount > 0 ? Text('$unreadCount') : null,
          onTap: onTap,
        ),
        const Divider(height: 1, indent: 76),
      ],
    );
  }
}

class _ConversationsLoading extends StatelessWidget {
  const _ConversationsLoading();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      itemCount: 6,
      separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, _) => const Row(
        children: [
          ShimmerBox(width: 48, height: 48, borderRadius: 24),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 140, height: 14),
                SizedBox(height: 8),
                ShimmerBox(width: 220, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationsEmpty extends StatelessWidget {
  const _ConversationsEmpty({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No chats yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'When you start a conversation, it will show up here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onStart, child: const Text('New chat')),
          ],
        ),
      ),
    );
  }
}

class _ConversationsError extends StatelessWidget {
  const _ConversationsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 32,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Couldn't load your conversations",
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Check your connection and try again.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
