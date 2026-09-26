import 'package:dio/dio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/models/user.dart';
import '../../../core/network/dio_provider.dart';

part 'contacts_repository.g.dart';

/// Everyone else on Convoze (`GET /users`): the Contacts tab's data source,
/// until real phone-contact matching replaces it.
class ContactsRepository {
  ContactsRepository(this._dio);

  final Dio _dio;

  Future<List<User>> fetchContacts() async {
    final res = await _dio.get<Map<String, dynamic>>('/users');
    final raw = (res.data?['users'] as List?) ?? const [];
    return raw.map((u) => User.fromJson(u as Map<String, dynamic>)).toList();
  }
}

@Riverpod(keepAlive: true)
ContactsRepository contactsRepository(Ref ref) =>
    ContactsRepository(ref.watch(dioProvider));

/// The list of everyone else on Convoze, fetched fresh each time the
/// Contacts tab / New conversation screen is opened.
@riverpod
Future<List<User>> contacts(Ref ref) => ref.watch(contactsRepositoryProvider).fetchContacts();
