import 'package:flutter/material.dart';

import '../../auth/presentation/account_menu.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversations'),
        actions: const [AccountMenu()],
      ),
      body: const Center(child: Text('No conversations yet')),
    );
  }
}
