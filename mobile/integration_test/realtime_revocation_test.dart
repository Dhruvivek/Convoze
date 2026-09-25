import 'package:convoze/core/realtime/connection_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/e2e.dart';
import 'support/other_device.dart';
import 'support/realtime_helpers.dart';

// Covers #33: revoking a Session reaches its open sockets immediately, so a
// signed-out Device lands on login without waiting for its next HTTP call
// (ADR 0005). logout_test.dart and realtime_connection_test.dart cover this
// Device's own "Log out"; this file is about a Session ended from elsewhere.

const _storage = FlutterSecureStorage();
const _alice = '+14155550100';

void main() {
  setUpE2e();

  final others = <OtherDevice>[];
  tearDown(() {
    for (final other in others) {
      other.dispose();
    }
    others.clear();
  });

  testWidgets(
    'a second Device logging this one out lands the app on login within a '
    'few seconds, from the push alone (no HTTP call in between)',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final deviceId = await _storage.read(key: 'device_id');
      final other = await OtherDevice.signIn(_alice);
      others.add(other);

      expect(await other.logoutOthers(), 204);

      await pumpUntil(
        tester,
        () async => find.text('Sign in').evaluate().isNotEmpty,
        reason: 'the app to land on login after the sessionRevoked push',
      );
      expect(await _storage.read(key: 'refresh_token'), isNull);
      expect(await _storage.read(key: 'access_token'), isNull);
      expect(await _storage.read(key: 'device_id'), deviceId);
      expect(connection(tester).status, ConnectionStatus.offline);
    },
  );

  testWidgets(
    'refresh-token reuse detection also lands the app on login via the push',
    (tester) async {
      await launchApp(tester);
      await signIn(tester);
      await untilStatus(tester, ConnectionStatus.connected);
      final deviceId = await _storage.read(key: 'device_id');
      final staleRefreshToken = (await _storage.read(key: 'refresh_token'))!;
      // Rotates the Session's stored hash out from under the Device, as if
      // a copy of its token had been used elsewhere first.
      expect(await backend.refreshStatus(staleRefreshToken), 200);

      // Reusing the now-rotated-away token is detected as reuse and revokes
      // the Session the Device is still holding.
      expect(await backend.refreshStatus(staleRefreshToken), 401);

      await pumpUntil(
        tester,
        () async => find.text('Sign in').evaluate().isNotEmpty,
        reason: 'the app to land on login after reuse revokes the Session',
      );
      expect(await _storage.read(key: 'device_id'), deviceId);
    },
  );
}
