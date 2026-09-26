import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/realtime/connection_manager.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/settings/data/app_preferences.dart';

class ConvozeApp extends ConsumerWidget {
  const ConvozeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    // Starts the live connection, which follows the auth state from then on.
    ref.watch(connectionManagerProvider);

    return MaterialApp.router(
      title: 'Convoze',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
