import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_avatar.dart';
import '../data/mock_contacts.dart';

/// The contact list + search shared by the full-screen "New conversation"
/// picker and the persistent Contacts tab, so the two don't duplicate the
/// same list-building logic.
class ContactPickerList extends StatefulWidget {
  const ContactPickerList({super.key, this.autofocus = true, required this.onSelect});

  final bool autofocus;
  final void Function(String id, String name) onSelect;

  @override
  State<ContactPickerList> createState() => _ContactPickerListState();
}

class _ContactPickerListState extends State<ContactPickerList> {
  final _query = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = mockContacts
        .where((c) => c.$2.toLowerCase().contains(_filter.toLowerCase()))
        .toList();

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
          child: contacts.isEmpty
              ? Center(
                  child: Text(
                    'No one matches "$_filter"',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                )
              : ListView.separated(
                  itemCount: contacts.length,
                  separatorBuilder: (context, _) => const Divider(height: 1, indent: 76),
                  itemBuilder: (context, index) {
                    final (id, name) = contacts[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      leading: AppAvatar(label: name, seed: id, size: 44),
                      title: Text(name),
                      onTap: () => widget.onSelect(id, name),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
