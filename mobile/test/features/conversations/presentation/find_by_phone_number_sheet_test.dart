import 'dart:convert';
import 'dart:typed_data';

import 'package:convoze/core/models/user.dart';
import 'package:convoze/features/conversations/data/contacts_repository.dart';
import 'package:convoze/features/conversations/presentation/find_by_phone_number_sheet.dart';
import 'package:dio/dio.dart';
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

User? _lastResult;

/// Opens the sheet the same way [ContactPickerList] does: as a modal bottom
/// sheet whose popped value is the found User (or nothing).
Future<void> _openSheet(WidgetTester tester, HttpClientAdapter adapter) async {
  _lastResult = null;
  final dio = Dio(BaseOptions(baseUrl: 'http://backend.test'))..httpClientAdapter = adapter;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [contactsRepositoryProvider.overrideWithValue(ContactsRepository(dio))],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                _lastResult = await showModalBottomSheet<User>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const FindByPhoneNumberSheet(),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rejects an empty phone number without calling the backend', (tester) async {
    await _openSheet(tester, _StubAdapter.connectionFails());

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a country code and phone number'), findsOneWidget);
    expect(_lastResult, isNull);
  });

  testWidgets('shows a message when nobody has that number', (tester) async {
    await _openSheet(tester, _StubAdapter.respond(200, {'user': null}));

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '4155550100');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('No one on Convoze has that number.'), findsOneWidget);
    expect(_lastResult, isNull);
  });

  testWidgets('pops with the found User', (tester) async {
    await _openSheet(
      tester,
      _StubAdapter.respond(200, {
        'user': {
          'id': 'u1',
          'displayName': 'Priya',
          'avatarUrl': null,
          'phoneNumber': '+914155550100',
        },
      }),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '4155550100');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(_lastResult, isNotNull);
    expect(_lastResult!.id, 'u1');
    expect(find.widgetWithText(TextField, 'Phone number'), findsNothing);
  });

  testWidgets('shows the rate-limit message on a 429', (tester) async {
    await _openSheet(
      tester,
      _StubAdapter.respond(429, {
        'error': {'code': 'rate_limited', 'message': 'Too many lookups'},
      }),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Phone number'), '4155550100');
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(find.text('Too many attempts. Try again in a few minutes.'), findsOneWidget);
    expect(_lastResult, isNull);
  });
}
