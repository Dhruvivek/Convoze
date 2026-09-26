// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_thread_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The chat screen's merged, tick-derived message list (#53/#55):
/// recombines whenever any of the three underlying replica streams change —
/// Riverpod's own dependency tracking doing the work an explicit
/// `combineLatest` would elsewhere.

@ProviderFor(chatMessages)
final chatMessagesProvider = ChatMessagesFamily._();

/// The chat screen's merged, tick-derived message list (#53/#55):
/// recombines whenever any of the three underlying replica streams change —
/// Riverpod's own dependency tracking doing the work an explicit
/// `combineLatest` would elsewhere.

final class ChatMessagesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ChatMessageView>>,
          List<ChatMessageView>,
          FutureOr<List<ChatMessageView>>
        >
    with
        $FutureModifier<List<ChatMessageView>>,
        $FutureProvider<List<ChatMessageView>> {
  /// The chat screen's merged, tick-derived message list (#53/#55):
  /// recombines whenever any of the three underlying replica streams change —
  /// Riverpod's own dependency tracking doing the work an explicit
  /// `combineLatest` would elsewhere.
  ChatMessagesProvider._({
    required ChatMessagesFamily super.from,
    required String super.argument,
  }) : super(
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
  $FutureProviderElement<List<ChatMessageView>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<ChatMessageView>> create(Ref ref) {
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

String _$chatMessagesHash() => r'5f6e802ac3f5f73eafc6fc2561997ae9a3f4ac1c';

/// The chat screen's merged, tick-derived message list (#53/#55):
/// recombines whenever any of the three underlying replica streams change —
/// Riverpod's own dependency tracking doing the work an explicit
/// `combineLatest` would elsewhere.

final class ChatMessagesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<ChatMessageView>>, String> {
  ChatMessagesFamily._()
    : super(
        retry: null,
        name: r'chatMessagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The chat screen's merged, tick-derived message list (#53/#55):
  /// recombines whenever any of the three underlying replica streams change —
  /// Riverpod's own dependency tracking doing the work an explicit
  /// `combineLatest` would elsewhere.

  ChatMessagesProvider call(String conversationId) =>
      ChatMessagesProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'chatMessagesProvider';
}

/// The chat screen header's title: the other Participant's name for a
/// direct chat, the Conversation's name for a group.

@ProviderFor(chatThreadTitle)
final chatThreadTitleProvider = ChatThreadTitleFamily._();

/// The chat screen header's title: the other Participant's name for a
/// direct chat, the Conversation's name for a group.

final class ChatThreadTitleProvider
    extends $FunctionalProvider<AsyncValue<String>, String, FutureOr<String>>
    with $FutureModifier<String>, $FutureProvider<String> {
  /// The chat screen header's title: the other Participant's name for a
  /// direct chat, the Conversation's name for a group.
  ChatThreadTitleProvider._({
    required ChatThreadTitleFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatThreadTitleProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatThreadTitleHash();

  @override
  String toString() {
    return r'chatThreadTitleProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<String> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<String> create(Ref ref) {
    final argument = this.argument as String;
    return chatThreadTitle(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ChatThreadTitleProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatThreadTitleHash() => r'c48b6052e765c82df6c49dfe08cf57bae32cd316';

/// The chat screen header's title: the other Participant's name for a
/// direct chat, the Conversation's name for a group.

final class ChatThreadTitleFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<String>, String> {
  ChatThreadTitleFamily._()
    : super(
        retry: null,
        name: r'chatThreadTitleProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The chat screen header's title: the other Participant's name for a
  /// direct chat, the Conversation's name for a group.

  ChatThreadTitleProvider call(String conversationId) =>
      ChatThreadTitleProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'chatThreadTitleProvider';
}

/// Owns the chat screen's history-paging state (#55): the initial "fetch
/// the first page if nothing's local yet" fetch and the scroll-to-top
/// trigger both go through [loadOlder], which is guarded against
/// concurrent/redundant calls.

@ProviderFor(ChatThreadController)
final chatThreadControllerProvider = ChatThreadControllerFamily._();

/// Owns the chat screen's history-paging state (#55): the initial "fetch
/// the first page if nothing's local yet" fetch and the scroll-to-top
/// trigger both go through [loadOlder], which is guarded against
/// concurrent/redundant calls.
final class ChatThreadControllerProvider
    extends $NotifierProvider<ChatThreadController, ChatThreadState> {
  /// Owns the chat screen's history-paging state (#55): the initial "fetch
  /// the first page if nothing's local yet" fetch and the scroll-to-top
  /// trigger both go through [loadOlder], which is guarded against
  /// concurrent/redundant calls.
  ChatThreadControllerProvider._({
    required ChatThreadControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'chatThreadControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$chatThreadControllerHash();

  @override
  String toString() {
    return r'chatThreadControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ChatThreadController create() => ChatThreadController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ChatThreadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ChatThreadState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatThreadControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$chatThreadControllerHash() =>
    r'cc92497cc62b322ec4c72e1050f1f098f25c63d1';

/// Owns the chat screen's history-paging state (#55): the initial "fetch
/// the first page if nothing's local yet" fetch and the scroll-to-top
/// trigger both go through [loadOlder], which is guarded against
/// concurrent/redundant calls.

final class ChatThreadControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ChatThreadController,
          ChatThreadState,
          ChatThreadState,
          ChatThreadState,
          String
        > {
  ChatThreadControllerFamily._()
    : super(
        retry: null,
        name: r'chatThreadControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Owns the chat screen's history-paging state (#55): the initial "fetch
  /// the first page if nothing's local yet" fetch and the scroll-to-top
  /// trigger both go through [loadOlder], which is guarded against
  /// concurrent/redundant calls.

  ChatThreadControllerProvider call(String conversationId) =>
      ChatThreadControllerProvider._(argument: conversationId, from: this);

  @override
  String toString() => r'chatThreadControllerProvider';
}

/// Owns the chat screen's history-paging state (#55): the initial "fetch
/// the first page if nothing's local yet" fetch and the scroll-to-top
/// trigger both go through [loadOlder], which is guarded against
/// concurrent/redundant calls.

abstract class _$ChatThreadController extends $Notifier<ChatThreadState> {
  late final _$args = ref.$arg as String;
  String get conversationId => _$args;

  ChatThreadState build(String conversationId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ChatThreadState, ChatThreadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ChatThreadState, ChatThreadState>,
              ChatThreadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
