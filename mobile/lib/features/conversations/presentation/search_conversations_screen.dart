import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/conversation_list_item.dart';
import '../data/conversations_repository.dart';
import 'conversation_tile.dart';

class SearchConversationsScreen extends ConsumerStatefulWidget {
  const SearchConversationsScreen({super.key});

  @override
  ConsumerState<SearchConversationsScreen> createState() =>
      _SearchConversationsScreenState();
}

class _SearchConversationsScreenState
    extends ConsumerState<SearchConversationsScreen> {
  final _query = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversations =
        ref.watch(conversationListProvider()).value ??
        const <ConversationListItem>[];
    final filter = _filter.toLowerCase();
    final results = filter.isEmpty
        ? const <ConversationListItem>[]
        : conversations
              .where(
                (c) =>
                    c.title.toLowerCase().contains(filter) ||
                    c.previewText.toLowerCase().contains(filter),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _query,
          autofocus: true,
          onChanged: (value) => setState(() => _filter = value),
          decoration: const InputDecoration(
            hintText: 'Search conversations',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
          ),
        ),
      ),
      body: _filter.isEmpty
          ? Center(
              child: Text(
                'Search by name or message',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : results.isEmpty
          ? Center(
              child: Text(
                'No results for "$_filter"',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          : ListView.separated(
              itemCount: results.length,
              separatorBuilder: (context, _) =>
                  const Divider(height: 1, indent: 76),
              itemBuilder: (context, index) {
                final conversation = results[index];
                return ConversationTile(
                  item: conversation,
                  onTap: () => context.pushReplacement(
                    '/thread/${conversation.id}',
                    extra: conversation.title,
                  ),
                );
              },
            ),
    );
  }
}
