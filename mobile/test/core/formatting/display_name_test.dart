import 'package:convoze/core/formatting/display_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the display name when there is one', () {
    expect(
      displayName(displayName: 'Asha', phoneNumber: '+14155554821'),
      'Asha',
    );
  });

  test('falls back to the phone number', () {
    expect(
      displayName(displayName: null, phoneNumber: '+14155554821'),
      '+14155554821',
    );
  });

  test('treats a blank display name as none', () {
    expect(
      displayName(displayName: '  ', phoneNumber: '+14155554821'),
      '+14155554821',
    );
  });
}
