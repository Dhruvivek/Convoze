import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'contact_picker_list.dart';

/// The Contacts tab: browse mock contacts, tap one to open a chat.
class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ContactPickerList(
      autofocus: false,
      onSelect: (id, name) => context.push('/thread/$id', extra: name),
    );
  }
}
