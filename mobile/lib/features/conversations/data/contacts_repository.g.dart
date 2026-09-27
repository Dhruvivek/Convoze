// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contacts_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(contactsRepository)
final contactsRepositoryProvider = ContactsRepositoryProvider._();

final class ContactsRepositoryProvider
    extends
        $FunctionalProvider<
          ContactsRepository,
          ContactsRepository,
          ContactsRepository
        >
    with $Provider<ContactsRepository> {
  ContactsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contactsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contactsRepositoryHash();

  @$internal
  @override
  $ProviderElement<ContactsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContactsRepository create(Ref ref) {
    return contactsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContactsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContactsRepository>(value),
    );
  }
}

String _$contactsRepositoryHash() =>
    r'64ebd4fe662d4d55d17323a9351a2290cc1b4ecf';

/// The Contacts tab / New conversation picker's data source: the Device's
/// address book, matched against registered Users. Throws
/// [ContactsPermissionException] when access hasn't been granted, or a
/// [ContactsFailure] when the match request itself fails.

@ProviderFor(contacts)
final contactsProvider = ContactsProvider._();

/// The Contacts tab / New conversation picker's data source: the Device's
/// address book, matched against registered Users. Throws
/// [ContactsPermissionException] when access hasn't been granted, or a
/// [ContactsFailure] when the match request itself fails.

final class ContactsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<User>>,
          List<User>,
          FutureOr<List<User>>
        >
    with $FutureModifier<List<User>>, $FutureProvider<List<User>> {
  /// The Contacts tab / New conversation picker's data source: the Device's
  /// address book, matched against registered Users. Throws
  /// [ContactsPermissionException] when access hasn't been granted, or a
  /// [ContactsFailure] when the match request itself fails.
  ContactsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contactsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contactsHash();

  @$internal
  @override
  $FutureProviderElement<List<User>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<User>> create(Ref ref) {
    return contacts(ref);
  }
}

String _$contactsHash() => r'0143e64c8348f0bed3ada45db901892e9f1fac58';
