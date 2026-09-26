import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import 'app_mark.dart';

/// Shared shell for the phone-entry and OTP screens: app bar, a brand mark,
/// and a scrollable body so content never gets clipped by the keyboard on a
/// small phone. Keeping this in one place means the two auth screens can't
/// drift apart in spacing or layout as they change.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.headline,
    required this.children,
  });

  final String title;
  final String headline;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppMark(size: 36),
              const SizedBox(height: AppSpacing.xxl),
              Text(headline, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.lg),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
