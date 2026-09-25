import 'package:convoze/core/realtime/socket_factory.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

/// A [Socket] that never touches the network: [connect] resolves to
/// `connected` on the next microtask, and [disconnect]/[dispose] just flip
/// local state. Lets a widget test cold-start the signed-in app without a
/// real backend — the alternative, a real socket that can never reach one,
/// would leave [ConnectionManager] stuck `connecting`/`reconnecting` and pin
/// the "Connecting…" banner's indeterminate spinner up, which never lets
/// `pumpAndSettle` converge.
class _FakeSocket extends io.Socket {
  _FakeSocket(Manager manager) : super(manager, '/', const {});

  @override
  io.Socket connect() {
    Future.microtask(() {
      connected = true;
      emitReserved('connect');
    });
    return this;
  }

  @override
  io.Socket disconnect() {
    connected = false;
    return this;
  }

  // No real backend is ever going to ack anything (#54): the base
  // implementation would otherwise register a real 15s ack-timeout Timer
  // that outlives the widget tree whenever a test's Outbox/pending-reads
  // drainer fires on this "connected" socket, failing the test framework's
  // no-pending-timers invariant. Failing fast instead mirrors what actually
  // happens with no backend there, and the drainers already treat a failed
  // ack as "stop, the next connect resumes it" rather than spinning.
  @override
  Future emitWithAckAsync(
    String event,
    dynamic data, {
    Function? ack,
    bool binary = false,
  }) {
    return Future.error(StateError('no backend to ack $event'));
  }

  @override
  void dispose() {
    connected = false;
    clearListeners();
  }
}

/// A [SocketFactory] for widget tests: connects instantly, in memory, with
/// no real backend involved.
SocketFactory fakeSocketFactory() => () =>
    _FakeSocket(Manager(uri: 'http://fake', options: {'autoConnect': false}));
