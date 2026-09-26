import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/auth_scaffold.dart';
import '../../../core/widgets/loading_filled_button.dart';
import 'auth_failure_message.dart';
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
    if (number.length < 7) {
      setState(() => _error = "That doesn't look like a complete phone number.");
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
    } catch (e) {
      if (mounted) setState(() => _error = authFailureMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Sign in',
      headline: "What's your number?",
      children: [
        Text(
          "We'll text you a code to sign in — no password to remember.",
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
                decoration: const InputDecoration(labelText: 'Code', prefixText: '+'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: TextField(
                key: PhoneEntryScreen.numberFieldKey,
                controller: _number,
                keyboardType: TextInputType.phone,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Phone number'),
                onSubmitted: (_) => _sendCode(),
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        LoadingFilledButton(label: 'Send code', loading: _sending, onPressed: _sendCode),
      ],
    );
  }
}
