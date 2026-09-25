import 'package:flutter/material.dart';

/// Shown on a cold start while stored tokens are read, so neither the login
/// screen nor conversations flash up before it's known which one applies.
/// Deliberately blank: the read is too quick for anything here to be seen.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold();
}
