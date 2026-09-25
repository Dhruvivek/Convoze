import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_failure_message.dart';
import 'auth_state.dart';

class OtpEntryScreen extends ConsumerStatefulWidget {
  const OtpEntryScreen({super.key, required this.phoneNumber});

  static const codeFieldKey = ValueKey('otpCodeField');
  static const resendButtonKey = ValueKey('resendCodeButton');

  /// How long "Resend code" stays disabled after a code is sent, so a User
  /// can't burn through the backend's rate limit by tapping it.
  static const resendCooldown = Duration(seconds: 30);

  final String phoneNumber;

  @override
  ConsumerState<OtpEntryScreen> createState() => _OtpEntryScreenState();
}

class _OtpEntryScreenState extends ConsumerState<OtpEntryScreen> {
  final _code = TextEditingController();
  bool _verifying = false;
  String? _error;
  String? _notice;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    // The phone-entry screen sent a code just before showing this one.
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    _cooldownSeconds = OtpEntryScreen.resendCooldown.inSeconds;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _cooldownSeconds--);
      if (_cooldownSeconds == 0) timer.cancel();
    });
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _verifying = true;
      _error = null;
      _notice = null;
    });
    try {
      // On success the router sees the auth state flip and shows
      // conversations; nothing to navigate here.
      await ref
          .read(authStateProvider.notifier)
          .verifyOtp(widget.phoneNumber, code);
    } catch (e) {
      if (mounted) setState(() => _error = authFailureMessage(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    // Every attempt restarts the cooldown, successful or not.
    setState(() {
      _startCooldown();
      _error = null;
      _notice = null;
    });
    try {
      await ref.read(authStateProvider.notifier).requestOtp(widget.phoneNumber);
      if (mounted) setState(() => _notice = 'We texted you a new code.');
    } catch (e) {
      if (mounted) setState(() => _error = authFailureMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final coolingDown = _cooldownSeconds > 0;
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
            ] else if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_notice!),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _verifying ? null : _verify,
              child: const Text('Verify'),
            ),
            const SizedBox(height: 8),
            TextButton(
              key: OtpEntryScreen.resendButtonKey,
              onPressed: coolingDown ? null : _resend,
              child: Text(
                coolingDown
                    ? 'Resend code in ${_cooldownSeconds}s'
                    : 'Resend code',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
