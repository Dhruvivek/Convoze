import 'package:convoze/features/presence/data/presence_state.dart';
import 'package:convoze/features/presence/presence_label.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 1, 5, 20, 0);

  test('online', () {
    expect(presenceLabel(const PresenceOnline(), now: now), 'online');
  });

  test('unknown is empty, so a caller can decide how to show it', () {
    expect(presenceLabel(const PresenceUnknown(), now: now), '');
  });

  test('today shows the time, 24-hour', () {
    final time = DateTime.utc(2026, 1, 5, 14, 5);
    expect(presenceLabel(PresenceLastSeen(time), now: now), 'last seen today at 14:05');
  });

  test('yesterday, regardless of time of day', () {
    final time = DateTime.utc(2026, 1, 4, 9, 0);
    expect(presenceLabel(PresenceLastSeen(time), now: now), 'last seen yesterday');
  });

  test('older than yesterday shows a date, not a time', () {
    final time = DateTime.utc(2025, 12, 1, 10, 0);
    expect(presenceLabel(PresenceLastSeen(time), now: now), 'last seen Dec 1');
  });
}
