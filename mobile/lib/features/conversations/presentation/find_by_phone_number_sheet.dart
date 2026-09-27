import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/loading_filled_button.dart';
import '../data/contacts_repository.dart';
import 'contacts_failure_message.dart';

/// The Telegram-style escape hatch from Contacts (#101): find one exact
/// registered User by phone number, for someone who isn't (or can't be)
/// saved in the Device's address book. Pops with the found [User], or
/// nothing if the sheet is dismissed.
class FindByPhoneNumberSheet extends ConsumerStatefulWidget {
  const FindByPhoneNumberSheet({super.key});

  @override
  ConsumerState<FindByPhoneNumberSheet> createState() => _FindByPhoneNumberSheetState();
}

class _FindByPhoneNumberSheetState extends ConsumerState<FindByPhoneNumberSheet> {
  final _countryCode = TextEditingController(text: '91');
  final _number = TextEditingController();
  bool _searching = false;
  String? _message;

  @override
  void dispose() {
    _countryCode.dispose();
    _number.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final countryCode = _countryCode.text.trim();
    final number = _number.text.replaceAll(RegExp(r'\D'), '');
    if (countryCode.isEmpty || number.isEmpty) {
      setState(() => _message = 'Enter a country code and phone number');
      return;
    }
    // Same convention as sign-in: the backend normalises the rest.
    final phoneNumber = '+$countryCode$number';

    setState(() {
      _searching = true;
      _message = null;
    });
    try {
      final user = await ref.read(contactsRepositoryProvider).lookupByPhoneNumber(phoneNumber);
      if (!mounted) return;
      if (user == null) {
        setState(() => _message = "No one on Convoze has that number.");
        return;
      }
      Navigator.of(context).pop(user);
    } catch (e) {
      if (mounted) setState(() => _message = contactsFailureMessage(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('New chat via phone number', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: TextField(
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
                  controller: _number,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Phone number'),
                  onSubmitted: (_) => _search(),
                ),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _message!,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          LoadingFilledButton(label: 'Search', loading: _searching, onPressed: _search),
        ],
      ),
    );
  }
}
