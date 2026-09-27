import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatting/display_name.dart';
import '../../../core/models/user.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/contacts_repository.dart';
import '../data/conversations_repository.dart';
import '../data/device_contacts_service.dart';
import 'contacts_failure_message.dart';
import 'conversations_failure_message.dart';
import 'find_by_phone_number_sheet.dart';

/// The contact list + search shared by the full-screen "New conversation"
/// picker and the persistent Contacts tab, so the two don't duplicate the
/// same list-building logic. Backed by whichever Device contacts are also
/// registered on Convoze (`POST /users/match`, #101); a pinned row above the
/// list can also find someone by exact phone number for a contact that
/// isn't saved. Picking someone opens (or creates) the direct Conversation
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

  Future<void> _findByPhoneNumber() async {
    final found = await showModalBottomSheet<User>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const FindByPhoneNumberSheet(),
    );
    if (found == null || !mounted) return;
    final name = displayName(displayName: found.displayName, phoneNumber: found.phoneNumber);
    _select(found.id, name);
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
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.dialpad)),
          title: const Text('New chat via phone number'),
          onTap: _findByPhoneNumber,
        ),
        const Divider(height: 1, indent: 76),
        Expanded(
          child: switch (contactsAsync) {
            AsyncData(:final value) => _buildList(value),
            AsyncError(:final error) => _buildError(error),
            _ => const Center(child: CircularProgressIndicator()),
          },
        ),
      ],
    );
  }

  Widget _buildError(Object error) {
    if (error is ContactsPermissionException) {
      return _PermissionGate(permanentlyDenied: error.permanentlyDenied);
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(contactsFailureMessage(error), style: Theme.of(context).textTheme.bodyMedium),
          TextButton(
            onPressed: () => ref.invalidate(contactsProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
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
      if (_filter.trim().isEmpty) {
        return Center(
          child: Text(
            "None of your contacts are on Convoze yet.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        );
      }
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

/// Shown in place of the list while Contacts access hasn't been granted.
/// [permanentlyDenied] switches the recovery action from "ask again" (the
/// system dialog can still appear) to "open Settings" (it can't).
class _PermissionGate extends ConsumerWidget {
  const _PermissionGate({required this.permanentlyDenied});

  final bool permanentlyDenied;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_outlined, size: 40),
            const SizedBox(height: AppSpacing.md),
            Text(
              "Convoze needs access to your contacts to show who's already here.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: permanentlyDenied
                  ? () => ref.read(deviceContactsServiceProvider).openSettings()
                  : () => ref.invalidate(contactsProvider),
              child: Text(permanentlyDenied ? 'Open settings' : 'Allow access'),
            ),
          ],
        ),
      ),
    );
  }
}
