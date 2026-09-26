import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../realtime/connection_manager.dart';

/// A non-blocking "Connecting…" banner for the signed-in shell: shown while
/// the live connection is being opened or is retrying after a drop, hidden
/// once it's up. Not shown for [ConnectionStatus.offline] — that also covers
/// a deliberate background disconnect, which isn't something to alarm the
/// user with since there's no screen to show it on anyway.
class ConnectingBanner extends ConsumerWidget {
  const ConnectingBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectionStatusProvider).value;
    final show = status == ConnectionStatus.connecting || status == ConnectionStatus.reconnecting;
    if (!show) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Connecting…',
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
