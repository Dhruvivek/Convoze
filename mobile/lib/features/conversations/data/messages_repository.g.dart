// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'messages_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(messagesRepository)
final messagesRepositoryProvider = MessagesRepositoryProvider._();

final class MessagesRepositoryProvider
    extends $FunctionalProvider<MessagesRepository, MessagesRepository, MessagesRepository>
    with $Provider<MessagesRepository> {
  MessagesRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'messagesRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$messagesRepositoryHash();

  @$internal
  @override
  $ProviderElement<MessagesRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MessagesRepository create(Ref ref) {
    return messagesRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MessagesRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MessagesRepository>(value),
    );
  }
}

String _$messagesRepositoryHash() => r'28f6b9ebd2c5a624264a88d065639781d42870e7';

/// The live thread for [conversationId] — empty (rather than an error) while
/// signed out, same reasoning as `conversationList`.

@ProviderFor(chatMessages)
final chatMessagesProvider = ChatMessagesFamily._();

/// The live thread for [conversationId] — empty (rather than an error) while
/// signed out, same reasoning as `conversationList`.

final class ChatMessagesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<LocalChatMessage>>,
          List<LocalChatMessage>,
          Stream<List<LocalChatMessage>>
        >
    with $FutureModifier<List<LocalChatMessage>>, $StreamProvider<List<LocalChatMessage>> {
  /// The live thread for [conversationId] — empty (rather than an error) while
  /// signed out, same reasoning as `conversationList`.
  ChatMessagesProvider._({required ChatMessagesFamily super.from, required String super.argument})
    : super(
        retry: null,
        name: r'chatMessagesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$chatMessagesHash();

  @override
  String toString() {
    return r'chatMessagesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<LocalChatMessage>> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<List<LocalChatMessage>> create(Ref ref) {
    final argument = this.argument as String;
    return chatMessages(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatMessagesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatMessagesHash() => r'00e492520120b16dfc5d73e6c19574a117b9883a';

/// The live thread for [conversationId] — empty (rather than an error) while
/// signed out, same reasoning as `conversationList`.

final class ChatMessagesFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<LocalChatMessage>>, String> {
  ChatMessagesFamily._()
    : super(
        retry: null,
        name: r'chatMessagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The live thread for [conversationId] — empty (rather than an error) while
  /// signed out, same reasoning as `conversationList`.

  ChatMessagesProvider call(String conversationId) =>
      ChatMessagesProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'chatMessagesProvider';
}
