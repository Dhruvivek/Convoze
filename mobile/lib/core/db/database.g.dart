// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UsersTable extends Users with TableInfo<$UsersTable, LocalUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneNumberMeta = const VerificationMeta('phoneNumber');
  @override
  late final GeneratedColumn<String> phoneNumber = GeneratedColumn<String>(
    'phone_number',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _avatarUrlMeta = const VerificationMeta('avatarUrl');
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
    'avatar_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [id, phoneNumber, displayName, avatarUrl];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'users';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalUser> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('phone_number')) {
      context.handle(
        _phoneNumberMeta,
        phoneNumber.isAcceptableOrUnknown(data['phone_number']!, _phoneNumberMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneNumberMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(data['display_name']!, _displayNameMeta),
      );
    }
    if (data.containsKey('avatar_url')) {
      context.handle(
        _avatarUrlMeta,
        avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalUser(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      phoneNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone_number'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      avatarUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}avatar_url'],
      ),
    );
  }

  @override
  $UsersTable createAlias(String alias) {
    return $UsersTable(attachedDatabase, alias);
  }
}

class LocalUser extends DataClass implements Insertable<LocalUser> {
  final String id;
  final String phoneNumber;
  final String? displayName;
  final String? avatarUrl;
  const LocalUser({required this.id, required this.phoneNumber, this.displayName, this.avatarUrl});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['phone_number'] = Variable<String>(phoneNumber);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    return map;
  }

  UsersCompanion toCompanion(bool nullToAbsent) {
    return UsersCompanion(
      id: Value(id),
      phoneNumber: Value(phoneNumber),
      displayName: displayName == null && nullToAbsent ? const Value.absent() : Value(displayName),
      avatarUrl: avatarUrl == null && nullToAbsent ? const Value.absent() : Value(avatarUrl),
    );
  }

  factory LocalUser.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalUser(
      id: serializer.fromJson<String>(json['id']),
      phoneNumber: serializer.fromJson<String>(json['phoneNumber']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'phoneNumber': serializer.toJson<String>(phoneNumber),
      'displayName': serializer.toJson<String?>(displayName),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
    };
  }

  LocalUser copyWith({
    String? id,
    String? phoneNumber,
    Value<String?> displayName = const Value.absent(),
    Value<String?> avatarUrl = const Value.absent(),
  }) => LocalUser(
    id: id ?? this.id,
    phoneNumber: phoneNumber ?? this.phoneNumber,
    displayName: displayName.present ? displayName.value : this.displayName,
    avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
  );
  LocalUser copyWithCompanion(UsersCompanion data) {
    return LocalUser(
      id: data.id.present ? data.id.value : this.id,
      phoneNumber: data.phoneNumber.present ? data.phoneNumber.value : this.phoneNumber,
      displayName: data.displayName.present ? data.displayName.value : this.displayName,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalUser(')
          ..write('id: $id, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, phoneNumber, displayName, avatarUrl);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalUser &&
          other.id == this.id &&
          other.phoneNumber == this.phoneNumber &&
          other.displayName == this.displayName &&
          other.avatarUrl == this.avatarUrl);
}

class UsersCompanion extends UpdateCompanion<LocalUser> {
  final Value<String> id;
  final Value<String> phoneNumber;
  final Value<String?> displayName;
  final Value<String?> avatarUrl;
  final Value<int> rowid;
  const UsersCompanion({
    this.id = const Value.absent(),
    this.phoneNumber = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UsersCompanion.insert({
    required String id,
    required String phoneNumber,
    this.displayName = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       phoneNumber = Value(phoneNumber);
  static Insertable<LocalUser> custom({
    Expression<String>? id,
    Expression<String>? phoneNumber,
    Expression<String>? displayName,
    Expression<String>? avatarUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (displayName != null) 'display_name': displayName,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UsersCompanion copyWith({
    Value<String>? id,
    Value<String>? phoneNumber,
    Value<String?>? displayName,
    Value<String?>? avatarUrl,
    Value<int>? rowid,
  }) {
    return UsersCompanion(
      id: id ?? this.id,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (phoneNumber.present) {
      map['phone_number'] = Variable<String>(phoneNumber.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UsersCompanion(')
          ..write('id: $id, ')
          ..write('phoneNumber: $phoneNumber, ')
          ..write('displayName: $displayName, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConversationsTable extends Conversations with TableInfo<$ConversationsTable, Conversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdByIdMeta = const VerificationMeta('createdById');
  @override
  late final GeneratedColumn<String> createdById = GeneratedColumn<String>(
    'created_by_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _leftMeta = const VerificationMeta('left');
  @override
  late final GeneratedColumn<bool> left = GeneratedColumn<bool>(
    'left',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("left" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _pinnedAtMeta = const VerificationMeta('pinnedAt');
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
    'pinned_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta('archivedAt');
  @override
  late final GeneratedColumn<DateTime> archivedAt = GeneratedColumn<DateTime>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mutedUntilMeta = const VerificationMeta('mutedUntil');
  @override
  late final GeneratedColumn<DateTime> mutedUntil = GeneratedColumn<DateTime>(
    'muted_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hiddenAtMeta = const VerificationMeta('hiddenAt');
  @override
  late final GeneratedColumn<DateTime> hiddenAt = GeneratedColumn<DateTime>(
    'hidden_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _historyClearedMessageIdMeta = const VerificationMeta(
    'historyClearedMessageId',
  );
  @override
  late final GeneratedColumn<String> historyClearedMessageId = GeneratedColumn<String>(
    'history_cleared_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    name,
    createdById,
    createdAt,
    unreadCount,
    left,
    pinnedAt,
    archivedAt,
    mutedUntil,
    hiddenAt,
    historyClearedMessageId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Conversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(_typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(_nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    }
    if (data.containsKey('created_by_id')) {
      context.handle(
        _createdByIdMeta,
        createdById.isAcceptableOrUnknown(data['created_by_id']!, _createdByIdMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(data['unread_count']!, _unreadCountMeta),
      );
    }
    if (data.containsKey('left')) {
      context.handle(_leftMeta, left.isAcceptableOrUnknown(data['left']!, _leftMeta));
    }
    if (data.containsKey('pinned_at')) {
      context.handle(
        _pinnedAtMeta,
        pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('muted_until')) {
      context.handle(
        _mutedUntilMeta,
        mutedUntil.isAcceptableOrUnknown(data['muted_until']!, _mutedUntilMeta),
      );
    }
    if (data.containsKey('hidden_at')) {
      context.handle(
        _hiddenAtMeta,
        hiddenAt.isAcceptableOrUnknown(data['hidden_at']!, _hiddenAtMeta),
      );
    }
    if (data.containsKey('history_cleared_message_id')) {
      context.handle(
        _historyClearedMessageIdMeta,
        historyClearedMessageId.isAcceptableOrUnknown(
          data['history_cleared_message_id']!,
          _historyClearedMessageIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Conversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Conversation(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      type: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      name: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}name']),
      createdById: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}created_by_id'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      ),
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
      left: attachedDatabase.typeMapping.read(DriftSqlType.bool, data['${effectivePrefix}left'])!,
      pinnedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}pinned_at'],
      ),
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}archived_at'],
      ),
      mutedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}muted_until'],
      ),
      hiddenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}hidden_at'],
      ),
      historyClearedMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}history_cleared_message_id'],
      ),
    );
  }

  @override
  $ConversationsTable createAlias(String alias) {
    return $ConversationsTable(attachedDatabase, alias);
  }
}

class Conversation extends DataClass implements Insertable<Conversation> {
  final String id;

  /// `'direct'` or `'group'`.
  final String type;
  final String? name;
  final String? createdById;

  /// Null when this row came from `GET /conversations` (#50's list payload
  /// doesn't carry it) rather than a live `conversation.joined` Update
  /// (which does); nothing reads it, so this is harmless.
  final DateTime? createdAt;
  final int unreadCount;

  /// Set once this User's Participant row carries a `leftAt` (ADR 0009: a
  /// left Conversation stays, read-only, rather than disappearing).
  final bool left;

  /// Conversation preferences (#45, ADR 0009): mirrored from the caller's own
  /// `Participant` row on the server, never derived locally. `mutedUntil` in
  /// the past just means "not muted" — there's no unmute job, the client
  /// compares against now wherever it's shown.
  final DateTime? pinnedAt;
  final DateTime? archivedAt;
  final DateTime? mutedUntil;
  final DateTime? hiddenAt;

  /// The newest Message id (as of the last clear) at or before which this
  /// User's own view of the history is cut off. The sync engine deletes
  /// local Messages at or before it as soon as it applies this.
  final String? historyClearedMessageId;
  const Conversation({
    required this.id,
    required this.type,
    this.name,
    this.createdById,
    this.createdAt,
    required this.unreadCount,
    required this.left,
    this.pinnedAt,
    this.archivedAt,
    this.mutedUntil,
    this.hiddenAt,
    this.historyClearedMessageId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || name != null) {
      map['name'] = Variable<String>(name);
    }
    if (!nullToAbsent || createdById != null) {
      map['created_by_id'] = Variable<String>(createdById);
    }
    if (!nullToAbsent || createdAt != null) {
      map['created_at'] = Variable<DateTime>(createdAt);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['left'] = Variable<bool>(left);
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt);
    }
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<DateTime>(archivedAt);
    }
    if (!nullToAbsent || mutedUntil != null) {
      map['muted_until'] = Variable<DateTime>(mutedUntil);
    }
    if (!nullToAbsent || hiddenAt != null) {
      map['hidden_at'] = Variable<DateTime>(hiddenAt);
    }
    if (!nullToAbsent || historyClearedMessageId != null) {
      map['history_cleared_message_id'] = Variable<String>(historyClearedMessageId);
    }
    return map;
  }

  ConversationsCompanion toCompanion(bool nullToAbsent) {
    return ConversationsCompanion(
      id: Value(id),
      type: Value(type),
      name: name == null && nullToAbsent ? const Value.absent() : Value(name),
      createdById: createdById == null && nullToAbsent ? const Value.absent() : Value(createdById),
      createdAt: createdAt == null && nullToAbsent ? const Value.absent() : Value(createdAt),
      unreadCount: Value(unreadCount),
      left: Value(left),
      pinnedAt: pinnedAt == null && nullToAbsent ? const Value.absent() : Value(pinnedAt),
      archivedAt: archivedAt == null && nullToAbsent ? const Value.absent() : Value(archivedAt),
      mutedUntil: mutedUntil == null && nullToAbsent ? const Value.absent() : Value(mutedUntil),
      hiddenAt: hiddenAt == null && nullToAbsent ? const Value.absent() : Value(hiddenAt),
      historyClearedMessageId: historyClearedMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(historyClearedMessageId),
    );
  }

  factory Conversation.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Conversation(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      name: serializer.fromJson<String?>(json['name']),
      createdById: serializer.fromJson<String?>(json['createdById']),
      createdAt: serializer.fromJson<DateTime?>(json['createdAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      left: serializer.fromJson<bool>(json['left']),
      pinnedAt: serializer.fromJson<DateTime?>(json['pinnedAt']),
      archivedAt: serializer.fromJson<DateTime?>(json['archivedAt']),
      mutedUntil: serializer.fromJson<DateTime?>(json['mutedUntil']),
      hiddenAt: serializer.fromJson<DateTime?>(json['hiddenAt']),
      historyClearedMessageId: serializer.fromJson<String?>(json['historyClearedMessageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'name': serializer.toJson<String?>(name),
      'createdById': serializer.toJson<String?>(createdById),
      'createdAt': serializer.toJson<DateTime?>(createdAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'left': serializer.toJson<bool>(left),
      'pinnedAt': serializer.toJson<DateTime?>(pinnedAt),
      'archivedAt': serializer.toJson<DateTime?>(archivedAt),
      'mutedUntil': serializer.toJson<DateTime?>(mutedUntil),
      'hiddenAt': serializer.toJson<DateTime?>(hiddenAt),
      'historyClearedMessageId': serializer.toJson<String?>(historyClearedMessageId),
    };
  }

  Conversation copyWith({
    String? id,
    String? type,
    Value<String?> name = const Value.absent(),
    Value<String?> createdById = const Value.absent(),
    Value<DateTime?> createdAt = const Value.absent(),
    int? unreadCount,
    bool? left,
    Value<DateTime?> pinnedAt = const Value.absent(),
    Value<DateTime?> archivedAt = const Value.absent(),
    Value<DateTime?> mutedUntil = const Value.absent(),
    Value<DateTime?> hiddenAt = const Value.absent(),
    Value<String?> historyClearedMessageId = const Value.absent(),
  }) => Conversation(
    id: id ?? this.id,
    type: type ?? this.type,
    name: name.present ? name.value : this.name,
    createdById: createdById.present ? createdById.value : this.createdById,
    createdAt: createdAt.present ? createdAt.value : this.createdAt,
    unreadCount: unreadCount ?? this.unreadCount,
    left: left ?? this.left,
    pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    mutedUntil: mutedUntil.present ? mutedUntil.value : this.mutedUntil,
    hiddenAt: hiddenAt.present ? hiddenAt.value : this.hiddenAt,
    historyClearedMessageId: historyClearedMessageId.present
        ? historyClearedMessageId.value
        : this.historyClearedMessageId,
  );
  Conversation copyWithCompanion(ConversationsCompanion data) {
    return Conversation(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      name: data.name.present ? data.name.value : this.name,
      createdById: data.createdById.present ? data.createdById.value : this.createdById,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      unreadCount: data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      left: data.left.present ? data.left.value : this.left,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
      archivedAt: data.archivedAt.present ? data.archivedAt.value : this.archivedAt,
      mutedUntil: data.mutedUntil.present ? data.mutedUntil.value : this.mutedUntil,
      hiddenAt: data.hiddenAt.present ? data.hiddenAt.value : this.hiddenAt,
      historyClearedMessageId: data.historyClearedMessageId.present
          ? data.historyClearedMessageId.value
          : this.historyClearedMessageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Conversation(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('createdById: $createdById, ')
          ..write('createdAt: $createdAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('left: $left, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('mutedUntil: $mutedUntil, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('historyClearedMessageId: $historyClearedMessageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    type,
    name,
    createdById,
    createdAt,
    unreadCount,
    left,
    pinnedAt,
    archivedAt,
    mutedUntil,
    hiddenAt,
    historyClearedMessageId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Conversation &&
          other.id == this.id &&
          other.type == this.type &&
          other.name == this.name &&
          other.createdById == this.createdById &&
          other.createdAt == this.createdAt &&
          other.unreadCount == this.unreadCount &&
          other.left == this.left &&
          other.pinnedAt == this.pinnedAt &&
          other.archivedAt == this.archivedAt &&
          other.mutedUntil == this.mutedUntil &&
          other.hiddenAt == this.hiddenAt &&
          other.historyClearedMessageId == this.historyClearedMessageId);
}

class ConversationsCompanion extends UpdateCompanion<Conversation> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> name;
  final Value<String?> createdById;
  final Value<DateTime?> createdAt;
  final Value<int> unreadCount;
  final Value<bool> left;
  final Value<DateTime?> pinnedAt;
  final Value<DateTime?> archivedAt;
  final Value<DateTime?> mutedUntil;
  final Value<DateTime?> hiddenAt;
  final Value<String?> historyClearedMessageId;
  final Value<int> rowid;
  const ConversationsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.name = const Value.absent(),
    this.createdById = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.left = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.mutedUntil = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.historyClearedMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConversationsCompanion.insert({
    required String id,
    required String type,
    this.name = const Value.absent(),
    this.createdById = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.left = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.mutedUntil = const Value.absent(),
    this.hiddenAt = const Value.absent(),
    this.historyClearedMessageId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type);
  static Insertable<Conversation> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? name,
    Expression<String>? createdById,
    Expression<DateTime>? createdAt,
    Expression<int>? unreadCount,
    Expression<bool>? left,
    Expression<DateTime>? pinnedAt,
    Expression<DateTime>? archivedAt,
    Expression<DateTime>? mutedUntil,
    Expression<DateTime>? hiddenAt,
    Expression<String>? historyClearedMessageId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (name != null) 'name': name,
      if (createdById != null) 'created_by_id': createdById,
      if (createdAt != null) 'created_at': createdAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (left != null) 'left': left,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (mutedUntil != null) 'muted_until': mutedUntil,
      if (hiddenAt != null) 'hidden_at': hiddenAt,
      if (historyClearedMessageId != null) 'history_cleared_message_id': historyClearedMessageId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConversationsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String?>? name,
    Value<String?>? createdById,
    Value<DateTime?>? createdAt,
    Value<int>? unreadCount,
    Value<bool>? left,
    Value<DateTime?>? pinnedAt,
    Value<DateTime?>? archivedAt,
    Value<DateTime?>? mutedUntil,
    Value<DateTime?>? hiddenAt,
    Value<String?>? historyClearedMessageId,
    Value<int>? rowid,
  }) {
    return ConversationsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      unreadCount: unreadCount ?? this.unreadCount,
      left: left ?? this.left,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      archivedAt: archivedAt ?? this.archivedAt,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      hiddenAt: hiddenAt ?? this.hiddenAt,
      historyClearedMessageId: historyClearedMessageId ?? this.historyClearedMessageId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdById.present) {
      map['created_by_id'] = Variable<String>(createdById.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (left.present) {
      map['left'] = Variable<bool>(left.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<DateTime>(archivedAt.value);
    }
    if (mutedUntil.present) {
      map['muted_until'] = Variable<DateTime>(mutedUntil.value);
    }
    if (hiddenAt.present) {
      map['hidden_at'] = Variable<DateTime>(hiddenAt.value);
    }
    if (historyClearedMessageId.present) {
      map['history_cleared_message_id'] = Variable<String>(historyClearedMessageId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConversationsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('name: $name, ')
          ..write('createdById: $createdById, ')
          ..write('createdAt: $createdAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('left: $left, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('mutedUntil: $mutedUntil, ')
          ..write('hiddenAt: $hiddenAt, ')
          ..write('historyClearedMessageId: $historyClearedMessageId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ParticipantsTable extends Participants with TableInfo<$ParticipantsTable, Participant> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ParticipantsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('member'),
  );
  static const VerificationMeta _lastReadMessageIdMeta = const VerificationMeta(
    'lastReadMessageId',
  );
  @override
  late final GeneratedColumn<String> lastReadMessageId = GeneratedColumn<String>(
    'last_read_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastDeliveredMessageIdMeta = const VerificationMeta(
    'lastDeliveredMessageId',
  );
  @override
  late final GeneratedColumn<String> lastDeliveredMessageId = GeneratedColumn<String>(
    'last_delivered_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leftAtMeta = const VerificationMeta('leftAt');
  @override
  late final GeneratedColumn<DateTime> leftAt = GeneratedColumn<DateTime>(
    'left_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    userId,
    role,
    lastReadMessageId,
    lastDeliveredMessageId,
    leftAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'participants';
  @override
  VerificationContext validateIntegrity(
    Insertable<Participant> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(data['conversation_id']!, _conversationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta, userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(_roleMeta, role.isAcceptableOrUnknown(data['role']!, _roleMeta));
    }
    if (data.containsKey('last_read_message_id')) {
      context.handle(
        _lastReadMessageIdMeta,
        lastReadMessageId.isAcceptableOrUnknown(
          data['last_read_message_id']!,
          _lastReadMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('last_delivered_message_id')) {
      context.handle(
        _lastDeliveredMessageIdMeta,
        lastDeliveredMessageId.isAcceptableOrUnknown(
          data['last_delivered_message_id']!,
          _lastDeliveredMessageIdMeta,
        ),
      );
    }
    if (data.containsKey('left_at')) {
      context.handle(_leftAtMeta, leftAt.isAcceptableOrUnknown(data['left_at']!, _leftAtMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, userId};
  @override
  Participant map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Participant(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      role: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}role'])!,
      lastReadMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_read_message_id'],
      ),
      lastDeliveredMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_delivered_message_id'],
      ),
      leftAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}left_at'],
      ),
    );
  }

  @override
  $ParticipantsTable createAlias(String alias) {
    return $ParticipantsTable(attachedDatabase, alias);
  }
}

class Participant extends DataClass implements Insertable<Participant> {
  final String conversationId;
  final String userId;
  final String role;
  final String? lastReadMessageId;
  final String? lastDeliveredMessageId;
  final DateTime? leftAt;
  const Participant({
    required this.conversationId,
    required this.userId,
    required this.role,
    this.lastReadMessageId,
    this.lastDeliveredMessageId,
    this.leftAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['user_id'] = Variable<String>(userId);
    map['role'] = Variable<String>(role);
    if (!nullToAbsent || lastReadMessageId != null) {
      map['last_read_message_id'] = Variable<String>(lastReadMessageId);
    }
    if (!nullToAbsent || lastDeliveredMessageId != null) {
      map['last_delivered_message_id'] = Variable<String>(lastDeliveredMessageId);
    }
    if (!nullToAbsent || leftAt != null) {
      map['left_at'] = Variable<DateTime>(leftAt);
    }
    return map;
  }

  ParticipantsCompanion toCompanion(bool nullToAbsent) {
    return ParticipantsCompanion(
      conversationId: Value(conversationId),
      userId: Value(userId),
      role: Value(role),
      lastReadMessageId: lastReadMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadMessageId),
      lastDeliveredMessageId: lastDeliveredMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDeliveredMessageId),
      leftAt: leftAt == null && nullToAbsent ? const Value.absent() : Value(leftAt),
    );
  }

  factory Participant.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Participant(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      userId: serializer.fromJson<String>(json['userId']),
      role: serializer.fromJson<String>(json['role']),
      lastReadMessageId: serializer.fromJson<String?>(json['lastReadMessageId']),
      lastDeliveredMessageId: serializer.fromJson<String?>(json['lastDeliveredMessageId']),
      leftAt: serializer.fromJson<DateTime?>(json['leftAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'userId': serializer.toJson<String>(userId),
      'role': serializer.toJson<String>(role),
      'lastReadMessageId': serializer.toJson<String?>(lastReadMessageId),
      'lastDeliveredMessageId': serializer.toJson<String?>(lastDeliveredMessageId),
      'leftAt': serializer.toJson<DateTime?>(leftAt),
    };
  }

  Participant copyWith({
    String? conversationId,
    String? userId,
    String? role,
    Value<String?> lastReadMessageId = const Value.absent(),
    Value<String?> lastDeliveredMessageId = const Value.absent(),
    Value<DateTime?> leftAt = const Value.absent(),
  }) => Participant(
    conversationId: conversationId ?? this.conversationId,
    userId: userId ?? this.userId,
    role: role ?? this.role,
    lastReadMessageId: lastReadMessageId.present ? lastReadMessageId.value : this.lastReadMessageId,
    lastDeliveredMessageId: lastDeliveredMessageId.present
        ? lastDeliveredMessageId.value
        : this.lastDeliveredMessageId,
    leftAt: leftAt.present ? leftAt.value : this.leftAt,
  );
  Participant copyWithCompanion(ParticipantsCompanion data) {
    return Participant(
      conversationId: data.conversationId.present ? data.conversationId.value : this.conversationId,
      userId: data.userId.present ? data.userId.value : this.userId,
      role: data.role.present ? data.role.value : this.role,
      lastReadMessageId: data.lastReadMessageId.present
          ? data.lastReadMessageId.value
          : this.lastReadMessageId,
      lastDeliveredMessageId: data.lastDeliveredMessageId.present
          ? data.lastDeliveredMessageId.value
          : this.lastDeliveredMessageId,
      leftAt: data.leftAt.present ? data.leftAt.value : this.leftAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Participant(')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('lastReadMessageId: $lastReadMessageId, ')
          ..write('lastDeliveredMessageId: $lastDeliveredMessageId, ')
          ..write('leftAt: $leftAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(conversationId, userId, role, lastReadMessageId, lastDeliveredMessageId, leftAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Participant &&
          other.conversationId == this.conversationId &&
          other.userId == this.userId &&
          other.role == this.role &&
          other.lastReadMessageId == this.lastReadMessageId &&
          other.lastDeliveredMessageId == this.lastDeliveredMessageId &&
          other.leftAt == this.leftAt);
}

class ParticipantsCompanion extends UpdateCompanion<Participant> {
  final Value<String> conversationId;
  final Value<String> userId;
  final Value<String> role;
  final Value<String?> lastReadMessageId;
  final Value<String?> lastDeliveredMessageId;
  final Value<DateTime?> leftAt;
  final Value<int> rowid;
  const ParticipantsCompanion({
    this.conversationId = const Value.absent(),
    this.userId = const Value.absent(),
    this.role = const Value.absent(),
    this.lastReadMessageId = const Value.absent(),
    this.lastDeliveredMessageId = const Value.absent(),
    this.leftAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ParticipantsCompanion.insert({
    required String conversationId,
    required String userId,
    this.role = const Value.absent(),
    this.lastReadMessageId = const Value.absent(),
    this.lastDeliveredMessageId = const Value.absent(),
    this.leftAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       userId = Value(userId);
  static Insertable<Participant> custom({
    Expression<String>? conversationId,
    Expression<String>? userId,
    Expression<String>? role,
    Expression<String>? lastReadMessageId,
    Expression<String>? lastDeliveredMessageId,
    Expression<DateTime>? leftAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (userId != null) 'user_id': userId,
      if (role != null) 'role': role,
      if (lastReadMessageId != null) 'last_read_message_id': lastReadMessageId,
      if (lastDeliveredMessageId != null) 'last_delivered_message_id': lastDeliveredMessageId,
      if (leftAt != null) 'left_at': leftAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ParticipantsCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? userId,
    Value<String>? role,
    Value<String?>? lastReadMessageId,
    Value<String?>? lastDeliveredMessageId,
    Value<DateTime?>? leftAt,
    Value<int>? rowid,
  }) {
    return ParticipantsCompanion(
      conversationId: conversationId ?? this.conversationId,
      userId: userId ?? this.userId,
      role: role ?? this.role,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      lastDeliveredMessageId: lastDeliveredMessageId ?? this.lastDeliveredMessageId,
      leftAt: leftAt ?? this.leftAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (lastReadMessageId.present) {
      map['last_read_message_id'] = Variable<String>(lastReadMessageId.value);
    }
    if (lastDeliveredMessageId.present) {
      map['last_delivered_message_id'] = Variable<String>(lastDeliveredMessageId.value);
    }
    if (leftAt.present) {
      map['left_at'] = Variable<DateTime>(leftAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ParticipantsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('userId: $userId, ')
          ..write('role: $role, ')
          ..write('lastReadMessageId: $lastReadMessageId, ')
          ..write('lastDeliveredMessageId: $lastDeliveredMessageId, ')
          ..write('leftAt: $leftAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _senderIdMeta = const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
    'sender_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientMsgIdMeta = const VerificationMeta('clientMsgId');
  @override
  late final GeneratedColumn<String> clientMsgId = GeneratedColumn<String>(
    'client_msg_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta('replyToMessageId');
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkPreviewMeta = const VerificationMeta('linkPreview');
  @override
  late final GeneratedColumn<String> linkPreview = GeneratedColumn<String>(
    'link_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _contentMeta = const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reactionsMeta = const VerificationMeta('reactions');
  @override
  late final GeneratedColumn<String> reactions = GeneratedColumn<String>(
    'reactions',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _isDeletedMeta = const VerificationMeta('isDeleted');
  @override
  late final GeneratedColumn<bool> isDeleted = GeneratedColumn<bool>(
    'is_deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways('CHECK ("is_deleted" IN (0, 1))'),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _editedAtMeta = const VerificationMeta('editedAt');
  @override
  late final GeneratedColumn<DateTime> editedAt = GeneratedColumn<DateTime>(
    'edited_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaPublicIdMeta = const VerificationMeta('mediaPublicId');
  @override
  late final GeneratedColumn<String> mediaPublicId = GeneratedColumn<String>(
    'media_public_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaResourceTypeMeta = const VerificationMeta(
    'mediaResourceType',
  );
  @override
  late final GeneratedColumn<String> mediaResourceType = GeneratedColumn<String>(
    'media_resource_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaBytesMeta = const VerificationMeta('mediaBytes');
  @override
  late final GeneratedColumn<int> mediaBytes = GeneratedColumn<int>(
    'media_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaWidthMeta = const VerificationMeta('mediaWidth');
  @override
  late final GeneratedColumn<int> mediaWidth = GeneratedColumn<int>(
    'media_width',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaHeightMeta = const VerificationMeta('mediaHeight');
  @override
  late final GeneratedColumn<int> mediaHeight = GeneratedColumn<int>(
    'media_height',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaFormatMeta = const VerificationMeta('mediaFormat');
  @override
  late final GeneratedColumn<String> mediaFormat = GeneratedColumn<String>(
    'media_format',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaFileNameMeta = const VerificationMeta('mediaFileName');
  @override
  late final GeneratedColumn<String> mediaFileName = GeneratedColumn<String>(
    'media_file_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaUrlMeta = const VerificationMeta('mediaUrl');
  @override
  late final GeneratedColumn<String> mediaUrl = GeneratedColumn<String>(
    'media_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mediaThumbnailUrlMeta = const VerificationMeta(
    'mediaThumbnailUrl',
  );
  @override
  late final GeneratedColumn<String> mediaThumbnailUrl = GeneratedColumn<String>(
    'media_thumbnail_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    senderId,
    clientMsgId,
    replyToMessageId,
    linkPreview,
    type,
    content,
    reactions,
    isDeleted,
    createdAt,
    editedAt,
    mediaPublicId,
    mediaResourceType,
    mediaBytes,
    mediaWidth,
    mediaHeight,
    mediaFormat,
    mediaFileName,
    mediaUrl,
    mediaThumbnailUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance, {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(data['conversation_id']!, _conversationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(
        _senderIdMeta,
        senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta),
      );
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('client_msg_id')) {
      context.handle(
        _clientMsgIdMeta,
        clientMsgId.isAcceptableOrUnknown(data['client_msg_id']!, _clientMsgIdMeta),
      );
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(data['reply_to_message_id']!, _replyToMessageIdMeta),
      );
    }
    if (data.containsKey('link_preview')) {
      context.handle(
        _linkPreviewMeta,
        linkPreview.isAcceptableOrUnknown(data['link_preview']!, _linkPreviewMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(_typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta, content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    }
    if (data.containsKey('reactions')) {
      context.handle(
        _reactionsMeta,
        reactions.isAcceptableOrUnknown(data['reactions']!, _reactionsMeta),
      );
    }
    if (data.containsKey('is_deleted')) {
      context.handle(
        _isDeletedMeta,
        isDeleted.isAcceptableOrUnknown(data['is_deleted']!, _isDeletedMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('edited_at')) {
      context.handle(
        _editedAtMeta,
        editedAt.isAcceptableOrUnknown(data['edited_at']!, _editedAtMeta),
      );
    }
    if (data.containsKey('media_public_id')) {
      context.handle(
        _mediaPublicIdMeta,
        mediaPublicId.isAcceptableOrUnknown(data['media_public_id']!, _mediaPublicIdMeta),
      );
    }
    if (data.containsKey('media_resource_type')) {
      context.handle(
        _mediaResourceTypeMeta,
        mediaResourceType.isAcceptableOrUnknown(
          data['media_resource_type']!,
          _mediaResourceTypeMeta,
        ),
      );
    }
    if (data.containsKey('media_bytes')) {
      context.handle(
        _mediaBytesMeta,
        mediaBytes.isAcceptableOrUnknown(data['media_bytes']!, _mediaBytesMeta),
      );
    }
    if (data.containsKey('media_width')) {
      context.handle(
        _mediaWidthMeta,
        mediaWidth.isAcceptableOrUnknown(data['media_width']!, _mediaWidthMeta),
      );
    }
    if (data.containsKey('media_height')) {
      context.handle(
        _mediaHeightMeta,
        mediaHeight.isAcceptableOrUnknown(data['media_height']!, _mediaHeightMeta),
      );
    }
    if (data.containsKey('media_format')) {
      context.handle(
        _mediaFormatMeta,
        mediaFormat.isAcceptableOrUnknown(data['media_format']!, _mediaFormatMeta),
      );
    }
    if (data.containsKey('media_file_name')) {
      context.handle(
        _mediaFileNameMeta,
        mediaFileName.isAcceptableOrUnknown(data['media_file_name']!, _mediaFileNameMeta),
      );
    }
    if (data.containsKey('media_url')) {
      context.handle(
        _mediaUrlMeta,
        mediaUrl.isAcceptableOrUnknown(data['media_url']!, _mediaUrlMeta),
      );
    }
    if (data.containsKey('media_thumbnail_url')) {
      context.handle(
        _mediaThumbnailUrlMeta,
        mediaThumbnailUrl.isAcceptableOrUnknown(
          data['media_thumbnail_url']!,
          _mediaThumbnailUrlMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      senderId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sender_id'],
      )!,
      clientMsgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_msg_id'],
      ),
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      linkPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_preview'],
      ),
      type: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      ),
      reactions: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reactions'],
      )!,
      isDeleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_deleted'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      editedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}edited_at'],
      ),
      mediaPublicId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_public_id'],
      ),
      mediaResourceType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_resource_type'],
      ),
      mediaBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_bytes'],
      ),
      mediaWidth: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_width'],
      ),
      mediaHeight: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}media_height'],
      ),
      mediaFormat: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_format'],
      ),
      mediaFileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_file_name'],
      ),
      mediaUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_url'],
      ),
      mediaThumbnailUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_thumbnail_url'],
      ),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String conversationId;
  final String senderId;

  /// The id this Message was sent under from this Device (or another of this
  /// User's Devices), used to dedupe against a confirming `message.new`
  /// against an Outbox row. Null for a Message from someone else.
  final String? clientMsgId;
  final String? replyToMessageId;

  /// JSON `{url, title, description}` or null.
  final String? linkPreview;
  final String type;
  final String? content;

  /// JSON `[{userId, emoji}]` — the current list, not a diff (mirrors
  /// `reaction.changed`'s hydration).
  final String reactions;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime? editedAt;

  /// Media (photos/documents, `type` `image`/`file`): the Cloudinary asset
  /// reference plus display metadata, mirrored from `messagePayload()`.
  /// `mediaUrl`/`mediaThumbnailUrl` are the last signed delivery URLs the
  /// server handed back — possibly stale (ADR 0002: signed URLs expire
  /// ~1h), kept anyway so a media bubble has something to show offline.
  final String? mediaPublicId;
  final String? mediaResourceType;
  final int? mediaBytes;
  final int? mediaWidth;
  final int? mediaHeight;
  final String? mediaFormat;
  final String? mediaFileName;
  final String? mediaUrl;
  final String? mediaThumbnailUrl;
  const Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    this.clientMsgId,
    this.replyToMessageId,
    this.linkPreview,
    required this.type,
    this.content,
    required this.reactions,
    required this.isDeleted,
    required this.createdAt,
    this.editedAt,
    this.mediaPublicId,
    this.mediaResourceType,
    this.mediaBytes,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaFormat,
    this.mediaFileName,
    this.mediaUrl,
    this.mediaThumbnailUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['sender_id'] = Variable<String>(senderId);
    if (!nullToAbsent || clientMsgId != null) {
      map['client_msg_id'] = Variable<String>(clientMsgId);
    }
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    if (!nullToAbsent || linkPreview != null) {
      map['link_preview'] = Variable<String>(linkPreview);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || content != null) {
      map['content'] = Variable<String>(content);
    }
    map['reactions'] = Variable<String>(reactions);
    map['is_deleted'] = Variable<bool>(isDeleted);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || editedAt != null) {
      map['edited_at'] = Variable<DateTime>(editedAt);
    }
    if (!nullToAbsent || mediaPublicId != null) {
      map['media_public_id'] = Variable<String>(mediaPublicId);
    }
    if (!nullToAbsent || mediaResourceType != null) {
      map['media_resource_type'] = Variable<String>(mediaResourceType);
    }
    if (!nullToAbsent || mediaBytes != null) {
      map['media_bytes'] = Variable<int>(mediaBytes);
    }
    if (!nullToAbsent || mediaWidth != null) {
      map['media_width'] = Variable<int>(mediaWidth);
    }
    if (!nullToAbsent || mediaHeight != null) {
      map['media_height'] = Variable<int>(mediaHeight);
    }
    if (!nullToAbsent || mediaFormat != null) {
      map['media_format'] = Variable<String>(mediaFormat);
    }
    if (!nullToAbsent || mediaFileName != null) {
      map['media_file_name'] = Variable<String>(mediaFileName);
    }
    if (!nullToAbsent || mediaUrl != null) {
      map['media_url'] = Variable<String>(mediaUrl);
    }
    if (!nullToAbsent || mediaThumbnailUrl != null) {
      map['media_thumbnail_url'] = Variable<String>(mediaThumbnailUrl);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      senderId: Value(senderId),
      clientMsgId: clientMsgId == null && nullToAbsent ? const Value.absent() : Value(clientMsgId),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      linkPreview: linkPreview == null && nullToAbsent ? const Value.absent() : Value(linkPreview),
      type: Value(type),
      content: content == null && nullToAbsent ? const Value.absent() : Value(content),
      reactions: Value(reactions),
      isDeleted: Value(isDeleted),
      createdAt: Value(createdAt),
      editedAt: editedAt == null && nullToAbsent ? const Value.absent() : Value(editedAt),
      mediaPublicId: mediaPublicId == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaPublicId),
      mediaResourceType: mediaResourceType == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaResourceType),
      mediaBytes: mediaBytes == null && nullToAbsent ? const Value.absent() : Value(mediaBytes),
      mediaWidth: mediaWidth == null && nullToAbsent ? const Value.absent() : Value(mediaWidth),
      mediaHeight: mediaHeight == null && nullToAbsent ? const Value.absent() : Value(mediaHeight),
      mediaFormat: mediaFormat == null && nullToAbsent ? const Value.absent() : Value(mediaFormat),
      mediaFileName: mediaFileName == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaFileName),
      mediaUrl: mediaUrl == null && nullToAbsent ? const Value.absent() : Value(mediaUrl),
      mediaThumbnailUrl: mediaThumbnailUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaThumbnailUrl),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      clientMsgId: serializer.fromJson<String?>(json['clientMsgId']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      linkPreview: serializer.fromJson<String?>(json['linkPreview']),
      type: serializer.fromJson<String>(json['type']),
      content: serializer.fromJson<String?>(json['content']),
      reactions: serializer.fromJson<String>(json['reactions']),
      isDeleted: serializer.fromJson<bool>(json['isDeleted']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      editedAt: serializer.fromJson<DateTime?>(json['editedAt']),
      mediaPublicId: serializer.fromJson<String?>(json['mediaPublicId']),
      mediaResourceType: serializer.fromJson<String?>(json['mediaResourceType']),
      mediaBytes: serializer.fromJson<int?>(json['mediaBytes']),
      mediaWidth: serializer.fromJson<int?>(json['mediaWidth']),
      mediaHeight: serializer.fromJson<int?>(json['mediaHeight']),
      mediaFormat: serializer.fromJson<String?>(json['mediaFormat']),
      mediaFileName: serializer.fromJson<String?>(json['mediaFileName']),
      mediaUrl: serializer.fromJson<String?>(json['mediaUrl']),
      mediaThumbnailUrl: serializer.fromJson<String?>(json['mediaThumbnailUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'senderId': serializer.toJson<String>(senderId),
      'clientMsgId': serializer.toJson<String?>(clientMsgId),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'linkPreview': serializer.toJson<String?>(linkPreview),
      'type': serializer.toJson<String>(type),
      'content': serializer.toJson<String?>(content),
      'reactions': serializer.toJson<String>(reactions),
      'isDeleted': serializer.toJson<bool>(isDeleted),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'editedAt': serializer.toJson<DateTime?>(editedAt),
      'mediaPublicId': serializer.toJson<String?>(mediaPublicId),
      'mediaResourceType': serializer.toJson<String?>(mediaResourceType),
      'mediaBytes': serializer.toJson<int?>(mediaBytes),
      'mediaWidth': serializer.toJson<int?>(mediaWidth),
      'mediaHeight': serializer.toJson<int?>(mediaHeight),
      'mediaFormat': serializer.toJson<String?>(mediaFormat),
      'mediaFileName': serializer.toJson<String?>(mediaFileName),
      'mediaUrl': serializer.toJson<String?>(mediaUrl),
      'mediaThumbnailUrl': serializer.toJson<String?>(mediaThumbnailUrl),
    };
  }

  Message copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    Value<String?> clientMsgId = const Value.absent(),
    Value<String?> replyToMessageId = const Value.absent(),
    Value<String?> linkPreview = const Value.absent(),
    String? type,
    Value<String?> content = const Value.absent(),
    String? reactions,
    bool? isDeleted,
    DateTime? createdAt,
    Value<DateTime?> editedAt = const Value.absent(),
    Value<String?> mediaPublicId = const Value.absent(),
    Value<String?> mediaResourceType = const Value.absent(),
    Value<int?> mediaBytes = const Value.absent(),
    Value<int?> mediaWidth = const Value.absent(),
    Value<int?> mediaHeight = const Value.absent(),
    Value<String?> mediaFormat = const Value.absent(),
    Value<String?> mediaFileName = const Value.absent(),
    Value<String?> mediaUrl = const Value.absent(),
    Value<String?> mediaThumbnailUrl = const Value.absent(),
  }) => Message(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    senderId: senderId ?? this.senderId,
    clientMsgId: clientMsgId.present ? clientMsgId.value : this.clientMsgId,
    replyToMessageId: replyToMessageId.present ? replyToMessageId.value : this.replyToMessageId,
    linkPreview: linkPreview.present ? linkPreview.value : this.linkPreview,
    type: type ?? this.type,
    content: content.present ? content.value : this.content,
    reactions: reactions ?? this.reactions,
    isDeleted: isDeleted ?? this.isDeleted,
    createdAt: createdAt ?? this.createdAt,
    editedAt: editedAt.present ? editedAt.value : this.editedAt,
    mediaPublicId: mediaPublicId.present ? mediaPublicId.value : this.mediaPublicId,
    mediaResourceType: mediaResourceType.present ? mediaResourceType.value : this.mediaResourceType,
    mediaBytes: mediaBytes.present ? mediaBytes.value : this.mediaBytes,
    mediaWidth: mediaWidth.present ? mediaWidth.value : this.mediaWidth,
    mediaHeight: mediaHeight.present ? mediaHeight.value : this.mediaHeight,
    mediaFormat: mediaFormat.present ? mediaFormat.value : this.mediaFormat,
    mediaFileName: mediaFileName.present ? mediaFileName.value : this.mediaFileName,
    mediaUrl: mediaUrl.present ? mediaUrl.value : this.mediaUrl,
    mediaThumbnailUrl: mediaThumbnailUrl.present ? mediaThumbnailUrl.value : this.mediaThumbnailUrl,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present ? data.conversationId.value : this.conversationId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      clientMsgId: data.clientMsgId.present ? data.clientMsgId.value : this.clientMsgId,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      linkPreview: data.linkPreview.present ? data.linkPreview.value : this.linkPreview,
      type: data.type.present ? data.type.value : this.type,
      content: data.content.present ? data.content.value : this.content,
      reactions: data.reactions.present ? data.reactions.value : this.reactions,
      isDeleted: data.isDeleted.present ? data.isDeleted.value : this.isDeleted,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      editedAt: data.editedAt.present ? data.editedAt.value : this.editedAt,
      mediaPublicId: data.mediaPublicId.present ? data.mediaPublicId.value : this.mediaPublicId,
      mediaResourceType: data.mediaResourceType.present
          ? data.mediaResourceType.value
          : this.mediaResourceType,
      mediaBytes: data.mediaBytes.present ? data.mediaBytes.value : this.mediaBytes,
      mediaWidth: data.mediaWidth.present ? data.mediaWidth.value : this.mediaWidth,
      mediaHeight: data.mediaHeight.present ? data.mediaHeight.value : this.mediaHeight,
      mediaFormat: data.mediaFormat.present ? data.mediaFormat.value : this.mediaFormat,
      mediaFileName: data.mediaFileName.present ? data.mediaFileName.value : this.mediaFileName,
      mediaUrl: data.mediaUrl.present ? data.mediaUrl.value : this.mediaUrl,
      mediaThumbnailUrl: data.mediaThumbnailUrl.present
          ? data.mediaThumbnailUrl.value
          : this.mediaThumbnailUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('linkPreview: $linkPreview, ')
          ..write('type: $type, ')
          ..write('content: $content, ')
          ..write('reactions: $reactions, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('editedAt: $editedAt, ')
          ..write('mediaPublicId: $mediaPublicId, ')
          ..write('mediaResourceType: $mediaResourceType, ')
          ..write('mediaBytes: $mediaBytes, ')
          ..write('mediaWidth: $mediaWidth, ')
          ..write('mediaHeight: $mediaHeight, ')
          ..write('mediaFormat: $mediaFormat, ')
          ..write('mediaFileName: $mediaFileName, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('mediaThumbnailUrl: $mediaThumbnailUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    conversationId,
    senderId,
    clientMsgId,
    replyToMessageId,
    linkPreview,
    type,
    content,
    reactions,
    isDeleted,
    createdAt,
    editedAt,
    mediaPublicId,
    mediaResourceType,
    mediaBytes,
    mediaWidth,
    mediaHeight,
    mediaFormat,
    mediaFileName,
    mediaUrl,
    mediaThumbnailUrl,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.senderId == this.senderId &&
          other.clientMsgId == this.clientMsgId &&
          other.replyToMessageId == this.replyToMessageId &&
          other.linkPreview == this.linkPreview &&
          other.type == this.type &&
          other.content == this.content &&
          other.reactions == this.reactions &&
          other.isDeleted == this.isDeleted &&
          other.createdAt == this.createdAt &&
          other.editedAt == this.editedAt &&
          other.mediaPublicId == this.mediaPublicId &&
          other.mediaResourceType == this.mediaResourceType &&
          other.mediaBytes == this.mediaBytes &&
          other.mediaWidth == this.mediaWidth &&
          other.mediaHeight == this.mediaHeight &&
          other.mediaFormat == this.mediaFormat &&
          other.mediaFileName == this.mediaFileName &&
          other.mediaUrl == this.mediaUrl &&
          other.mediaThumbnailUrl == this.mediaThumbnailUrl);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<String> senderId;
  final Value<String?> clientMsgId;
  final Value<String?> replyToMessageId;
  final Value<String?> linkPreview;
  final Value<String> type;
  final Value<String?> content;
  final Value<String> reactions;
  final Value<bool> isDeleted;
  final Value<DateTime> createdAt;
  final Value<DateTime?> editedAt;
  final Value<String?> mediaPublicId;
  final Value<String?> mediaResourceType;
  final Value<int?> mediaBytes;
  final Value<int?> mediaWidth;
  final Value<int?> mediaHeight;
  final Value<String?> mediaFormat;
  final Value<String?> mediaFileName;
  final Value<String?> mediaUrl;
  final Value<String?> mediaThumbnailUrl;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.clientMsgId = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.linkPreview = const Value.absent(),
    this.type = const Value.absent(),
    this.content = const Value.absent(),
    this.reactions = const Value.absent(),
    this.isDeleted = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.editedAt = const Value.absent(),
    this.mediaPublicId = const Value.absent(),
    this.mediaResourceType = const Value.absent(),
    this.mediaBytes = const Value.absent(),
    this.mediaWidth = const Value.absent(),
    this.mediaHeight = const Value.absent(),
    this.mediaFormat = const Value.absent(),
    this.mediaFileName = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.mediaThumbnailUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String conversationId,
    required String senderId,
    this.clientMsgId = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.linkPreview = const Value.absent(),
    this.type = const Value.absent(),
    this.content = const Value.absent(),
    this.reactions = const Value.absent(),
    this.isDeleted = const Value.absent(),
    required DateTime createdAt,
    this.editedAt = const Value.absent(),
    this.mediaPublicId = const Value.absent(),
    this.mediaResourceType = const Value.absent(),
    this.mediaBytes = const Value.absent(),
    this.mediaWidth = const Value.absent(),
    this.mediaHeight = const Value.absent(),
    this.mediaFormat = const Value.absent(),
    this.mediaFileName = const Value.absent(),
    this.mediaUrl = const Value.absent(),
    this.mediaThumbnailUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       senderId = Value(senderId),
       createdAt = Value(createdAt);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<String>? senderId,
    Expression<String>? clientMsgId,
    Expression<String>? replyToMessageId,
    Expression<String>? linkPreview,
    Expression<String>? type,
    Expression<String>? content,
    Expression<String>? reactions,
    Expression<bool>? isDeleted,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? editedAt,
    Expression<String>? mediaPublicId,
    Expression<String>? mediaResourceType,
    Expression<int>? mediaBytes,
    Expression<int>? mediaWidth,
    Expression<int>? mediaHeight,
    Expression<String>? mediaFormat,
    Expression<String>? mediaFileName,
    Expression<String>? mediaUrl,
    Expression<String>? mediaThumbnailUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (senderId != null) 'sender_id': senderId,
      if (clientMsgId != null) 'client_msg_id': clientMsgId,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (linkPreview != null) 'link_preview': linkPreview,
      if (type != null) 'type': type,
      if (content != null) 'content': content,
      if (reactions != null) 'reactions': reactions,
      if (isDeleted != null) 'is_deleted': isDeleted,
      if (createdAt != null) 'created_at': createdAt,
      if (editedAt != null) 'edited_at': editedAt,
      if (mediaPublicId != null) 'media_public_id': mediaPublicId,
      if (mediaResourceType != null) 'media_resource_type': mediaResourceType,
      if (mediaBytes != null) 'media_bytes': mediaBytes,
      if (mediaWidth != null) 'media_width': mediaWidth,
      if (mediaHeight != null) 'media_height': mediaHeight,
      if (mediaFormat != null) 'media_format': mediaFormat,
      if (mediaFileName != null) 'media_file_name': mediaFileName,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (mediaThumbnailUrl != null) 'media_thumbnail_url': mediaThumbnailUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<String>? senderId,
    Value<String?>? clientMsgId,
    Value<String?>? replyToMessageId,
    Value<String?>? linkPreview,
    Value<String>? type,
    Value<String?>? content,
    Value<String>? reactions,
    Value<bool>? isDeleted,
    Value<DateTime>? createdAt,
    Value<DateTime?>? editedAt,
    Value<String?>? mediaPublicId,
    Value<String?>? mediaResourceType,
    Value<int?>? mediaBytes,
    Value<int?>? mediaWidth,
    Value<int?>? mediaHeight,
    Value<String?>? mediaFormat,
    Value<String?>? mediaFileName,
    Value<String?>? mediaUrl,
    Value<String?>? mediaThumbnailUrl,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      clientMsgId: clientMsgId ?? this.clientMsgId,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      linkPreview: linkPreview ?? this.linkPreview,
      type: type ?? this.type,
      content: content ?? this.content,
      reactions: reactions ?? this.reactions,
      isDeleted: isDeleted ?? this.isDeleted,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      mediaPublicId: mediaPublicId ?? this.mediaPublicId,
      mediaResourceType: mediaResourceType ?? this.mediaResourceType,
      mediaBytes: mediaBytes ?? this.mediaBytes,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      mediaFormat: mediaFormat ?? this.mediaFormat,
      mediaFileName: mediaFileName ?? this.mediaFileName,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaThumbnailUrl: mediaThumbnailUrl ?? this.mediaThumbnailUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (clientMsgId.present) {
      map['client_msg_id'] = Variable<String>(clientMsgId.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (linkPreview.present) {
      map['link_preview'] = Variable<String>(linkPreview.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (reactions.present) {
      map['reactions'] = Variable<String>(reactions.value);
    }
    if (isDeleted.present) {
      map['is_deleted'] = Variable<bool>(isDeleted.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (editedAt.present) {
      map['edited_at'] = Variable<DateTime>(editedAt.value);
    }
    if (mediaPublicId.present) {
      map['media_public_id'] = Variable<String>(mediaPublicId.value);
    }
    if (mediaResourceType.present) {
      map['media_resource_type'] = Variable<String>(mediaResourceType.value);
    }
    if (mediaBytes.present) {
      map['media_bytes'] = Variable<int>(mediaBytes.value);
    }
    if (mediaWidth.present) {
      map['media_width'] = Variable<int>(mediaWidth.value);
    }
    if (mediaHeight.present) {
      map['media_height'] = Variable<int>(mediaHeight.value);
    }
    if (mediaFormat.present) {
      map['media_format'] = Variable<String>(mediaFormat.value);
    }
    if (mediaFileName.present) {
      map['media_file_name'] = Variable<String>(mediaFileName.value);
    }
    if (mediaUrl.present) {
      map['media_url'] = Variable<String>(mediaUrl.value);
    }
    if (mediaThumbnailUrl.present) {
      map['media_thumbnail_url'] = Variable<String>(mediaThumbnailUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('senderId: $senderId, ')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('linkPreview: $linkPreview, ')
          ..write('type: $type, ')
          ..write('content: $content, ')
          ..write('reactions: $reactions, ')
          ..write('isDeleted: $isDeleted, ')
          ..write('createdAt: $createdAt, ')
          ..write('editedAt: $editedAt, ')
          ..write('mediaPublicId: $mediaPublicId, ')
          ..write('mediaResourceType: $mediaResourceType, ')
          ..write('mediaBytes: $mediaBytes, ')
          ..write('mediaWidth: $mediaWidth, ')
          ..write('mediaHeight: $mediaHeight, ')
          ..write('mediaFormat: $mediaFormat, ')
          ..write('mediaFileName: $mediaFileName, ')
          ..write('mediaUrl: $mediaUrl, ')
          ..write('mediaThumbnailUrl: $mediaThumbnailUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _cursorMeta = const VerificationMeta('cursor');
  @override
  late final GeneratedColumn<int> cursor = GeneratedColumn<int>(
    'cursor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, cursor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncStateData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('cursor')) {
      context.handle(_cursorMeta, cursor.isAcceptableOrUnknown(data['cursor']!, _cursorMeta));
    } else if (isInserting) {
      context.missing(_cursorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping.read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      cursor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cursor'],
      )!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final int id;
  final int cursor;
  const SyncStateData({required this.id, required this.cursor});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['cursor'] = Variable<int>(cursor);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(id: Value(id), cursor: Value(cursor));
  }

  factory SyncStateData.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<int>(json['id']),
      cursor: serializer.fromJson<int>(json['cursor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cursor': serializer.toJson<int>(cursor),
    };
  }

  SyncStateData copyWith({int? id, int? cursor}) =>
      SyncStateData(id: id ?? this.id, cursor: cursor ?? this.cursor);
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      cursor: data.cursor.present ? data.cursor.value : this.cursor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cursor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData && other.id == this.id && other.cursor == this.cursor);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<int> id;
  final Value<int> cursor;
  const SyncStateCompanion({this.id = const Value.absent(), this.cursor = const Value.absent()});
  SyncStateCompanion.insert({this.id = const Value.absent(), required int cursor})
    : cursor = Value(cursor);
  static Insertable<SyncStateData> custom({Expression<int>? id, Expression<int>? cursor}) {
    return RawValuesInsertable({if (id != null) 'id': id, if (cursor != null) 'cursor': cursor});
  }

  SyncStateCompanion copyWith({Value<int>? id, Value<int>? cursor}) {
    return SyncStateCompanion(id: id ?? this.id, cursor: cursor ?? this.cursor);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cursor.present) {
      map['cursor'] = Variable<int>(cursor.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('cursor: $cursor')
          ..write(')'))
        .toString();
  }
}

class $PendingReadsTable extends PendingReads with TableInfo<$PendingReadsTable, PendingRead> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingReadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conversationIdMeta = const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta('messageId');
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [conversationId, messageId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_reads';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingRead> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(data['conversation_id']!, _conversationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId};
  @override
  PendingRead map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingRead(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
    );
  }

  @override
  $PendingReadsTable createAlias(String alias) {
    return $PendingReadsTable(attachedDatabase, alias);
  }
}

class PendingRead extends DataClass implements Insertable<PendingRead> {
  final String conversationId;
  final String messageId;
  const PendingRead({required this.conversationId, required this.messageId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['message_id'] = Variable<String>(messageId);
    return map;
  }

  PendingReadsCompanion toCompanion(bool nullToAbsent) {
    return PendingReadsCompanion(
      conversationId: Value(conversationId),
      messageId: Value(messageId),
    );
  }

  factory PendingRead.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingRead(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      messageId: serializer.fromJson<String>(json['messageId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'messageId': serializer.toJson<String>(messageId),
    };
  }

  PendingRead copyWith({String? conversationId, String? messageId}) => PendingRead(
    conversationId: conversationId ?? this.conversationId,
    messageId: messageId ?? this.messageId,
  );
  PendingRead copyWithCompanion(PendingReadsCompanion data) {
    return PendingRead(
      conversationId: data.conversationId.present ? data.conversationId.value : this.conversationId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingRead(')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(conversationId, messageId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingRead &&
          other.conversationId == this.conversationId &&
          other.messageId == this.messageId);
}

class PendingReadsCompanion extends UpdateCompanion<PendingRead> {
  final Value<String> conversationId;
  final Value<String> messageId;
  final Value<int> rowid;
  const PendingReadsCompanion({
    this.conversationId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingReadsCompanion.insert({
    required String conversationId,
    required String messageId,
    this.rowid = const Value.absent(),
  }) : conversationId = Value(conversationId),
       messageId = Value(messageId);
  static Insertable<PendingRead> custom({
    Expression<String>? conversationId,
    Expression<String>? messageId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (messageId != null) 'message_id': messageId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingReadsCompanion copyWith({
    Value<String>? conversationId,
    Value<String>? messageId,
    Value<int>? rowid,
  }) {
    return PendingReadsCompanion(
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingReadsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('messageId: $messageId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _clientMsgIdMeta = const VerificationMeta('clientMsgId');
  @override
  late final GeneratedColumn<String> clientMsgId = GeneratedColumn<String>(
    'client_msg_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta('conversationId');
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _replyToMessageIdMeta = const VerificationMeta('replyToMessageId');
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
    'reply_to_message_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkPreviewMeta = const VerificationMeta('linkPreview');
  @override
  late final GeneratedColumn<String> linkPreview = GeneratedColumn<String>(
    'link_preview',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('text'),
  );
  static const VerificationMeta _mediaMeta = const VerificationMeta('media');
  @override
  late final GeneratedColumn<String> media = GeneratedColumn<String>(
    'media',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta('retryCount');
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    clientMsgId,
    conversationId,
    content,
    replyToMessageId,
    linkPreview,
    type,
    media,
    status,
    retryCount,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('client_msg_id')) {
      context.handle(
        _clientMsgIdMeta,
        clientMsgId.isAcceptableOrUnknown(data['client_msg_id']!, _clientMsgIdMeta),
      );
    } else if (isInserting) {
      context.missing(_clientMsgIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(data['conversation_id']!, _conversationIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta, content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
        _replyToMessageIdMeta,
        replyToMessageId.isAcceptableOrUnknown(data['reply_to_message_id']!, _replyToMessageIdMeta),
      );
    }
    if (data.containsKey('link_preview')) {
      context.handle(
        _linkPreviewMeta,
        linkPreview.isAcceptableOrUnknown(data['link_preview']!, _linkPreviewMeta),
      );
    }
    if (data.containsKey('type')) {
      context.handle(_typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    }
    if (data.containsKey('media')) {
      context.handle(_mediaMeta, media.isAcceptableOrUnknown(data['media']!, _mediaMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta, status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {clientMsgId};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      clientMsgId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_msg_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      replyToMessageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reply_to_message_id'],
      ),
      linkPreview: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_preview'],
      ),
      type: attachedDatabase.typeMapping.read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      media: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final String clientMsgId;
  final String conversationId;
  final String content;
  final String? replyToMessageId;

  /// JSON `{url, title, description}` or null.
  final String? linkPreview;

  /// `'text'`, `'image'` or `'file'`.
  final String type;

  /// JSON `{publicId, version, signature, resourceType, bytes, format,
  /// width?, height?, fileName?}` — the already-uploaded Cloudinary asset
  /// reference to send with `message:send`. Null for a text message.
  final String? media;

  /// `'pending'` (queued or awaiting ack), `'sending'` (ack in flight) or
  /// `'failed'` ("tap to retry or delete", ADR 0009). `RATE_LIMITED` retries
  /// in place rather than moving to `'failed'`.
  final String status;
  final int retryCount;
  final DateTime createdAt;
  const OutboxData({
    required this.clientMsgId,
    required this.conversationId,
    required this.content,
    this.replyToMessageId,
    this.linkPreview,
    required this.type,
    this.media,
    required this.status,
    required this.retryCount,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['client_msg_id'] = Variable<String>(clientMsgId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['content'] = Variable<String>(content);
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    if (!nullToAbsent || linkPreview != null) {
      map['link_preview'] = Variable<String>(linkPreview);
    }
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || media != null) {
      map['media'] = Variable<String>(media);
    }
    map['status'] = Variable<String>(status);
    map['retry_count'] = Variable<int>(retryCount);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      clientMsgId: Value(clientMsgId),
      conversationId: Value(conversationId),
      content: Value(content),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      linkPreview: linkPreview == null && nullToAbsent ? const Value.absent() : Value(linkPreview),
      type: Value(type),
      media: media == null && nullToAbsent ? const Value.absent() : Value(media),
      status: Value(status),
      retryCount: Value(retryCount),
      createdAt: Value(createdAt),
    );
  }

  factory OutboxData.fromJson(Map<String, dynamic> json, {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      clientMsgId: serializer.fromJson<String>(json['clientMsgId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      content: serializer.fromJson<String>(json['content']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      linkPreview: serializer.fromJson<String?>(json['linkPreview']),
      type: serializer.fromJson<String>(json['type']),
      media: serializer.fromJson<String?>(json['media']),
      status: serializer.fromJson<String>(json['status']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'clientMsgId': serializer.toJson<String>(clientMsgId),
      'conversationId': serializer.toJson<String>(conversationId),
      'content': serializer.toJson<String>(content),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'linkPreview': serializer.toJson<String?>(linkPreview),
      'type': serializer.toJson<String>(type),
      'media': serializer.toJson<String?>(media),
      'status': serializer.toJson<String>(status),
      'retryCount': serializer.toJson<int>(retryCount),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  OutboxData copyWith({
    String? clientMsgId,
    String? conversationId,
    String? content,
    Value<String?> replyToMessageId = const Value.absent(),
    Value<String?> linkPreview = const Value.absent(),
    String? type,
    Value<String?> media = const Value.absent(),
    String? status,
    int? retryCount,
    DateTime? createdAt,
  }) => OutboxData(
    clientMsgId: clientMsgId ?? this.clientMsgId,
    conversationId: conversationId ?? this.conversationId,
    content: content ?? this.content,
    replyToMessageId: replyToMessageId.present ? replyToMessageId.value : this.replyToMessageId,
    linkPreview: linkPreview.present ? linkPreview.value : this.linkPreview,
    type: type ?? this.type,
    media: media.present ? media.value : this.media,
    status: status ?? this.status,
    retryCount: retryCount ?? this.retryCount,
    createdAt: createdAt ?? this.createdAt,
  );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      clientMsgId: data.clientMsgId.present ? data.clientMsgId.value : this.clientMsgId,
      conversationId: data.conversationId.present ? data.conversationId.value : this.conversationId,
      content: data.content.present ? data.content.value : this.content,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      linkPreview: data.linkPreview.present ? data.linkPreview.value : this.linkPreview,
      type: data.type.present ? data.type.value : this.type,
      media: data.media.present ? data.media.value : this.media,
      status: data.status.present ? data.status.value : this.status,
      retryCount: data.retryCount.present ? data.retryCount.value : this.retryCount,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('conversationId: $conversationId, ')
          ..write('content: $content, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('linkPreview: $linkPreview, ')
          ..write('type: $type, ')
          ..write('media: $media, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    clientMsgId,
    conversationId,
    content,
    replyToMessageId,
    linkPreview,
    type,
    media,
    status,
    retryCount,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.clientMsgId == this.clientMsgId &&
          other.conversationId == this.conversationId &&
          other.content == this.content &&
          other.replyToMessageId == this.replyToMessageId &&
          other.linkPreview == this.linkPreview &&
          other.type == this.type &&
          other.media == this.media &&
          other.status == this.status &&
          other.retryCount == this.retryCount &&
          other.createdAt == this.createdAt);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<String> clientMsgId;
  final Value<String> conversationId;
  final Value<String> content;
  final Value<String?> replyToMessageId;
  final Value<String?> linkPreview;
  final Value<String> type;
  final Value<String?> media;
  final Value<String> status;
  final Value<int> retryCount;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const OutboxCompanion({
    this.clientMsgId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.content = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.linkPreview = const Value.absent(),
    this.type = const Value.absent(),
    this.media = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboxCompanion.insert({
    required String clientMsgId,
    required String conversationId,
    required String content,
    this.replyToMessageId = const Value.absent(),
    this.linkPreview = const Value.absent(),
    this.type = const Value.absent(),
    this.media = const Value.absent(),
    this.status = const Value.absent(),
    this.retryCount = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : clientMsgId = Value(clientMsgId),
       conversationId = Value(conversationId),
       content = Value(content),
       createdAt = Value(createdAt);
  static Insertable<OutboxData> custom({
    Expression<String>? clientMsgId,
    Expression<String>? conversationId,
    Expression<String>? content,
    Expression<String>? replyToMessageId,
    Expression<String>? linkPreview,
    Expression<String>? type,
    Expression<String>? media,
    Expression<String>? status,
    Expression<int>? retryCount,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (clientMsgId != null) 'client_msg_id': clientMsgId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (content != null) 'content': content,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (linkPreview != null) 'link_preview': linkPreview,
      if (type != null) 'type': type,
      if (media != null) 'media': media,
      if (status != null) 'status': status,
      if (retryCount != null) 'retry_count': retryCount,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboxCompanion copyWith({
    Value<String>? clientMsgId,
    Value<String>? conversationId,
    Value<String>? content,
    Value<String?>? replyToMessageId,
    Value<String?>? linkPreview,
    Value<String>? type,
    Value<String?>? media,
    Value<String>? status,
    Value<int>? retryCount,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return OutboxCompanion(
      clientMsgId: clientMsgId ?? this.clientMsgId,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      linkPreview: linkPreview ?? this.linkPreview,
      type: type ?? this.type,
      media: media ?? this.media,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (clientMsgId.present) {
      map['client_msg_id'] = Variable<String>(clientMsgId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (linkPreview.present) {
      map['link_preview'] = Variable<String>(linkPreview.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (media.present) {
      map['media'] = Variable<String>(media.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('clientMsgId: $clientMsgId, ')
          ..write('conversationId: $conversationId, ')
          ..write('content: $content, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('linkPreview: $linkPreview, ')
          ..write('type: $type, ')
          ..write('media: $media, ')
          ..write('status: $status, ')
          ..write('retryCount: $retryCount, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $UsersTable users = $UsersTable(this);
  late final $ConversationsTable conversations = $ConversationsTable(this);
  late final $ParticipantsTable participants = $ParticipantsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  late final $PendingReadsTable pendingReads = $PendingReadsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    users,
    conversations,
    participants,
    messages,
    syncState,
    pendingReads,
    outbox,
  ];
}

typedef $$UsersTableCreateCompanionBuilder = UsersCompanion Function({
  required String id,
  required String phoneNumber,
  Value<String?> displayName,
  Value<String?> avatarUrl,
  Value<int> rowid,
});
typedef $$UsersTableUpdateCompanionBuilder = UsersCompanion Function({
  Value<String> id,
  Value<String> phoneNumber,
  Value<String?> displayName,
  Value<String?> avatarUrl,
  Value<int> rowid,
});

class $$UsersTableFilterComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get phoneNumber =>
      $composableBuilder(column: $table.phoneNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName =>
      $composableBuilder(column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => ColumnFilters(column));
}

class $$UsersTableOrderingComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get phoneNumber =>
      $composableBuilder(column: $table.phoneNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName =>
      $composableBuilder(column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => ColumnOrderings(column));
}

class $$UsersTableAnnotationComposer extends Composer<_$AppDatabase, $UsersTable> {
  $$UsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get phoneNumber =>
      $composableBuilder(column: $table.phoneNumber, builder: (column) => column);

  GeneratedColumn<String> get displayName =>
      $composableBuilder(column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);
}

class $$UsersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UsersTable,
          LocalUser,
          $$UsersTableFilterComposer,
          $$UsersTableOrderingComposer,
          $$UsersTableAnnotationComposer,
          $$UsersTableCreateCompanionBuilder,
          $$UsersTableUpdateCompanionBuilder,
          (LocalUser, BaseReferences<_$AppDatabase, $UsersTable, LocalUser>),
          LocalUser,
          PrefetchHooks Function()
        > {
  $$UsersTableTableManager(_$AppDatabase db, $UsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$UsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$UsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () => $$UsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> phoneNumber = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion(
                id: id,
                phoneNumber: phoneNumber,
                displayName: displayName,
                avatarUrl: avatarUrl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String phoneNumber,
                Value<String?> displayName = const Value.absent(),
                Value<String?> avatarUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => UsersCompanion.insert(
                id: id,
                phoneNumber: phoneNumber,
                displayName: displayName,
                avatarUrl: avatarUrl,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UsersTable, LocalUser>(table),
                  BaseReferences<_$AppDatabase, $UsersTable, LocalUser>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UsersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UsersTable,
      LocalUser,
      $$UsersTableFilterComposer,
      $$UsersTableOrderingComposer,
      $$UsersTableAnnotationComposer,
      $$UsersTableCreateCompanionBuilder,
      $$UsersTableUpdateCompanionBuilder,
      (LocalUser, BaseReferences<_$AppDatabase, $UsersTable, LocalUser>),
      LocalUser,
      PrefetchHooks Function()
    >;
typedef $$ConversationsTableCreateCompanionBuilder = ConversationsCompanion Function({
  required String id,
  required String type,
  Value<String?> name,
  Value<String?> createdById,
  Value<DateTime?> createdAt,
  Value<int> unreadCount,
  Value<bool> left,
  Value<DateTime?> pinnedAt,
  Value<DateTime?> archivedAt,
  Value<DateTime?> mutedUntil,
  Value<DateTime?> hiddenAt,
  Value<String?> historyClearedMessageId,
  Value<int> rowid,
});
typedef $$ConversationsTableUpdateCompanionBuilder = ConversationsCompanion Function({
  Value<String> id,
  Value<String> type,
  Value<String?> name,
  Value<String?> createdById,
  Value<DateTime?> createdAt,
  Value<int> unreadCount,
  Value<bool> left,
  Value<DateTime?> pinnedAt,
  Value<DateTime?> archivedAt,
  Value<DateTime?> mutedUntil,
  Value<DateTime?> hiddenAt,
  Value<String?> historyClearedMessageId,
  Value<int> rowid,
});

class $$ConversationsTableFilterComposer extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdById =>
      $composableBuilder(column: $table.createdById, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount =>
      $composableBuilder(column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get left =>
      $composableBuilder(column: $table.left, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get archivedAt =>
      $composableBuilder(column: $table.archivedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get mutedUntil =>
      $composableBuilder(column: $table.mutedUntil, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get historyClearedMessageId => $composableBuilder(
    column: $table.historyClearedMessageId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConversationsTableOrderingComposer extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdById =>
      $composableBuilder(column: $table.createdById, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount =>
      $composableBuilder(column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get left =>
      $composableBuilder(column: $table.left, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get archivedAt =>
      $composableBuilder(column: $table.archivedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get mutedUntil =>
      $composableBuilder(column: $table.mutedUntil, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get historyClearedMessageId => $composableBuilder(
    column: $table.historyClearedMessageId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConversationsTableAnnotationComposer extends Composer<_$AppDatabase, $ConversationsTable> {
  $$ConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get createdById =>
      $composableBuilder(column: $table.createdById, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get unreadCount =>
      $composableBuilder(column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get left =>
      $composableBuilder(column: $table.left, builder: (column) => column);

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get archivedAt =>
      $composableBuilder(column: $table.archivedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get mutedUntil =>
      $composableBuilder(column: $table.mutedUntil, builder: (column) => column);

  GeneratedColumn<DateTime> get hiddenAt =>
      $composableBuilder(column: $table.hiddenAt, builder: (column) => column);

  GeneratedColumn<String> get historyClearedMessageId =>
      $composableBuilder(column: $table.historyClearedMessageId, builder: (column) => column);
}

class $$ConversationsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConversationsTable,
          Conversation,
          $$ConversationsTableFilterComposer,
          $$ConversationsTableOrderingComposer,
          $$ConversationsTableAnnotationComposer,
          $$ConversationsTableCreateCompanionBuilder,
          $$ConversationsTableUpdateCompanionBuilder,
          (Conversation, BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>),
          Conversation,
          PrefetchHooks Function()
        > {
  $$ConversationsTableTableManager(_$AppDatabase db, $ConversationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ConversationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConversationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConversationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> name = const Value.absent(),
                Value<String?> createdById = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> left = const Value.absent(),
                Value<DateTime?> pinnedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<DateTime?> mutedUntil = const Value.absent(),
                Value<DateTime?> hiddenAt = const Value.absent(),
                Value<String?> historyClearedMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion(
                id: id,
                type: type,
                name: name,
                createdById: createdById,
                createdAt: createdAt,
                unreadCount: unreadCount,
                left: left,
                pinnedAt: pinnedAt,
                archivedAt: archivedAt,
                mutedUntil: mutedUntil,
                hiddenAt: hiddenAt,
                historyClearedMessageId: historyClearedMessageId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                Value<String?> name = const Value.absent(),
                Value<String?> createdById = const Value.absent(),
                Value<DateTime?> createdAt = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<bool> left = const Value.absent(),
                Value<DateTime?> pinnedAt = const Value.absent(),
                Value<DateTime?> archivedAt = const Value.absent(),
                Value<DateTime?> mutedUntil = const Value.absent(),
                Value<DateTime?> hiddenAt = const Value.absent(),
                Value<String?> historyClearedMessageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConversationsCompanion.insert(
                id: id,
                type: type,
                name: name,
                createdById: createdById,
                createdAt: createdAt,
                unreadCount: unreadCount,
                left: left,
                pinnedAt: pinnedAt,
                archivedAt: archivedAt,
                mutedUntil: mutedUntil,
                hiddenAt: hiddenAt,
                historyClearedMessageId: historyClearedMessageId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConversationsTable, Conversation>(table),
                  BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConversationsTable,
      Conversation,
      $$ConversationsTableFilterComposer,
      $$ConversationsTableOrderingComposer,
      $$ConversationsTableAnnotationComposer,
      $$ConversationsTableCreateCompanionBuilder,
      $$ConversationsTableUpdateCompanionBuilder,
      (Conversation, BaseReferences<_$AppDatabase, $ConversationsTable, Conversation>),
      Conversation,
      PrefetchHooks Function()
    >;
typedef $$ParticipantsTableCreateCompanionBuilder = ParticipantsCompanion Function({
  required String conversationId,
  required String userId,
  Value<String> role,
  Value<String?> lastReadMessageId,
  Value<String?> lastDeliveredMessageId,
  Value<DateTime?> leftAt,
  Value<int> rowid,
});
typedef $$ParticipantsTableUpdateCompanionBuilder = ParticipantsCompanion Function({
  Value<String> conversationId,
  Value<String> userId,
  Value<String> role,
  Value<String?> lastReadMessageId,
  Value<String?> lastDeliveredMessageId,
  Value<DateTime?> leftAt,
  Value<int> rowid,
});

class $$ParticipantsTableFilterComposer extends Composer<_$AppDatabase, $ParticipantsTable> {
  $$ParticipantsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastDeliveredMessageId => $composableBuilder(
    column: $table.lastDeliveredMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leftAt =>
      $composableBuilder(column: $table.leftAt, builder: (column) => ColumnFilters(column));
}

class $$ParticipantsTableOrderingComposer extends Composer<_$AppDatabase, $ParticipantsTable> {
  $$ParticipantsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastReadMessageId => $composableBuilder(
    column: $table.lastReadMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastDeliveredMessageId => $composableBuilder(
    column: $table.lastDeliveredMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leftAt =>
      $composableBuilder(column: $table.leftAt, builder: (column) => ColumnOrderings(column));
}

class $$ParticipantsTableAnnotationComposer extends Composer<_$AppDatabase, $ParticipantsTable> {
  $$ParticipantsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get lastReadMessageId =>
      $composableBuilder(column: $table.lastReadMessageId, builder: (column) => column);

  GeneratedColumn<String> get lastDeliveredMessageId =>
      $composableBuilder(column: $table.lastDeliveredMessageId, builder: (column) => column);

  GeneratedColumn<DateTime> get leftAt =>
      $composableBuilder(column: $table.leftAt, builder: (column) => column);
}

class $$ParticipantsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ParticipantsTable,
          Participant,
          $$ParticipantsTableFilterComposer,
          $$ParticipantsTableOrderingComposer,
          $$ParticipantsTableAnnotationComposer,
          $$ParticipantsTableCreateCompanionBuilder,
          $$ParticipantsTableUpdateCompanionBuilder,
          (Participant, BaseReferences<_$AppDatabase, $ParticipantsTable, Participant>),
          Participant,
          PrefetchHooks Function()
        > {
  $$ParticipantsTableTableManager(_$AppDatabase db, $ParticipantsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$ParticipantsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$ParticipantsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ParticipantsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String?> lastReadMessageId = const Value.absent(),
                Value<String?> lastDeliveredMessageId = const Value.absent(),
                Value<DateTime?> leftAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ParticipantsCompanion(
                conversationId: conversationId,
                userId: userId,
                role: role,
                lastReadMessageId: lastReadMessageId,
                lastDeliveredMessageId: lastDeliveredMessageId,
                leftAt: leftAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String userId,
                Value<String> role = const Value.absent(),
                Value<String?> lastReadMessageId = const Value.absent(),
                Value<String?> lastDeliveredMessageId = const Value.absent(),
                Value<DateTime?> leftAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ParticipantsCompanion.insert(
                conversationId: conversationId,
                userId: userId,
                role: role,
                lastReadMessageId: lastReadMessageId,
                lastDeliveredMessageId: lastDeliveredMessageId,
                leftAt: leftAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ParticipantsTable, Participant>(table),
                  BaseReferences<_$AppDatabase, $ParticipantsTable, Participant>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ParticipantsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ParticipantsTable,
      Participant,
      $$ParticipantsTableFilterComposer,
      $$ParticipantsTableOrderingComposer,
      $$ParticipantsTableAnnotationComposer,
      $$ParticipantsTableCreateCompanionBuilder,
      $$ParticipantsTableUpdateCompanionBuilder,
      (Participant, BaseReferences<_$AppDatabase, $ParticipantsTable, Participant>),
      Participant,
      PrefetchHooks Function()
    >;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String id,
  required String conversationId,
  required String senderId,
  Value<String?> clientMsgId,
  Value<String?> replyToMessageId,
  Value<String?> linkPreview,
  Value<String> type,
  Value<String?> content,
  Value<String> reactions,
  Value<bool> isDeleted,
  required DateTime createdAt,
  Value<DateTime?> editedAt,
  Value<String?> mediaPublicId,
  Value<String?> mediaResourceType,
  Value<int?> mediaBytes,
  Value<int?> mediaWidth,
  Value<int?> mediaHeight,
  Value<String?> mediaFormat,
  Value<String?> mediaFileName,
  Value<String?> mediaUrl,
  Value<String?> mediaThumbnailUrl,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> id,
  Value<String> conversationId,
  Value<String> senderId,
  Value<String?> clientMsgId,
  Value<String?> replyToMessageId,
  Value<String?> linkPreview,
  Value<String> type,
  Value<String?> content,
  Value<String> reactions,
  Value<bool> isDeleted,
  Value<DateTime> createdAt,
  Value<DateTime?> editedAt,
  Value<String?> mediaPublicId,
  Value<String?> mediaResourceType,
  Value<int?> mediaBytes,
  Value<int?> mediaWidth,
  Value<int?> mediaHeight,
  Value<String?> mediaFormat,
  Value<String?> mediaFileName,
  Value<String?> mediaUrl,
  Value<String?> mediaThumbnailUrl,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reactions =>
      $composableBuilder(column: $table.reactions, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaPublicId =>
      $composableBuilder(column: $table.mediaPublicId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaResourceType => $composableBuilder(
    column: $table.mediaResourceType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get mediaBytes =>
      $composableBuilder(column: $table.mediaBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mediaWidth =>
      $composableBuilder(column: $table.mediaWidth, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get mediaHeight =>
      $composableBuilder(column: $table.mediaHeight, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaFormat =>
      $composableBuilder(column: $table.mediaFormat, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaFileName =>
      $composableBuilder(column: $table.mediaFileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaThumbnailUrl => $composableBuilder(
    column: $table.mediaThumbnailUrl,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reactions =>
      $composableBuilder(column: $table.reactions, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaPublicId => $composableBuilder(
    column: $table.mediaPublicId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaResourceType => $composableBuilder(
    column: $table.mediaResourceType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get mediaBytes =>
      $composableBuilder(column: $table.mediaBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mediaWidth =>
      $composableBuilder(column: $table.mediaWidth, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get mediaHeight =>
      $composableBuilder(column: $table.mediaHeight, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaFormat =>
      $composableBuilder(column: $table.mediaFormat, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaFileName => $composableBuilder(
    column: $table.mediaFileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaThumbnailUrl => $composableBuilder(
    column: $table.mediaThumbnailUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId =>
      $composableBuilder(column: $table.replyToMessageId, builder: (column) => column);

  GeneratedColumn<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get reactions =>
      $composableBuilder(column: $table.reactions, builder: (column) => column);

  GeneratedColumn<bool> get isDeleted =>
      $composableBuilder(column: $table.isDeleted, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get editedAt =>
      $composableBuilder(column: $table.editedAt, builder: (column) => column);

  GeneratedColumn<String> get mediaPublicId =>
      $composableBuilder(column: $table.mediaPublicId, builder: (column) => column);

  GeneratedColumn<String> get mediaResourceType =>
      $composableBuilder(column: $table.mediaResourceType, builder: (column) => column);

  GeneratedColumn<int> get mediaBytes =>
      $composableBuilder(column: $table.mediaBytes, builder: (column) => column);

  GeneratedColumn<int> get mediaWidth =>
      $composableBuilder(column: $table.mediaWidth, builder: (column) => column);

  GeneratedColumn<int> get mediaHeight =>
      $composableBuilder(column: $table.mediaHeight, builder: (column) => column);

  GeneratedColumn<String> get mediaFormat =>
      $composableBuilder(column: $table.mediaFormat, builder: (column) => column);

  GeneratedColumn<String> get mediaFileName =>
      $composableBuilder(column: $table.mediaFileName, builder: (column) => column);

  GeneratedColumn<String> get mediaUrl =>
      $composableBuilder(column: $table.mediaUrl, builder: (column) => column);

  GeneratedColumn<String> get mediaThumbnailUrl =>
      $composableBuilder(column: $table.mediaThumbnailUrl, builder: (column) => column);
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> senderId = const Value.absent(),
                Value<String?> clientMsgId = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String?> linkPreview = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String> reactions = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> editedAt = const Value.absent(),
                Value<String?> mediaPublicId = const Value.absent(),
                Value<String?> mediaResourceType = const Value.absent(),
                Value<int?> mediaBytes = const Value.absent(),
                Value<int?> mediaWidth = const Value.absent(),
                Value<int?> mediaHeight = const Value.absent(),
                Value<String?> mediaFormat = const Value.absent(),
                Value<String?> mediaFileName = const Value.absent(),
                Value<String?> mediaUrl = const Value.absent(),
                Value<String?> mediaThumbnailUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                clientMsgId: clientMsgId,
                replyToMessageId: replyToMessageId,
                linkPreview: linkPreview,
                type: type,
                content: content,
                reactions: reactions,
                isDeleted: isDeleted,
                createdAt: createdAt,
                editedAt: editedAt,
                mediaPublicId: mediaPublicId,
                mediaResourceType: mediaResourceType,
                mediaBytes: mediaBytes,
                mediaWidth: mediaWidth,
                mediaHeight: mediaHeight,
                mediaFormat: mediaFormat,
                mediaFileName: mediaFileName,
                mediaUrl: mediaUrl,
                mediaThumbnailUrl: mediaThumbnailUrl,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required String senderId,
                Value<String?> clientMsgId = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String?> linkPreview = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> content = const Value.absent(),
                Value<String> reactions = const Value.absent(),
                Value<bool> isDeleted = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> editedAt = const Value.absent(),
                Value<String?> mediaPublicId = const Value.absent(),
                Value<String?> mediaResourceType = const Value.absent(),
                Value<int?> mediaBytes = const Value.absent(),
                Value<int?> mediaWidth = const Value.absent(),
                Value<int?> mediaHeight = const Value.absent(),
                Value<String?> mediaFormat = const Value.absent(),
                Value<String?> mediaFileName = const Value.absent(),
                Value<String?> mediaUrl = const Value.absent(),
                Value<String?> mediaThumbnailUrl = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                conversationId: conversationId,
                senderId: senderId,
                clientMsgId: clientMsgId,
                replyToMessageId: replyToMessageId,
                linkPreview: linkPreview,
                type: type,
                content: content,
                reactions: reactions,
                isDeleted: isDeleted,
                createdAt: createdAt,
                editedAt: editedAt,
                mediaPublicId: mediaPublicId,
                mediaResourceType: mediaResourceType,
                mediaBytes: mediaBytes,
                mediaWidth: mediaWidth,
                mediaHeight: mediaHeight,
                mediaFormat: mediaFormat,
                mediaFileName: mediaFileName,
                mediaUrl: mediaUrl,
                mediaThumbnailUrl: mediaThumbnailUrl,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MessagesTable, Message>(table),
                  BaseReferences<_$AppDatabase, $MessagesTable, Message>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$AppDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  required int cursor,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> cursor,
});

class $$SyncStateTableFilterComposer extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => ColumnFilters(column));
}

class $$SyncStateTableOrderingComposer extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => ColumnOrderings(column));
}

class $$SyncStateTableAnnotationComposer extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id => $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get cursor =>
      $composableBuilder(column: $table.cursor, builder: (column) => column);
}

class $$SyncStateTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncStateTable,
          SyncStateData,
          $$SyncStateTableFilterComposer,
          $$SyncStateTableOrderingComposer,
          $$SyncStateTableAnnotationComposer,
          $$SyncStateTableCreateCompanionBuilder,
          $$SyncStateTableUpdateCompanionBuilder,
          (SyncStateData, BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>),
          SyncStateData,
          PrefetchHooks Function()
        > {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> cursor = const Value.absent(),
          }) => SyncStateCompanion(id: id, cursor: cursor),
          createCompanionCallback: ({Value<int> id = const Value.absent(), required int cursor}) =>
              SyncStateCompanion.insert(id: id, cursor: cursor),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncStateTable, SyncStateData>(table),
                  BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncStateTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncStateTable,
      SyncStateData,
      $$SyncStateTableFilterComposer,
      $$SyncStateTableOrderingComposer,
      $$SyncStateTableAnnotationComposer,
      $$SyncStateTableCreateCompanionBuilder,
      $$SyncStateTableUpdateCompanionBuilder,
      (SyncStateData, BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>),
      SyncStateData,
      PrefetchHooks Function()
    >;
typedef $$PendingReadsTableCreateCompanionBuilder = PendingReadsCompanion Function({
  required String conversationId,
  required String messageId,
  Value<int> rowid,
});
typedef $$PendingReadsTableUpdateCompanionBuilder = PendingReadsCompanion Function({
  Value<String> conversationId,
  Value<String> messageId,
  Value<int> rowid,
});

class $$PendingReadsTableFilterComposer extends Composer<_$AppDatabase, $PendingReadsTable> {
  $$PendingReadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => ColumnFilters(column));
}

class $$PendingReadsTableOrderingComposer extends Composer<_$AppDatabase, $PendingReadsTable> {
  $$PendingReadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => ColumnOrderings(column));
}

class $$PendingReadsTableAnnotationComposer extends Composer<_$AppDatabase, $PendingReadsTable> {
  $$PendingReadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);
}

class $$PendingReadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingReadsTable,
          PendingRead,
          $$PendingReadsTableFilterComposer,
          $$PendingReadsTableOrderingComposer,
          $$PendingReadsTableAnnotationComposer,
          $$PendingReadsTableCreateCompanionBuilder,
          $$PendingReadsTableUpdateCompanionBuilder,
          (PendingRead, BaseReferences<_$AppDatabase, $PendingReadsTable, PendingRead>),
          PendingRead,
          PrefetchHooks Function()
        > {
  $$PendingReadsTableTableManager(_$AppDatabase db, $PendingReadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$PendingReadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$PendingReadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingReadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingReadsCompanion(
                conversationId: conversationId,
                messageId: messageId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required String messageId,
                Value<int> rowid = const Value.absent(),
              }) => PendingReadsCompanion.insert(
                conversationId: conversationId,
                messageId: messageId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PendingReadsTable, PendingRead>(table),
                  BaseReferences<_$AppDatabase, $PendingReadsTable, PendingRead>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingReadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingReadsTable,
      PendingRead,
      $$PendingReadsTableFilterComposer,
      $$PendingReadsTableOrderingComposer,
      $$PendingReadsTableAnnotationComposer,
      $$PendingReadsTableCreateCompanionBuilder,
      $$PendingReadsTableUpdateCompanionBuilder,
      (PendingRead, BaseReferences<_$AppDatabase, $PendingReadsTable, PendingRead>),
      PendingRead,
      PrefetchHooks Function()
    >;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  required String clientMsgId,
  required String conversationId,
  required String content,
  Value<String?> replyToMessageId,
  Value<String?> linkPreview,
  Value<String> type,
  Value<String?> media,
  Value<String> status,
  Value<int> retryCount,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<String> clientMsgId,
  Value<String> conversationId,
  Value<String> content,
  Value<String?> replyToMessageId,
  Value<String?> linkPreview,
  Value<String> type,
  Value<String?> media,
  Value<String> status,
  Value<int> retryCount,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$OutboxTableFilterComposer extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get media =>
      $composableBuilder(column: $table.media, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get retryCount =>
      $composableBuilder(column: $table.retryCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
    column: $table.replyToMessageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get media =>
      $composableBuilder(column: $table.media, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get retryCount =>
      $composableBuilder(column: $table.retryCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get clientMsgId =>
      $composableBuilder(column: $table.clientMsgId, builder: (column) => column);

  GeneratedColumn<String> get conversationId =>
      $composableBuilder(column: $table.conversationId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId =>
      $composableBuilder(column: $table.replyToMessageId, builder: (column) => column);

  GeneratedColumn<String> get linkPreview =>
      $composableBuilder(column: $table.linkPreview, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get media =>
      $composableBuilder(column: $table.media, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get retryCount =>
      $composableBuilder(column: $table.retryCount, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$OutboxTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboxTable,
          OutboxData,
          $$OutboxTableFilterComposer,
          $$OutboxTableOrderingComposer,
          $$OutboxTableAnnotationComposer,
          $$OutboxTableCreateCompanionBuilder,
          $$OutboxTableUpdateCompanionBuilder,
          (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
          OutboxData,
          PrefetchHooks Function()
        > {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () => $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () => $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> clientMsgId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String?> linkPreview = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> media = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion(
                clientMsgId: clientMsgId,
                conversationId: conversationId,
                content: content,
                replyToMessageId: replyToMessageId,
                linkPreview: linkPreview,
                type: type,
                media: media,
                status: status,
                retryCount: retryCount,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String clientMsgId,
                required String conversationId,
                required String content,
                Value<String?> replyToMessageId = const Value.absent(),
                Value<String?> linkPreview = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> media = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => OutboxCompanion.insert(
                clientMsgId: clientMsgId,
                conversationId: conversationId,
                content: content,
                replyToMessageId: replyToMessageId,
                linkPreview: linkPreview,
                type: type,
                media: media,
                status: status,
                retryCount: retryCount,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$OutboxTable, OutboxData>(table),
                  BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboxTable,
      OutboxData,
      $$OutboxTableFilterComposer,
      $$OutboxTableOrderingComposer,
      $$OutboxTableAnnotationComposer,
      $$OutboxTableCreateCompanionBuilder,
      $$OutboxTableUpdateCompanionBuilder,
      (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
      OutboxData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$UsersTableTableManager get users => $$UsersTableTableManager(_db, _db.users);
  $$ConversationsTableTableManager get conversations =>
      $$ConversationsTableTableManager(_db, _db.conversations);
  $$ParticipantsTableTableManager get participants =>
      $$ParticipantsTableTableManager(_db, _db.participants);
  $$MessagesTableTableManager get messages => $$MessagesTableTableManager(_db, _db.messages);
  $$SyncStateTableTableManager get syncState => $$SyncStateTableTableManager(_db, _db.syncState);
  $$PendingReadsTableTableManager get pendingReads =>
      $$PendingReadsTableTableManager(_db, _db.pendingReads);
  $$OutboxTableTableManager get outbox => $$OutboxTableTableManager(_db, _db.outbox);
}
