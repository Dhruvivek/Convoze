import 'package:convoze/app.dart';
import 'package:convoze/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Harness for the e2e suite: the real ConvozeApp against a local backend
// started with `npm run start:e2e` (see the README). The app and the harness
// both reach it through API_BASE_URL.

/// Client for the backend's test-only `/__e2e__` endpoints.
class E2eBackend {
  E2eBackend({String baseUrl = AppConfig.apiBaseUrl})
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

  final Dio _dio;

  /// Empties every table and clears pending injected faults.
  Future<void> reset() => _post('/__e2e__/reset');

  /// Makes the next [count] calls to `method path` fail with [status] and
  /// error [code] (503 `fault_injected` unless given).
  Future<void> failNext(
    String method,
    String path, {
    int count = 1,
    int? status,
    String? code,
  }) => _post(
    '/__e2e__/faults',
    data: {
      'method': method,
      'path': path,
      'count': count,
      'status': ?status,
      'code': ?code,
    },
  );

  /// Requests a code for [phoneNumber] through the real API, as another
  /// Device would, to use up some of its rate limit.
  Future<void> requestOtp(String phoneNumber) =>
      _post('/auth/otp/request', data: {'phoneNumber': phoneNumber});

  Future<void> _post(String path, {Object? data}) async {
    try {
      await _dio.post<void>(path, data: data);
    } on DioException catch (e) {
      throw StateError(
        'E2E backend call $path to ${_dio.options.baseUrl} failed (${e.message}). '
        'Is the backend running with `npm run start:e2e`?',
      );
    }
  }
}

final backend = E2eBackend();

/// E2E mode's fake Verify client accepts only this code (E2E_OTP_CODE).
const e2eOtpCode = String.fromEnvironment(
  'E2E_OTP_CODE',
  defaultValue: '000000',
);

/// Call once at the top of every e2e test file's `main`.
void setUpE2e() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await backend.reset();
    // Every test starts as a fresh install: no Session, no Device ID.
    await const FlutterSecureStorage().deleteAll();
  });
}

/// Launches the app as a cold start: a fresh ProviderScope and ConvozeApp
/// over whatever is in device storage. Calling it again restarts the app.
Future<void> launchApp(WidgetTester tester) async {
  await _coldStart(tester);
  await tester.pumpAndSettle();
}

/// Cold-starts the app like [launchApp], then pumps frame by frame until
/// [target] shows, failing if [mustNotShow] shows on any frame along the way.
Future<void> launchAppUntil(
  WidgetTester tester,
  Finder target, {
  required Finder mustNotShow,
  Duration timeout = const Duration(seconds: 10),
}) async {
  await _coldStart(tester);
  final deadline = DateTime.now().add(timeout);
  while (target.evaluate().isEmpty) {
    expect(mustNotShow, findsNothing);
    if (DateTime.now().isAfter(deadline)) {
      fail('$target did not show within $timeout');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(mustNotShow, findsNothing);
}

// The unique key makes a restart replace the old ProviderScope rather than
// reuse it.
Future<void> _coldStart(WidgetTester tester) => tester.pumpWidget(
  ProviderScope(key: UniqueKey(), child: const ConvozeApp()),
);
