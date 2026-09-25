import 'package:convoze/app.dart';
import 'package:convoze/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  /// Makes the next [count] calls to `method path` fail with 503.
  Future<void> failNext(String method, String path, {int count = 1}) =>
      _post(
        '/__e2e__/faults',
        data: {'method': method, 'path': path, 'count': count},
      );

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

/// Call once at the top of every e2e test file's `main`.
void setUpE2e() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(backend.reset);
}

/// Launches the app as a cold start: a fresh ProviderScope and ConvozeApp.
Future<void> launchApp(WidgetTester tester) async {
  await tester.pumpWidget(const ProviderScope(child: ConvozeApp()));
  await tester.pumpAndSettle();
}
