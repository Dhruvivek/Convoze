import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// In-memory only for now, not yet persisted across restarts. Swap these
/// notifier bodies for reads/writes to local storage (or synced profile
/// preferences, once that's wired up) without touching the settings screen
/// that watches them.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final notificationsEnabledProvider = NotifierProvider<NotificationsEnabledNotifier, bool>(
  NotificationsEnabledNotifier.new,
);

class NotificationsEnabledNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}
