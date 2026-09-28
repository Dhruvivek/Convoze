import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/db/database.dart';
import 'package:convoze/core/models/user.dart';
import 'package:convoze/features/conversations/data/contacts_failure.dart';
import 'package:convoze/features/conversations/data/contacts_repository.dart';
import 'package:convoze/features/conversations/data/conversations_repository.dart';
import 'package:convoze/features/conversations/presentation/contact_picker_list.dart';
import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
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

const _alice = User(id: 'u-alice', phoneNumber: '+14155550100', displayName: 'Alice');
const _bob = User(id: 'u-bob', phoneNumber: '+14155550101', displayName: 'Bob');

/// Pumps [ContactPickerList] with [contacts] backing `contactsProvider`
/// (returning a list, or throwing a [ContactsPermissionException] /
/// [ContactsFailure] to exercise the error states) and, when a select flow
/// needs to actually open a conversation, a real [conversationsRepository].
Future<void> _pumpPicker(
  WidgetTester tester, {
  required FutureOr<List<User>> Function(Ref ref) contacts,
  ConversationsRepository? conversationsRepository,
  required void Function(String conversationId, String name) onSelect,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        contactsProvider.overrideWith(contacts),
        if (conversationsRepository != null)
          conversationsRepositoryProvider.overrideWithValue(conversationsRepository),
      ],
      child: MaterialApp(home: Scaffold(body: ContactPickerList(onSelect: onSelect))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows a message when none of the contacts are on Convoze', (tester) async {
    await _pumpPicker(tester, contacts: (ref) async => const [], onSelect: (_, _) {});

    expect(find.text('None of your contacts are on Convoze yet.'), findsOneWidget);
  });

  testWidgets('lists matched contacts by their display name', (tester) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => const [_alice, _bob],
      onSelect: (_, _) {},
    );

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsOneWidget);
  });

  testWidgets('filters the list by name as the query changes', (tester) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => const [_alice, _bob],
      onSelect: (_, _) {},
    );

    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pumpAndSettle();

    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Bob'), findsNothing);
  });

  testWidgets('filters the list by phone number as the query changes', (tester) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => const [_alice, _bob],
      onSelect: (_, _) {},
    );

    await tester.enterText(find.byType(TextField), '550101');
    await tester.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('shows "No one matches" for a query with no results', (tester) async {
    await _pumpPicker(tester, contacts: (ref) async => const [_alice], onSelect: (_, _) {});

    await tester.enterText(find.byType(TextField), 'nobody');
    await tester.pumpAndSettle();

    expect(find.text('No one matches "nobody"'), findsOneWidget);
  });

  testWidgets('offers "Allow access" when Contacts permission was denied', (tester) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => throw const ContactsPermissionException(false),
      onSelect: (_, _) {},
    );

    expect(
      find.text("Convoze needs access to your contacts to show who's already here."),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Allow access'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Open settings'), findsNothing);
  });

  testWidgets('offers "Open settings" when Contacts permission is permanently denied', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => throw const ContactsPermissionException(true),
      onSelect: (_, _) {},
    );

    expect(find.widgetWithText(FilledButton, 'Open settings'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Allow access'), findsNothing);
  });

  testWidgets('shows a Retry button when matching contacts fails', (tester) async {
    await _pumpPicker(
      tester,
      contacts: (ref) async => throw const ContactsNetworkFailure(),
      onSelect: (_, _) {},
    );

    expect(
      find.text("Couldn't reach Convoze. Check your connection and try again."),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });

  testWidgets('selecting a contact opens the direct conversation and calls onSelect', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
      ..httpClientAdapter = _StubAdapter.respond(201, {
        'id': 'conv-1',
        'type': 'direct',
        'participants': [
          {'userId': 'me', 'role': 'member'},
          {'userId': _alice.id, 'role': 'member'},
        ],
        'users': [
          {'id': 'me', 'phoneNumber': '+10000000000', 'displayName': 'Me', 'avatarUrl': null},
          {
            'id': _alice.id,
            'phoneNumber': _alice.phoneNumber,
            'displayName': _alice.displayName,
            'avatarUrl': null,
          },
        ],
      });

    String? selectedId;
    String? selectedName;
    await _pumpPicker(
      tester,
      contacts: (ref) async => const [_alice],
      conversationsRepository: ConversationsRepository(dio, db),
      onSelect: (id, name) {
        selectedId = id;
        selectedName = name;
      },
    );

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(selectedId, 'conv-1');
    expect(selectedName, 'Alice');
  });

  testWidgets('shows an error snackbar when opening the conversation fails', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))
      ..httpClientAdapter = _StubAdapter.connectionFails();

    await _pumpPicker(
      tester,
      contacts: (ref) async => const [_alice],
      conversationsRepository: ConversationsRepository(dio, db),
      onSelect: (_, _) {},
    );

    await tester.tap(find.text('Alice'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('tapping "New chat via phone number" opens the lookup sheet', (tester) async {
    await _pumpPicker(tester, contacts: (ref) async => const [], onSelect: (_, _) {});

    await tester.tap(find.text('New chat via phone number'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'Phone number'), findsOneWidget);
  });
}
