import 'package:flutter/material.dart';

/// A [FilledButton] that shows an inline spinner while [loading]. The label
/// stays in the tree at zero opacity rather than being swapped out, so a
/// widget test that finds the button by its label keeps working whether or
/// not it's mid-submit.
class LoadingFilledButton extends StatelessWidget {
  const LoadingFilledButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: loading ? 0 : 1, child: Text(label)),
          if (loading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
        ],
      ),
    );
  }
}
