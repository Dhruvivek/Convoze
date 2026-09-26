import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/connecting_banner.dart';
import '../../auth/presentation/logout_menu.dart';
import '../../conversations/presentation/conversations_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../settings/presentation/settings_screen.dart';

/// The signed-in app shell: bottom navigation across Chats, Profile, and
/// Settings, under one shared app bar (a constant "Convoze" title; the
/// overflow menu and — on Chats only — search and the compose FAB live
/// here too).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _openProfileTab() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Convoze'),
        actions: [
          if (_index == 0)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Search conversations',
              onPressed: () => context.push('/search'),
            ),
          const LogoutMenu(),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          const ConnectingBanner(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                const ConversationsTabBody(),
                const ProfileScreen(embedded: true),
                SettingsScreen(embedded: true, onOpenProfile: _openProfileTab),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton(
              onPressed: () => context.push('/new'),
              tooltip: 'New conversation',
              child: const Icon(Icons.edit_outlined),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
