import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/user.dart';
import '../../../core/network/dio_provider.dart';
import 'contacts_failure.dart';
import 'device_contacts_service.dart';

part 'contacts_repository.g.dart';

/// Everyone on Convoze who's also in the Device's address book (`POST
/// /users/match`, #101), or one exact registered User found by phone number
/// (`GET /users/lookup`) for someone not saved as a contact.
class ContactsRepository {
  ContactsRepository(this._dio);

  final Dio _dio;

  /// Throws a [ContactsFailure] when it can't.
  Future<List<User>> matchContacts(List<String> phoneNumbers) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/users/match',
        data: {'phoneNumbers': phoneNumbers},
      );
      final raw = (res.data?['users'] as List?) ?? const [];
      return raw.map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ContactsFailure.fromDioException(e);
    }
  }

  /// Throws a [ContactsFailure] when it can't.
  Future<User?> lookupByPhoneNumber(String phoneNumber) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/users/lookup',
        queryParameters: {'phoneNumber': phoneNumber},
      );
      final user = res.data?['user'] as Map<String, dynamic>?;
      return user == null ? null : User.fromJson(user);
    } on DioException catch (e) {
      throw ContactsFailure.fromDioException(e);
    }
  }
}

@Riverpod(keepAlive: true)
ContactsRepository contactsRepository(Ref ref) =>
    ContactsRepository(ref.watch(dioProvider));

/// Thrown by [contacts] instead of a bare permission bool, so the UI can
/// tell "not asked yet / denied" apart from "denied for good, go to
/// Settings" and render the right recovery action.
class ContactsPermissionException implements Exception {
  const ContactsPermissionException(this.permanentlyDenied);
  final bool permanentlyDenied;
}

/// The Contacts tab / New conversation picker's data source: the Device's
/// address book, matched against registered Users. Throws
/// [ContactsPermissionException] when access hasn't been granted, or a
/// [ContactsFailure] when the match request itself fails.
@riverpod
Future<List<User>> contacts(Ref ref) async {
  final deviceContacts = ref.watch(deviceContactsServiceProvider);
  final permission = await deviceContacts.requestPermission();
  if (permission != ContactsPermission.granted) {
    throw ContactsPermissionException(permission == ContactsPermission.permanentlyDenied);
  }

  final phoneNumbers = await deviceContacts.fetchPhoneNumbers();
  if (phoneNumbers.isEmpty) return const [];
  return ref.watch(contactsRepositoryProvider).matchContacts(phoneNumbers);
}
