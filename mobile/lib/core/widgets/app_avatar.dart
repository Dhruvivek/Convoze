import 'package:flutter/material.dart';

/// A circular initials avatar. The color is derived deterministically from
/// [seed] (a stable id), so the same person always gets the same color
/// across every screen that shows them.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.label, required this.seed, this.size = 44, this.avatarUrl});

  /// The name (or masked-phone fallback) initials are derived from.
  final String label;

  /// A stable identifier — a user or conversation id — used to pick a color.
  final String seed;

  final double size;

  /// A User's real avatar (#43), shown in place of initials when present.
  /// Falls back to initials on a load error (offline, a stale/expired URL,
  /// ...) rather than a broken-image glyph.
  final String? avatarUrl;

  static const _palette = [
    Color(0xFF0E8C82),
    Color(0xFF3A6EA5),
    Color(0xFFB5533C),
    Color(0xFF6B5CA5),
    Color(0xFF9C7A1E),
    Color(0xFF4E7A3D),
  ];

  String get _initials {
    final trimmed = label.trim();
    if (trimmed.isEmpty) return '?';
    if (trimmed.startsWith('•')) {
      final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
      return digits.isEmpty ? '?' : digits.substring(digits.length - 1);
    }
    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  Color get _color => _palette[seed.hashCode.abs() % _palette.length];

  Widget _initialsAvatar(BuildContext context) {
    final color = _color;
    // The palette is fixed, but a flat 16% tint reads muddy on a dark
    // surface — richer background + a lightened glyph keep it vivid there.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Color.lerp(color, Colors.white, 0.35)! : color;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: isDark ? 0.28 : 0.16),
      child: Text(
        _initials,
        style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    if (url == null || url.isEmpty) return _initialsAvatar(context);
    return ClipOval(
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _initialsAvatar(context),
      ),
    );
  }
}
