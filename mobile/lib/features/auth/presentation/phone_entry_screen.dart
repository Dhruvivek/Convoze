import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_state.dart';

class PhoneEntryScreen extends ConsumerStatefulWidget {
  const PhoneEntryScreen({super.key});

  static const countryCodeFieldKey = ValueKey('countryCodeField');
  static const numberFieldKey = ValueKey('phoneNumberField');

  @override
  ConsumerState<PhoneEntryScreen> createState() => _PhoneEntryScreenState();
}

class _PhoneEntryScreenState extends ConsumerState<PhoneEntryScreen> {
  final _countryCode = TextEditingController(text: '1');
  final _number = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _countryCode.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final countryCode = _countryCode.text.trim();
    final number = _number.text.replaceAll(RegExp(r'\D'), '');
    if (countryCode.isEmpty || number.isEmpty) {
      setState(() => _error = 'Enter your country code and phone number');
      return;
    }
    // The backend normalises to E.164; it only needs the +country code.
    final phoneNumber = '+$countryCode$number';

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref.read(authStateProvider.notifier).requestOtp(phoneNumber);
      if (mounted) context.go('/login/otp', extra: phoneNumber);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = "Couldn't send a code. Check the number and try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text("Enter your phone number and we'll text you a code."),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 88,
                  child: TextField(
                    key: PhoneEntryScreen.countryCodeFieldKey,
                    controller: _countryCode,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      prefixText: '+',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    key: PhoneEntryScreen.numberFieldKey,
                    controller: _number,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                    onSubmitted: (_) => _sendCode(),
                  ),
                ),
              ],
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
              onPressed: _sending ? null : _sendCode,
              child: const Text('Send code'),
            ),
          ],
        ),
      ),
    );
  }
}
