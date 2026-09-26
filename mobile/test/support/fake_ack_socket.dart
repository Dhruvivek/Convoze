import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

/// A socket double for `emitWithAckAsync`-driven calls (the Outbox drainer,
/// `MessagesRepository.editMessage`/`deleteMessage`): [emitWithAckAsync]
/// returns [response] instead of touching the network, mirroring what
/// `message:send`/`message:edit`/`message:delete`'s ack contracts return
/// (`sendMessage.js`/`editMessage.js`/`deleteMessage.js`).
class FakeAckSocket extends io.Socket {
  FakeAckSocket(this.response)
    : super(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

  final Map<String, dynamic> response;
  final sentEvents = <String>[];
  final sentPayloads = <Map<String, dynamic>>[];

  @override
  Future emitWithAckAsync(String event, dynamic data, {Function? ack, bool binary = false}) async {
    sentEvents.add(event);
    sentPayloads.add((data as Map).cast<String, dynamic>());
    return response;
  }
}

/// A socket double whose ack always fails, simulating a timed-out or
/// dropped send (a caller must stop, not spin).
class TimingOutSocket extends io.Socket {
  TimingOutSocket()
    : super(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

  @override
  Future emitWithAckAsync(String event, dynamic data, {Function? ack, bool binary = false}) async {
    throw StateError('ack timed out');
  }
}
