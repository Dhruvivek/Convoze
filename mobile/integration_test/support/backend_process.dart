import 'dart:async';
import 'dart:io';

import 'package:convoze/core/config/app_config.dart';
import 'package:dio/dio.dart';

/// Starts, and later restarts, the real backend (`npm run start:e2e`) as a
/// child process — for the one test proving the client survives the server
/// itself going away and coming back, not just a dropped transport (#31).
///
/// Every other e2e test assumes the backend is already running externally
/// (see `support/e2e.dart`); this is the one exception, since restarting it
/// means having a handle to kill and relaunch it. Run the file that uses
/// this on its own, not alongside the rest of `integration_test/`: it binds
/// API_BASE_URL's port itself and would conflict with an externally-started
/// backend already listening there.
class BackendProcess {
  BackendProcess._(this._workingDirectory);

  final String _workingDirectory;
  Process? _process;

  static Future<BackendProcess> start({
    String workingDirectory = '../backend',
  }) async {
    final backend = BackendProcess._(workingDirectory);
    await backend._launch();
    return backend;
  }

  Future<void> _launch() async {
    final process = await Process.start(
      'npm',
      ['run', 'start:e2e'],
      workingDirectory: _workingDirectory,
    );
    _process = process;
    process.exitCode.then((code) {
      if (!identical(_process, process)) return; // superseded by a restart
      if (code != 0 && code != -15 && code != -9) {
        // Surfaces a startup failure (bad port, missing deps) instead of
        // leaving the test hanging on a backend that never comes up.
        stderr.writeln('backend process exited unexpectedly with code $code');
      }
    });
    await _waitUntilUp();
  }

  Future<void> _waitUntilUp() async {
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 1),
        receiveTimeout: const Duration(seconds: 1),
      ),
    );
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      try {
        // A cheap, non-mutating call: unlike /__e2e__/reset, safe to poll
        // after a restart without wiping the Session the test signed in.
        final res = await dio.get<void>('/__e2e__/sessions/none/sockets');
        if (res.statusCode == 200) return;
      } on DioException {
        // Not up yet.
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError(
      'Backend did not come up on ${AppConfig.apiBaseUrl} within 20s',
    );
  }

  /// Kills the process and starts a fresh one on the same port, once it
  /// accepts requests again.
  Future<void> restart() async {
    final dying = _process!;
    dying.kill(ProcessSignal.sigkill);
    await dying.exitCode;
    await _launch();
  }

  Future<void> stop() async {
    _process?.kill(ProcessSignal.sigkill);
    await _process?.exitCode;
    _process = null;
  }
}
