import 'package:flutter/material.dart';

/// Full-screen photo view with pinch-zoom, via the framework's own
/// `InteractiveViewer` — a reasonable substitute for the `photo_view`
/// package in this reduced-scope pass of #40 (no extra dependency needed for
/// photos-only zoom).
Future<void> showMediaViewer(BuildContext context, {required String url}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Image.network(
              url,
              errorBuilder: (context, error, stackTrace) =>
                  const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 48),
            ),
          ),
        ),
      ),
    ),
  );
}
