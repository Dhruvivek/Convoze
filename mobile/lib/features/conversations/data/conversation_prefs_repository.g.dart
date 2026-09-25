// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_prefs_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(conversationPrefsRepository)
final conversationPrefsRepositoryProvider =
    ConversationPrefsRepositoryProvider._();

final class ConversationPrefsRepositoryProvider
    extends
        $FunctionalProvider<
          ConversationPrefsRepository,
          ConversationPrefsRepository,
          ConversationPrefsRepository
        >
    with $Provider<ConversationPrefsRepository> {
  ConversationPrefsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'conversationPrefsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$conversationPrefsRepositoryHash();

  @$internal
  @override
  $ProviderElement<ConversationPrefsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConversationPrefsRepository create(Ref ref) {
    return conversationPrefsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationPrefsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationPrefsRepository>(value),
    );
  }
}

String _$conversationPrefsRepositoryHash() =>
    r'047e7ab9f5c47b9f2c9edd6956bef5b2659ab4ff';
