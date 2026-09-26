import 'package:flutter/material.dart';

/// The Convoze brand mark: a filled bubble glyph, optionally paired with the
/// wordmark. Used wherever the app needs to assert its identity — the auth
/// screens and the splash screen currently have none of this at all.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 40, this.showWordmark = true});

  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glyph = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.forum_rounded, color: scheme.onPrimary, size: size * 0.56),
    );
    if (!showWordmark) return glyph;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        glyph,
        SizedBox(width: size * 0.3),
        Text(
          'Convoze',
          style: TextStyle(
            fontSize: size * 0.5,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}
