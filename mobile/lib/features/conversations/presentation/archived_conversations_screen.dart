import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/conversations_repository.dart';
import 'conversation_list_view.dart';

/// The Archived section (#45): the same list rendering as the main Chats
/// tab, filtered to archived conversations, with unarchive available the
/// same way (long-press or swipe).
class ArchivedConversationsScreen extends ConsumerWidget {
  const ArchivedConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(conversationListProvider(archived: true));
    return Scaffold(
      appBar: AppBar(title: const Text('Archived')),
      body: itemsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            "Couldn't load archived chats.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Text(
                  'No archived chats',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              )
            : ConversationListView(items: items),
      ),
    );
  }
}
