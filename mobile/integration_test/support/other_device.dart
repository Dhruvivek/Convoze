import 'dart:async';
import 'dart:convert';

import 'package:convoze/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import 'e2e.dart';

/// Another User's Device, driven from the test through the real API and a
/// real Socket.IO connection: how a test makes someone else sign in, come
/// online and listen.
class OtherDevice {
  OtherDevice._({
    required this.userId,
    required this.sessionId,
    required this.accessToken,
  });

  final String userId;
  final String sessionId;
  final String accessToken;
  final List<io.Socket> _sockets = [];

  /// Signs [phoneNumber] in on a new Device.
  static Future<OtherDevice> signIn(String phoneNumber) async {
    final deviceId = const Uuid().v4();
    final dio = Dio(BaseOptions(baseUrl: AppConfig.apiBaseUrl));
    final res = await dio.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {
        'phoneNumber': phoneNumber,
        'code': e2eOtpCode,
        'deviceId': deviceId,
        'platform': 'android',
      },
    );
    final body = res.data!;
    final accessToken = body['accessToken'] as String;
    return OtherDevice._(
      userId: (body['user'] as Map<String, dynamic>)['id'] as String,
      sessionId: sessionIdOf(accessToken),
      accessToken: accessToken,
    );
  }

  /// Opens a live connection for this Device's Session, completing once the
  /// server has accepted it (and so joined it to its rooms).
  Future<io.Socket> connectSocket() {
    final socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .disableReconnection()
          .enableForceNew()
          .setAuth({'token': accessToken})
          .build(),
    );
    _sockets.add(socket);
    final connected = Completer<io.Socket>();
    socket
      ..onConnect((_) {
        if (!connected.isCompleted) connected.complete(socket);
      })
      ..onConnectError((err) {
        if (!connected.isCompleted) {
          connected.completeError(StateError('connect_error: $err'));
        }
      })
      ..connect();
    return connected.future.timeout(const Duration(seconds: 5));
  }

  /// Closes every connection this Device opened.
  void dispose() {
    for (final socket in _sockets) {
      socket.dispose();
    }
    _sockets.clear();
  }
}

/// The Session an access token belongs to, read from its (unverified) claims.
String sessionIdOf(String accessToken) {
  final claims = accessToken.split('.')[1];
  final json = utf8.decode(base64Url.decode(base64Url.normalize(claims)));
  return (jsonDecode(json) as Map<String, dynamic>)['sessionId'] as String;
}

/// The next [event] on [socket], failing after [timeout].
Future<dynamic> nextEvent(
  io.Socket socket,
  String event, {
  Duration timeout = const Duration(seconds: 5),
}) {
  final received = Completer<dynamic>();
  void handler(dynamic data) {
    if (!received.isCompleted) received.complete(data);
  }

  socket.on(event, handler);
  return received.future
      .timeout(timeout)
      .whenComplete(() => socket.off(event, handler));
}
