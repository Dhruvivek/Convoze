import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/models/user.dart';
import 'package:convoze/features/conversations/data/contacts_repository.dart';
import 'package:convoze/features/conversations/data/device_contacts_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers every request with one canned response, or fails the connection.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter.respond(this._status, [this._body]) : _connectionFails = false;
  _StubAdapter.connectionFails()
    : _status = 0,
      _body = null,
      _connectionFails = true;

  final int _status;
  final Object? _body;
  final bool _connectionFails;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_connectionFails) {
      throw DioException.connectionError(requestOptions: options, reason: 'Connection refused');
    }
    return ResponseBody.fromString(
      _body == null ? '' : jsonEncode(_body),
      _status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _FakeDeviceContactsService extends DeviceContactsService {
  const _FakeDeviceContactsService({
    this.permission = ContactsPermission.granted,
    this.phoneNumbers = const [],
  });

  final ContactsPermission permission;
  final List<String> phoneNumbers;

  @override
  Future<ContactsPermission> requestPermission() async => permission;

  @override
  Future<List<String>> fetchPhoneNumbers() async => phoneNumbers;
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ProviderContainer buildContainer({
    required DeviceContactsService deviceContactsService,
    required _StubAdapter adapter,
  }) {
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;
    final container = ProviderContainer(
      // Riverpod retries a failed FutureProvider with backoff by default;
      // these failures are deterministic, so retrying would just make the
      // permission/failure tests hang waiting for a retry that never helps.
      retry: (_, _) => null,
      overrides: [
        deviceContactsServiceProvider.overrideWithValue(deviceContactsService),
        contactsRepositoryProvider.overrideWithValue(ContactsRepository(dio)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('throws ContactsPermissionException(false) when access hasn\'t been granted', () async {
    final container = buildContainer(
      deviceContactsService: const _FakeDeviceContactsService(
        permission: ContactsPermission.denied,
      ),
      adapter: _StubAdapter.respond(200, {'users': []}),
    );
    // A listener keeps this autoDispose provider alive while it settles —
    // otherwise it can be torn down mid-flight before its rejection lands.
    container.listen(contactsProvider, (_, _) {});
    await settle();

    final state = container.read(contactsProvider);
    expect(state, isA<AsyncError<List<User>>>());
    final error = (state as AsyncError).error;
    expect(error, isA<ContactsPermissionException>());
    expect((error as ContactsPermissionException).permanentlyDenied, false);
  });

  test('throws ContactsPermissionException(true) when permanently denied', () async {
    final container = buildContainer(
      deviceContactsService: const _FakeDeviceContactsService(
        permission: ContactsPermission.permanentlyDenied,
      ),
      adapter: _StubAdapter.respond(200, {'users': []}),
    );
    container.listen(contactsProvider, (_, _) {});
    await settle();

    final state = container.read(contactsProvider);
    expect(state, isA<AsyncError<List<User>>>());
    final error = (state as AsyncError).error;
    expect(error, isA<ContactsPermissionException>());
    expect((error as ContactsPermissionException).permanentlyDenied, true);
  });

  test(
    'returns an empty list without calling the backend when the address book is empty',
    () async {
      final container = buildContainer(
        deviceContactsService: const _FakeDeviceContactsService(phoneNumbers: []),
        adapter: _StubAdapter.connectionFails(),
      );

      expect(await container.read(contactsProvider.future), isEmpty);
    },
  );

  test('matches the address book against registered Users', () async {
    final container = buildContainer(
      deviceContactsService: const _FakeDeviceContactsService(
        phoneNumbers: ['+14155550100'],
      ),
      adapter: _StubAdapter.respond(200, {
        'users': [
          {'id': 'u1', 'displayName': 'Priya', 'avatarUrl': null, 'phoneNumber': '+14155550100'},
        ],
      }),
    );

    final users = await container.read(contactsProvider.future);

    expect(users, hasLength(1));
    expect(users.first.id, 'u1');
  });
}
