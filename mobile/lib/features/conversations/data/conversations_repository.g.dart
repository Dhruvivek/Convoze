// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversations_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(conversationsRepository)
final conversationsRepositoryProvider = ConversationsRepositoryProvider._();

final class ConversationsRepositoryProvider
    extends
        $FunctionalProvider<
          ConversationsRepository,
          ConversationsRepository,
          ConversationsRepository
        >
    with $Provider<ConversationsRepository> {
  ConversationsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationsRepositoryHash();

  @$internal
  @override
  $ProviderElement<ConversationsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConversationsRepository create(Ref ref) {
    return conversationsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationsRepository>(value),
    );
  }
}

String _$conversationsRepositoryHash() =>
    r'306ad80510e8e896ed1db4e93b6e8a2b767ebe0c';

/// The live conversation list for the signed-in User — empty (rather than an
/// error) while signed out, since nothing should ever try to read it then.

@ProviderFor(conversationList)
final conversationListProvider = ConversationListFamily._();

/// The live conversation list for the signed-in User — empty (rather than an
/// error) while signed out, since nothing should ever try to read it then.

final class ConversationListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<ConversationListItem>>,
          List<ConversationListItem>,
          Stream<List<ConversationListItem>>
        >
    with
        $FutureModifier<List<ConversationListItem>>,
        $StreamProvider<List<ConversationListItem>> {
  /// The live conversation list for the signed-in User — empty (rather than an
  /// error) while signed out, since nothing should ever try to read it then.
  ConversationListProvider._({
    required ConversationListFamily super.from,
    required bool super.argument,
  }) : super(
         retry: null,
         name: r'conversationListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$conversationListHash();

  @override
  String toString() {
    return r'conversationListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<ConversationListItem>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<ConversationListItem>> create(Ref ref) {
    final argument = this.argument as bool;
    return conversationList(ref, archived: argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationListHash() => r'5d9198d670f2aa2124b25bcf991f5ff1b30e6f13';

/// The live conversation list for the signed-in User — empty (rather than an
/// error) while signed out, since nothing should ever try to read it then.

final class ConversationListFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<ConversationListItem>>, bool> {
  ConversationListFamily._()
    : super(
        retry: null,
        name: r'conversationListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The live conversation list for the signed-in User — empty (rather than an
  /// error) while signed out, since nothing should ever try to read it then.

  ConversationListProvider call({bool archived = false}) =>
      ConversationListProvider._(argument: archived, from: this);

  @override
  String toString() => r'conversationListProvider';
}
