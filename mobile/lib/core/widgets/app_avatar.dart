import 'package:flutter/material.dart';

/// A circular initials avatar. The color is derived deterministically from
/// [seed] (a stable id), so the same person always gets the same color
/// across every screen that shows them.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.label, required this.seed, this.size = 44});

  /// The name (or masked-phone fallback) initials are derived from.
  final String label;

  /// A stable identifier — a user or conversation id — used to pick a color.
  final String seed;

  final double size;

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

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.16),
      child: Text(
        _initials,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }
}
