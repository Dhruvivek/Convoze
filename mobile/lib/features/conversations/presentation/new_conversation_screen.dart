import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'contact_picker_list.dart';

/// The FAB's "compose" flow: full-screen contact picker. Choosing someone
/// opens a chat thread with them. Not wired to a real contacts/backend
/// source yet.
class NewConversationScreen extends StatelessWidget {
  const NewConversationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: ContactPickerList(
        onSelect: (id, name) => context.pushReplacement('/thread/$id', extra: name),
      ),
    );
  }
}
