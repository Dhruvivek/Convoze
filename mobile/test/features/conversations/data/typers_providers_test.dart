import 'package:convoze/core/storage/token_store.dart';
import 'package:convoze/features/conversations/data/typers_providers.dart';
import 'package:convoze/features/conversations/data/typing_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:socket_io_client/src/manager.dart';

const conversationId = 'conv-1';
const other = 'user-other';

io.Socket _fakeSocket() =>
    io.Socket(Manager(uri: 'http://fake', options: {'autoConnect': false}), '/', const {});

void main() {
  late TypingRepository repository;
  late io.Socket socket;
  late ProviderContainer container;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'user': '{"id":"user-me","phoneNumber":"+14155550100","displayName":"Me"}',
    });
    repository = TypingRepository(tokenStore: TokenStore(const FlutterSecureStorage()));
    socket = _fakeSocket();
    repository.attach(socket);
    container = ProviderContainer(
      overrides: [typingRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    // See `presence_providers_test.dart`'s own note: a `StreamProvider` built
    // for the first time inside a bare `container.read` is still
    // `AsyncLoading`, so a test that emits then reads once would otherwise
    // race its own setup.
    container.listen(typersMapProvider, (_, _) {});
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('empty for a Conversation nobody is typing in', () async {
    await settle();

    expect(container.read(typersProvider(conversationId)), isEmpty);
  });

  test("lists a typer once their typing event arrives, and only for that Conversation", () async {
    socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
    await settle();

    expect(container.read(typersProvider(conversationId)), {other});
    expect(container.read(typersProvider('conv-2')), isEmpty);
  });

  test('drops a typer once stopTyping arrives', () async {
    socket.emitReserved('typing', {'conversationId': conversationId, 'userId': other});
    await settle();
    socket.emitReserved('stopTyping', {'conversationId': conversationId, 'userId': other});
    await settle();

    expect(container.read(typersProvider(conversationId)), isEmpty);
  });
}
