import 'package:convoze/features/conversations/data/device_contacts_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// Real channel names from the flutter_contacts / permission_handler plugins
// (github.com/QuisApp/flutter_contacts, flutter.baseflow.com/permissions).
const _contactsChannel = MethodChannel('github.com/QuisApp/flutter_contacts');
const _permissionChannel = MethodChannel(
  'flutter.baseflow.com/permissions/methods',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const service = DeviceContactsService();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockContacts(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(_contactsChannel, handler);
  }

  void mockPermissions(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(_permissionChannel, handler);
  }

  tearDown(() {
    messenger.setMockMethodCallHandler(_contactsChannel, null);
    messenger.setMockMethodCallHandler(_permissionChannel, null);
  });

  group('requestPermission', () {
    test('reports granted when the OS grants access', () async {
      mockContacts((call) async {
        expect(call.method, 'requestPermission');
        expect(call.arguments, true); // readonly: true
        return true;
      });

      expect(await service.requestPermission(), ContactsPermission.granted);
    });

    test('reports denied (but askable again) when the OS declines', () async {
      mockContacts((call) async => false);
      mockPermissions((call) async {
        expect(call.method, 'checkPermissionStatus');
        return 0; // PermissionStatus.denied
      });

      expect(await service.requestPermission(), ContactsPermission.denied);
    });

    test('reports permanentlyDenied when only Settings can grant it', () async {
      mockContacts((call) async => false);
      mockPermissions((call) async => 4); // PermissionStatus.permanentlyDenied

      expect(
        await service.requestPermission(),
        ContactsPermission.permanentlyDenied,
      );
    });
  });

  group('fetchPhoneNumbers', () {
    test('dedupes numbers shared across contacts and drops blank ones', () async {
      mockContacts((call) async {
        expect(call.method, 'select');
        return [
          {
            'id': 'c1',
            'displayName': 'Alice',
            'phones': [
              {'number': '+14155550100'},
            ],
          },
          {
            'id': 'c2',
            'displayName': 'Bob',
            'phones': [
              {'number': '+14155550100'},
              {'number': '   '},
              {'number': '+14155550101'},
            ],
          },
        ];
      });

      final numbers = await service.fetchPhoneNumbers();

      expect(numbers.toSet(), {'+14155550100', '+14155550101'});
    });

    test('returns an empty list when the address book has no phone numbers', () async {
      mockContacts(
        (call) async => [
          {'id': 'c1', 'displayName': 'Alice', 'phones': <Object?>[]},
        ],
      );

      expect(await service.fetchPhoneNumbers(), isEmpty);
    });
  });
}
