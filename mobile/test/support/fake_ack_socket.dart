import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

/// A socket double for `emitWithAckAsync`-driven drainers (the Outbox
/// drainer, the pending-reads flusher): [emitWithAckAsync] returns
/// [response] instead of touching the network, mirroring what `message:send`
/// /`conversation:read`'s ack contracts return (`sendMessage.js`/`markRead.js`).
class FakeAckSocket extends io.Socket {
  FakeAckSocket(this.response)
    : super(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

  final Map<String, dynamic> response;
  final sentEvents = <String>[];

  @override
  Future emitWithAckAsync(String event, dynamic data, {Function? ack, bool binary = false}) async {
    sentEvents.add(event);
    return response;
  }
}

/// A socket double whose ack always fails, simulating a timed-out or
/// dropped send (a drainer must stop, not spin).
class TimingOutSocket extends io.Socket {
  TimingOutSocket()
    : super(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

  final sentEvents = <String>[];

  @override
  Future emitWithAckAsync(String event, dynamic data, {Function? ack, bool binary = false}) async {
    sentEvents.add(event);
    throw StateError('ack timed out');
  }
}
