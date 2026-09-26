import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/contacts_repository.dart';
import '../data/conversations_repository.dart';
import 'conversations_failure_message.dart';

/// The contact list + search shared by the full-screen "New conversation"
/// picker and the persistent Contacts tab, so the two don't duplicate the
/// same list-building logic. Backed by every other User on Convoze
/// (`GET /users`); picking one opens (or creates) the direct Conversation
/// with them and hands its id to [onSelect].
class ContactPickerList extends ConsumerStatefulWidget {
  const ContactPickerList({super.key, this.autofocus = true, required this.onSelect});

  final bool autofocus;
  final void Function(String conversationId, String name) onSelect;

  @override
  ConsumerState<ContactPickerList> createState() => _ContactPickerListState();
}

class _ContactPickerListState extends ConsumerState<ContactPickerList> {
  final _query = TextEditingController();
  String _filter = '';
  String? _openingUserId;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _select(String userId, String name) async {
    if (_openingUserId != null) return;
    setState(() => _openingUserId = userId);
    try {
      final conversationId = await ref.read(conversationsRepositoryProvider).openDirect(userId);
      if (!mounted) return;
      widget.onSelect(conversationId, name);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(conversationsFailureMessage(err))));
    } finally {
      if (mounted) setState(() => _openingUserId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: TextField(
            controller: _query,
            autofocus: widget.autofocus,
            onChanged: (value) => setState(() => _filter = value),
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
          ),
        ),
        Expanded(
          child: switch (contactsAsync) {
            AsyncData(:final value) => _buildList(value),
            AsyncError() => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Couldn't load contacts.",
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  TextButton(
                    onPressed: () => ref.invalidate(contactsProvider),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  Widget _buildList(List<User> users) {
    final query = _filter.trim().toLowerCase();
    final contacts = users.where((u) {
      final name = displayName(displayName: u.displayName, phoneNumber: u.phoneNumber);
      return query.isEmpty ||
          name.toLowerCase().contains(query) ||
          u.phoneNumber.toLowerCase().contains(query);
    }).toList();

    if (contacts.isEmpty) {
      return Center(
        child: Text(
          'No one matches "$_filter"',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (context, _) => const Divider(height: 1, indent: 76),
      itemBuilder: (context, index) {
        final user = contacts[index];
        final name = displayName(displayName: user.displayName, phoneNumber: user.phoneNumber);
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          leading: AppAvatar(label: name, seed: user.id, size: 44),
          title: Text(name),
          trailing: _openingUserId == user.id
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          onTap: () => _select(user.id, name),
        );
      },
    );
  }
}
