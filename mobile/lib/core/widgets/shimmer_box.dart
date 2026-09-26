import 'package:flutter/material.dart';

/// A pulsing placeholder rectangle for skeleton loading states. Falls back
/// to a static box when the platform has "reduce motion" enabled.
class ShimmerBox extends StatefulWidget {
  const ShimmerBox({super.key, required this.width, required this.height, this.borderRadius = 8});

  final double width;
  final double height;
  final double borderRadius;

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHighest;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    Widget box(double opacity) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
    );

    if (reduceMotion) return box(0.7);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => box(0.5 + _controller.value * 0.3),
    );
  }
}
