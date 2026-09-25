import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../data/conversation_prefs_repository.dart';

/// The mute-duration picker (#45): 8 hours, 1 week or always, plus an
/// "Unmute" row when the conversation is already muted. Mirrors
/// `conversation_action_sheet.dart`'s bottom-sheet idiom.
Future<void> showMuteDurationSheet(
  BuildContext context, {
  required bool alreadyMuted,
  DateTime? mutedUntil,
  required void Function(MuteDuration duration) onMute,
  required VoidCallback onUnmute,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Mute for…',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('8 hours'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onMute(MuteDuration.eightHours);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('1 week'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onMute(MuteDuration.oneWeek);
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_off_outlined),
            title: const Text('Always'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onMute(MuteDuration.always);
            },
          ),
          if (alreadyMuted) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Unmute'),
              subtitle: mutedUntil == null
                  ? null
                  : Text(_mutedUntilLabel(mutedUntil)),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onUnmute();
              },
            ),
          ],
        ],
      ),
    ),
  );
}

/// "Muted until <time>" (#45 story 14). The far-future sentinel the backend
/// stores for "always" reads as "Always" rather than a nonsense date.
String _mutedUntilLabel(DateTime mutedUntil) {
  if (mutedUntil.year >= 9999) return 'Muted until you unmute it';
  final local = mutedUntil.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';
  return 'Muted until ${_month[local.month - 1]} ${local.day}, $hour:$minute $period';
}

const _month = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
