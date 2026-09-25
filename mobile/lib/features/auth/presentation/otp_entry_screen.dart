import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

class OtpEntryScreen extends ConsumerStatefulWidget {
  const OtpEntryScreen({super.key, required this.phoneNumber});

  static const codeFieldKey = ValueKey('otpCodeField');

  final String phoneNumber;

  @override
  ConsumerState<OtpEntryScreen> createState() => _OtpEntryScreenState();
}

class _OtpEntryScreenState extends ConsumerState<OtpEntryScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      // On success the router sees the auth state flip and shows
      // conversations; nothing to navigate here.
      await ref
          .read(authStateProvider.notifier)
          .verifyOtp(widget.phoneNumber, code);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "That code didn't work. Try again.");
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter code')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('We texted a code to ${widget.phoneNumber}.'),
            const SizedBox(height: 16),
            TextField(
              key: OtpEntryScreen.codeFieldKey,
              controller: _code,
              keyboardType: TextInputType.number,
              autofocus: true,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(labelText: 'Code'),
              onSubmitted: (_) => _verify(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: const Text('Verify'),
            ),
          ],
        ),
      ),
    );
  }
}
