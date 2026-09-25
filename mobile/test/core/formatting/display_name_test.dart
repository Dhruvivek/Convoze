import 'package:convoze/core/formatting/display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the display name when there is one', () {
    expect(
      displayName(displayName: 'Asha', phoneNumber: '+14155554821'),
      'Asha',
    );
  });

  test('falls back to the last 4 digits of the phone number', () {
    expect(
      displayName(displayName: null, phoneNumber: '+14155554821'),
      '•••• 4821',
    );
  });

  test('treats a blank display name as none', () {
    expect(
      displayName(displayName: '  ', phoneNumber: '+14155554821'),
      '•••• 4821',
    );
  });

  test('uses only the digits for the fallback', () {
    expect(
      displayName(displayName: null, phoneNumber: '+1 415-555-48 21'),
      '•••• 4821',
    );
  });

  test('shows every digit of a number shorter than 4 digits', () {
    expect(displayName(displayName: null, phoneNumber: '+12'), '•••• 12');
  });
}
