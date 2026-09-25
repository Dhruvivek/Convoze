import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/app_config.dart';

part 'socket_factory.g.dart';

/// Builds a new, not yet connected socket to the backend.
typedef SocketFactory = io.Socket Function();

/// Overridable, so a test can hand the app a socket of its own.
@Riverpod(keepAlive: true)
SocketFactory socketFactory(Ref ref) =>
    () => io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          // The server offers no HTTP long-polling fallback.
          .setTransports(['websocket'])
          .disableAutoConnect()
          // A socket per sign-in, never one reused from a previous Session.
          .enableForceNew()
          .build(),
    );
