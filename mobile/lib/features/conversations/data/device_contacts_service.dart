import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_contacts_service.g.dart';

enum ContactsPermission {
  /// Access granted; [DeviceContactsService.fetchPhoneNumbers] can be called.
  granted,

  /// Not yet granted, but the system permission dialog can still be shown.
  denied,

  /// Denied for good (or restricted by policy) — the only way forward is the
  /// app's Settings page.
  permanentlyDenied,
}

/// The Contacts tab's window onto the Device's address book (#101): whether
/// it's allowed to read it, and the phone numbers to match against
/// registered Users when it is.
class DeviceContactsService {
  const DeviceContactsService();

  Future<ContactsPermission> requestPermission() async {
    if (await FlutterContacts.requestPermission(readonly: true)) {
      return ContactsPermission.granted;
    }
    final status = await Permission.contacts.status;
    return status.isPermanentlyDenied
        ? ContactsPermission.permanentlyDenied
        : ContactsPermission.denied;
  }

  Future<void> openSettings() => openAppSettings();

  /// Every phone number saved in the Device's address book, deduplicated.
  /// Assumes permission was already granted.
  Future<List<String>> fetchPhoneNumbers() async {
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final numbers = <String>{};
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        if (phone.number.trim().isNotEmpty) numbers.add(phone.number);
      }
    }
    return numbers.toList();
  }
}

@Riverpod(keepAlive: true)
DeviceContactsService deviceContactsService(Ref ref) => const DeviceContactsService();
