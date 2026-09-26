/// A short relative label for a timestamp, e.g. `now`, `12m`, `3h`, `2d`, or
/// a `m/d` date once it's more than a week old.
String relativeTime(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return '${time.month}/${time.day}';
}
