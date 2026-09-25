import 'data/presence_state.dart';

/// Renders a [PresenceState] as "online", "last seen today at 14:05", "last
/// seen yesterday", or "last seen Jan 3" (#34) — every surface that shows a
/// User's presence goes through this rather than formatting it itself.
/// Empty for [PresenceUnknown], so a caller can decide whether to hide the
/// row entirely or show a neutral placeholder.
String presenceLabel(PresenceState state, {DateTime? now}) {
  return switch (state) {
    PresenceOnline() => 'online',
    PresenceUnknown() => '',
    PresenceLastSeen(:final time) => 'last seen ${_when(time, now ?? DateTime.now())}',
  };
}

String _when(DateTime utc, DateTime reference) {
  final time = utc.toLocal();
  final now = reference.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  if (day == today) return 'today at ${_timeOfDay(time)}';
  if (day == today.subtract(const Duration(days: 1))) return 'yesterday';
  return _dateLabel(day);
}

const _months = [
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

String _dateLabel(DateTime day) => '${_months[day.month - 1]} ${day.day}';

// 24-hour, matching the spec's own example ("last seen today at 14:05").
String _timeOfDay(DateTime local) {
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
