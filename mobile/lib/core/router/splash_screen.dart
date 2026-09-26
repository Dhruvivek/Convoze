import 'package:flutter/material.dart';

import '../widgets/app_mark.dart';

/// Shown on a cold start while stored tokens are read, so neither the login
/// screen nor conversations flash up before it's known which one applies.
/// The read is normally too quick for this to be seen at all, so it's kept
/// to just the brand mark rather than any loading chrome.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Theme.of(context).colorScheme.surface,
    body: const Center(child: AppMark(size: 40)),
  );
}
