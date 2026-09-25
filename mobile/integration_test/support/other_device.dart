import 'dart:async';

import 'package:convoze/core/config/app_config.dart';
import 'package:convoze/core/storage/jwt.dart';
import 'package:dio/dio.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:uuid/uuid.dart';

import 'e2e.dart';

/// A Device other than the app under test, driven from the test through the
/// real API and a real Socket.IO connection: how a test makes someone else
/// sign in, come online and listen, or signs the app's own User in on a
/// second Device.
class OtherDevice {
  OtherDevice._(
    this._dio, {
    required this.userId,
    required this.sessionId,
    required this.accessToken,
    required this.refreshToken,
  });

  final Dio _dio;
  final String userId;
  final String sessionId;
  final String accessToken;
  final String refreshToken;
  final List<io.Socket> _sockets = [];

  /// Signs [phoneNumber] in on a new Device.
  static Future<OtherDevice> signIn(String phoneNumber) async {
    final deviceId = const Uuid().v4();
    final dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        // Tests assert on statuses, so none of them throws.
        validateStatus: (_) => true,
      ),
    );
    final res = await dio.post<Map<String, dynamic>>(
      '/auth/otp/verify',
      data: {
        'phoneNumber': phoneNumber,
        'code': e2eOtpCode,
        'deviceId': deviceId,
        'platform': 'android',
      },
    );
    if (res.statusCode != 200) {
      throw StateError('Signing $phoneNumber in failed: ${res.statusCode}');
    }
    final body = res.data!;
    final accessToken = body['accessToken'] as String;
    return OtherDevice._(
      dio,
      userId: (body['user'] as Map<String, dynamic>)['id'] as String,
      sessionId: sessionIdOf(accessToken),
      accessToken: accessToken,
      refreshToken: body['refreshToken'] as String,
    );
  }

  /// Logs out every other Device of this Device's User, and answers the
  /// status code.
  Future<int> logoutOthers() async {
    final res = await _dio.post<void>(
      '/auth/sessions/logout-others',
      options: _authorized,
    );
    return res.statusCode!;
  }

  /// Makes a protected call with this Device's access token, and answers the
  /// status code: 200 while its Session is live.
  Future<int> echoStatus() async {
    final res = await _dio.get<void>('/__e2e__/echo', options: _authorized);
    return res.statusCode!;
  }

  /// `POST /conversations/direct` as this Device's User — unlike
  /// `E2eBackend.seedConversation`, this writes `conversation.joined` to
  /// both Users' Update logs (`directConversation.js`), so an already
  /// connected counterpart's replica picks up the Conversation live.
  /// Answers its id.
  Future<String> createDirectConversationWith(String otherUserId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/conversations/direct',
      data: {'userId': otherUserId},
      options: _authorized,
    );
    return res.data!['id'] as String;
  }

  Options get _authorized =>
      Options(headers: {'Authorization': 'Bearer $accessToken'});

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

  /// Sends a Message on [socket] (from [connectSocket]) via `message:send`,
  /// waiting for its ack, and answers the server's response
  /// (`sendMessage.js`'s `{ok, messageId, createdAt}` / `{ok: false, code}`).
  Future<Map<String, dynamic>> sendMessage(
    io.Socket socket, {
    required String conversationId,
    String content = 'hi',
  }) async {
    final res = await socket.timeout(5000).emitWithAckAsync('message:send', {
      'clientMsgId': const Uuid().v4(),
      'conversationId': conversationId,
      'content': content,
    });
    return (res as Map).cast<String, dynamic>();
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
String sessionIdOf(String accessToken) =>
    jwtClaims(accessToken)['sessionId'] as String;

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
