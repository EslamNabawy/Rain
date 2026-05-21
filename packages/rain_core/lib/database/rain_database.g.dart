// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'rain_database.dart';

// ignore_for_file: type=lint
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
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<int> sentAt = GeneratedColumn<int>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOutgoingMeta = const VerificationMeta(
    'isOutgoing',
  );
  @override
  late final GeneratedColumn<bool> isOutgoing = GeneratedColumn<bool>(
    'is_outgoing',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_outgoing" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerId,
    content,
    sentAt,
    seq,
    type,
    status,
    isOutgoing,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<Message> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('is_outgoing')) {
      context.handle(
        _isOutgoingMeta,
        isOutgoing.isAcceptableOrUnknown(data['is_outgoing']!, _isOutgoingMeta),
      );
    } else if (isInserting) {
      context.missing(_isOutgoingMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sent_at'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      isOutgoing: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_outgoing'],
      )!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final String id;
  final String peerId;
  final String content;
  final int sentAt;
  final int seq;
  final String type;
  final String status;
  final bool isOutgoing;
  const Message({
    required this.id,
    required this.peerId,
    required this.content,
    required this.sentAt,
    required this.seq,
    required this.type,
    required this.status,
    required this.isOutgoing,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['peer_id'] = Variable<String>(peerId);
    map['content'] = Variable<String>(content);
    map['sent_at'] = Variable<int>(sentAt);
    map['seq'] = Variable<int>(seq);
    map['type'] = Variable<String>(type);
    map['status'] = Variable<String>(status);
    map['is_outgoing'] = Variable<bool>(isOutgoing);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      peerId: Value(peerId),
      content: Value(content),
      sentAt: Value(sentAt),
      seq: Value(seq),
      type: Value(type),
      status: Value(status),
      isOutgoing: Value(isOutgoing),
    );
  }

  factory Message.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<String>(json['id']),
      peerId: serializer.fromJson<String>(json['peerId']),
      content: serializer.fromJson<String>(json['content']),
      sentAt: serializer.fromJson<int>(json['sentAt']),
      seq: serializer.fromJson<int>(json['seq']),
      type: serializer.fromJson<String>(json['type']),
      status: serializer.fromJson<String>(json['status']),
      isOutgoing: serializer.fromJson<bool>(json['isOutgoing']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'peerId': serializer.toJson<String>(peerId),
      'content': serializer.toJson<String>(content),
      'sentAt': serializer.toJson<int>(sentAt),
      'seq': serializer.toJson<int>(seq),
      'type': serializer.toJson<String>(type),
      'status': serializer.toJson<String>(status),
      'isOutgoing': serializer.toJson<bool>(isOutgoing),
    };
  }

  Message copyWith({
    String? id,
    String? peerId,
    String? content,
    int? sentAt,
    int? seq,
    String? type,
    String? status,
    bool? isOutgoing,
  }) => Message(
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    content: content ?? this.content,
    sentAt: sentAt ?? this.sentAt,
    seq: seq ?? this.seq,
    type: type ?? this.type,
    status: status ?? this.status,
    isOutgoing: isOutgoing ?? this.isOutgoing,
  );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      content: data.content.present ? data.content.value : this.content,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      seq: data.seq.present ? data.seq.value : this.seq,
      type: data.type.present ? data.type.value : this.type,
      status: data.status.present ? data.status.value : this.status,
      isOutgoing: data.isOutgoing.present
          ? data.isOutgoing.value
          : this.isOutgoing,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('content: $content, ')
          ..write('sentAt: $sentAt, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('isOutgoing: $isOutgoing')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, peerId, content, sentAt, seq, type, status, isOutgoing);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.content == this.content &&
          other.sentAt == this.sentAt &&
          other.seq == this.seq &&
          other.type == this.type &&
          other.status == this.status &&
          other.isOutgoing == this.isOutgoing);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<String> id;
  final Value<String> peerId;
  final Value<String> content;
  final Value<int> sentAt;
  final Value<int> seq;
  final Value<String> type;
  final Value<String> status;
  final Value<bool> isOutgoing;
  final Value<int> rowid;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.content = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.seq = const Value.absent(),
    this.type = const Value.absent(),
    this.status = const Value.absent(),
    this.isOutgoing = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String id,
    required String peerId,
    required String content,
    required int sentAt,
    required int seq,
    required String type,
    required String status,
    required bool isOutgoing,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       peerId = Value(peerId),
       content = Value(content),
       sentAt = Value(sentAt),
       seq = Value(seq),
       type = Value(type),
       status = Value(status),
       isOutgoing = Value(isOutgoing);
  static Insertable<Message> custom({
    Expression<String>? id,
    Expression<String>? peerId,
    Expression<String>? content,
    Expression<int>? sentAt,
    Expression<int>? seq,
    Expression<String>? type,
    Expression<String>? status,
    Expression<bool>? isOutgoing,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (content != null) 'content': content,
      if (sentAt != null) 'sent_at': sentAt,
      if (seq != null) 'seq': seq,
      if (type != null) 'type': type,
      if (status != null) 'status': status,
      if (isOutgoing != null) 'is_outgoing': isOutgoing,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? peerId,
    Value<String>? content,
    Value<int>? sentAt,
    Value<int>? seq,
    Value<String>? type,
    Value<String>? status,
    Value<bool>? isOutgoing,
    Value<int>? rowid,
  }) {
    return MessagesCompanion(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      content: content ?? this.content,
      sentAt: sentAt ?? this.sentAt,
      seq: seq ?? this.seq,
      type: type ?? this.type,
      status: status ?? this.status,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<int>(sentAt.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (isOutgoing.present) {
      map['is_outgoing'] = Variable<bool>(isOutgoing.value);
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
          ..write('peerId: $peerId, ')
          ..write('content: $content, ')
          ..write('sentAt: $sentAt, ')
          ..write('seq: $seq, ')
          ..write('type: $type, ')
          ..write('status: $status, ')
          ..write('isOutgoing: $isOutgoing, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FriendsTable extends Friends with TableInfo<$FriendsTable, Friend> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FriendsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastOnlineAtMeta = const VerificationMeta(
    'lastOnlineAt',
  );
  @override
  late final GeneratedColumn<int> lastOnlineAt = GeneratedColumn<int>(
    'last_online_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _onlineMeta = const VerificationMeta('online');
  @override
  late final GeneratedColumn<bool> online = GeneratedColumn<bool>(
    'online',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("online" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _unreadCountMeta = const VerificationMeta(
    'unreadCount',
  );
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
    'unread_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    username,
    displayName,
    gender,
    state,
    addedAt,
    lastOnlineAt,
    online,
    unreadCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'friends';
  @override
  VerificationContext validateIntegrity(
    Insertable<Friend> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('last_online_at')) {
      context.handle(
        _lastOnlineAtMeta,
        lastOnlineAt.isAcceptableOrUnknown(
          data['last_online_at']!,
          _lastOnlineAtMeta,
        ),
      );
    }
    if (data.containsKey('online')) {
      context.handle(
        _onlineMeta,
        online.isAcceptableOrUnknown(data['online']!, _onlineMeta),
      );
    }
    if (data.containsKey('unread_count')) {
      context.handle(
        _unreadCountMeta,
        unreadCount.isAcceptableOrUnknown(
          data['unread_count']!,
          _unreadCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {username};
  @override
  Friend map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Friend(
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      lastOnlineAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_online_at'],
      ),
      online: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}online'],
      )!,
      unreadCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unread_count'],
      )!,
    );
  }

  @override
  $FriendsTable createAlias(String alias) {
    return $FriendsTable(attachedDatabase, alias);
  }
}

class Friend extends DataClass implements Insertable<Friend> {
  final String username;
  final String displayName;
  final String? gender;
  final String state;
  final int addedAt;
  final int? lastOnlineAt;
  final bool online;
  final int unreadCount;
  const Friend({
    required this.username,
    required this.displayName,
    this.gender,
    required this.state,
    required this.addedAt,
    this.lastOnlineAt,
    required this.online,
    required this.unreadCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || gender != null) {
      map['gender'] = Variable<String>(gender);
    }
    map['state'] = Variable<String>(state);
    map['added_at'] = Variable<int>(addedAt);
    if (!nullToAbsent || lastOnlineAt != null) {
      map['last_online_at'] = Variable<int>(lastOnlineAt);
    }
    map['online'] = Variable<bool>(online);
    map['unread_count'] = Variable<int>(unreadCount);
    return map;
  }

  FriendsCompanion toCompanion(bool nullToAbsent) {
    return FriendsCompanion(
      username: Value(username),
      displayName: Value(displayName),
      gender: gender == null && nullToAbsent
          ? const Value.absent()
          : Value(gender),
      state: Value(state),
      addedAt: Value(addedAt),
      lastOnlineAt: lastOnlineAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastOnlineAt),
      online: Value(online),
      unreadCount: Value(unreadCount),
    );
  }

  factory Friend.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Friend(
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      gender: serializer.fromJson<String?>(json['gender']),
      state: serializer.fromJson<String>(json['state']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      lastOnlineAt: serializer.fromJson<int?>(json['lastOnlineAt']),
      online: serializer.fromJson<bool>(json['online']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'gender': serializer.toJson<String?>(gender),
      'state': serializer.toJson<String>(state),
      'addedAt': serializer.toJson<int>(addedAt),
      'lastOnlineAt': serializer.toJson<int?>(lastOnlineAt),
      'online': serializer.toJson<bool>(online),
      'unreadCount': serializer.toJson<int>(unreadCount),
    };
  }

  Friend copyWith({
    String? username,
    String? displayName,
    Value<String?> gender = const Value.absent(),
    String? state,
    int? addedAt,
    Value<int?> lastOnlineAt = const Value.absent(),
    bool? online,
    int? unreadCount,
  }) => Friend(
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    gender: gender.present ? gender.value : this.gender,
    state: state ?? this.state,
    addedAt: addedAt ?? this.addedAt,
    lastOnlineAt: lastOnlineAt.present ? lastOnlineAt.value : this.lastOnlineAt,
    online: online ?? this.online,
    unreadCount: unreadCount ?? this.unreadCount,
  );
  Friend copyWithCompanion(FriendsCompanion data) {
    return Friend(
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      gender: data.gender.present ? data.gender.value : this.gender,
      state: data.state.present ? data.state.value : this.state,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      lastOnlineAt: data.lastOnlineAt.present
          ? data.lastOnlineAt.value
          : this.lastOnlineAt,
      online: data.online.present ? data.online.value : this.online,
      unreadCount: data.unreadCount.present
          ? data.unreadCount.value
          : this.unreadCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Friend(')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('gender: $gender, ')
          ..write('state: $state, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastOnlineAt: $lastOnlineAt, ')
          ..write('online: $online, ')
          ..write('unreadCount: $unreadCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    username,
    displayName,
    gender,
    state,
    addedAt,
    lastOnlineAt,
    online,
    unreadCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Friend &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.gender == this.gender &&
          other.state == this.state &&
          other.addedAt == this.addedAt &&
          other.lastOnlineAt == this.lastOnlineAt &&
          other.online == this.online &&
          other.unreadCount == this.unreadCount);
}

class FriendsCompanion extends UpdateCompanion<Friend> {
  final Value<String> username;
  final Value<String> displayName;
  final Value<String?> gender;
  final Value<String> state;
  final Value<int> addedAt;
  final Value<int?> lastOnlineAt;
  final Value<bool> online;
  final Value<int> unreadCount;
  final Value<int> rowid;
  const FriendsCompanion({
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.gender = const Value.absent(),
    this.state = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.lastOnlineAt = const Value.absent(),
    this.online = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FriendsCompanion.insert({
    required String username,
    required String displayName,
    this.gender = const Value.absent(),
    required String state,
    required int addedAt,
    this.lastOnlineAt = const Value.absent(),
    this.online = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : username = Value(username),
       displayName = Value(displayName),
       state = Value(state),
       addedAt = Value(addedAt);
  static Insertable<Friend> custom({
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? gender,
    Expression<String>? state,
    Expression<int>? addedAt,
    Expression<int>? lastOnlineAt,
    Expression<bool>? online,
    Expression<int>? unreadCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (gender != null) 'gender': gender,
      if (state != null) 'state': state,
      if (addedAt != null) 'added_at': addedAt,
      if (lastOnlineAt != null) 'last_online_at': lastOnlineAt,
      if (online != null) 'online': online,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FriendsCompanion copyWith({
    Value<String>? username,
    Value<String>? displayName,
    Value<String?>? gender,
    Value<String>? state,
    Value<int>? addedAt,
    Value<int?>? lastOnlineAt,
    Value<bool>? online,
    Value<int>? unreadCount,
    Value<int>? rowid,
  }) {
    return FriendsCompanion(
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      gender: gender ?? this.gender,
      state: state ?? this.state,
      addedAt: addedAt ?? this.addedAt,
      lastOnlineAt: lastOnlineAt ?? this.lastOnlineAt,
      online: online ?? this.online,
      unreadCount: unreadCount ?? this.unreadCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (lastOnlineAt.present) {
      map['last_online_at'] = Variable<int>(lastOnlineAt.value);
    }
    if (online.present) {
      map['online'] = Variable<bool>(online.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FriendsCompanion(')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('gender: $gender, ')
          ..write('state: $state, ')
          ..write('addedAt: $addedAt, ')
          ..write('lastOnlineAt: $lastOnlineAt, ')
          ..write('online: $online, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueuedMessagesTable extends QueuedMessages
    with TableInfo<$QueuedMessagesTable, QueuedMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueuedMessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toMeta = const VerificationMeta('to');
  @override
  late final GeneratedColumn<String> to = GeneratedColumn<String>(
    'to',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sentAtMeta = const VerificationMeta('sentAt');
  @override
  late final GeneratedColumn<int> sentAt = GeneratedColumn<int>(
    'sent_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _seqMeta = const VerificationMeta('seq');
  @override
  late final GeneratedColumn<int> seq = GeneratedColumn<int>(
    'seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, to, content, sentAt, seq, status];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queued_messages';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueuedMessage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('to')) {
      context.handle(_toMeta, to.isAcceptableOrUnknown(data['to']!, _toMeta));
    } else if (isInserting) {
      context.missing(_toMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('sent_at')) {
      context.handle(
        _sentAtMeta,
        sentAt.isAcceptableOrUnknown(data['sent_at']!, _sentAtMeta),
      );
    } else if (isInserting) {
      context.missing(_sentAtMeta);
    }
    if (data.containsKey('seq')) {
      context.handle(
        _seqMeta,
        seq.isAcceptableOrUnknown(data['seq']!, _seqMeta),
      );
    } else if (isInserting) {
      context.missing(_seqMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueuedMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueuedMessage(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      to: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      sentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sent_at'],
      )!,
      seq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}seq'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $QueuedMessagesTable createAlias(String alias) {
    return $QueuedMessagesTable(attachedDatabase, alias);
  }
}

class QueuedMessage extends DataClass implements Insertable<QueuedMessage> {
  final String id;
  final String to;
  final String content;
  final int sentAt;
  final int seq;
  final String status;
  const QueuedMessage({
    required this.id,
    required this.to,
    required this.content,
    required this.sentAt,
    required this.seq,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['to'] = Variable<String>(to);
    map['content'] = Variable<String>(content);
    map['sent_at'] = Variable<int>(sentAt);
    map['seq'] = Variable<int>(seq);
    map['status'] = Variable<String>(status);
    return map;
  }

  QueuedMessagesCompanion toCompanion(bool nullToAbsent) {
    return QueuedMessagesCompanion(
      id: Value(id),
      to: Value(to),
      content: Value(content),
      sentAt: Value(sentAt),
      seq: Value(seq),
      status: Value(status),
    );
  }

  factory QueuedMessage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueuedMessage(
      id: serializer.fromJson<String>(json['id']),
      to: serializer.fromJson<String>(json['to']),
      content: serializer.fromJson<String>(json['content']),
      sentAt: serializer.fromJson<int>(json['sentAt']),
      seq: serializer.fromJson<int>(json['seq']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'to': serializer.toJson<String>(to),
      'content': serializer.toJson<String>(content),
      'sentAt': serializer.toJson<int>(sentAt),
      'seq': serializer.toJson<int>(seq),
      'status': serializer.toJson<String>(status),
    };
  }

  QueuedMessage copyWith({
    String? id,
    String? to,
    String? content,
    int? sentAt,
    int? seq,
    String? status,
  }) => QueuedMessage(
    id: id ?? this.id,
    to: to ?? this.to,
    content: content ?? this.content,
    sentAt: sentAt ?? this.sentAt,
    seq: seq ?? this.seq,
    status: status ?? this.status,
  );
  QueuedMessage copyWithCompanion(QueuedMessagesCompanion data) {
    return QueuedMessage(
      id: data.id.present ? data.id.value : this.id,
      to: data.to.present ? data.to.value : this.to,
      content: data.content.present ? data.content.value : this.content,
      sentAt: data.sentAt.present ? data.sentAt.value : this.sentAt,
      seq: data.seq.present ? data.seq.value : this.seq,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueuedMessage(')
          ..write('id: $id, ')
          ..write('to: $to, ')
          ..write('content: $content, ')
          ..write('sentAt: $sentAt, ')
          ..write('seq: $seq, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, to, content, sentAt, seq, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueuedMessage &&
          other.id == this.id &&
          other.to == this.to &&
          other.content == this.content &&
          other.sentAt == this.sentAt &&
          other.seq == this.seq &&
          other.status == this.status);
}

class QueuedMessagesCompanion extends UpdateCompanion<QueuedMessage> {
  final Value<String> id;
  final Value<String> to;
  final Value<String> content;
  final Value<int> sentAt;
  final Value<int> seq;
  final Value<String> status;
  final Value<int> rowid;
  const QueuedMessagesCompanion({
    this.id = const Value.absent(),
    this.to = const Value.absent(),
    this.content = const Value.absent(),
    this.sentAt = const Value.absent(),
    this.seq = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  QueuedMessagesCompanion.insert({
    required String id,
    required String to,
    required String content,
    required int sentAt,
    required int seq,
    required String status,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       to = Value(to),
       content = Value(content),
       sentAt = Value(sentAt),
       seq = Value(seq),
       status = Value(status);
  static Insertable<QueuedMessage> custom({
    Expression<String>? id,
    Expression<String>? to,
    Expression<String>? content,
    Expression<int>? sentAt,
    Expression<int>? seq,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (to != null) 'to': to,
      if (content != null) 'content': content,
      if (sentAt != null) 'sent_at': sentAt,
      if (seq != null) 'seq': seq,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  QueuedMessagesCompanion copyWith({
    Value<String>? id,
    Value<String>? to,
    Value<String>? content,
    Value<int>? sentAt,
    Value<int>? seq,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return QueuedMessagesCompanion(
      id: id ?? this.id,
      to: to ?? this.to,
      content: content ?? this.content,
      sentAt: sentAt ?? this.sentAt,
      seq: seq ?? this.seq,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (to.present) {
      map['to'] = Variable<String>(to.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (sentAt.present) {
      map['sent_at'] = Variable<int>(sentAt.value);
    }
    if (seq.present) {
      map['seq'] = Variable<int>(seq.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueuedMessagesCompanion(')
          ..write('id: $id, ')
          ..write('to: $to, ')
          ..write('content: $content, ')
          ..write('sentAt: $sentAt, ')
          ..write('seq: $seq, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FileTransfersTable extends FileTransfers
    with TableInfo<$FileTransfersTable, FileTransfer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FileTransfersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageIdMeta = const VerificationMeta(
    'messageId',
  );
  @override
  late final GeneratedColumn<String> messageId = GeneratedColumn<String>(
    'message_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileNameMeta = const VerificationMeta(
    'fileName',
  );
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
    'file_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fileSizeMeta = const VerificationMeta(
    'fileSize',
  );
  @override
  late final GeneratedColumn<int> fileSize = GeneratedColumn<int>(
    'file_size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _localPathMeta = const VerificationMeta(
    'localPath',
  );
  @override
  late final GeneratedColumn<String> localPath = GeneratedColumn<String>(
    'local_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tempPathMeta = const VerificationMeta(
    'tempPath',
  );
  @override
  late final GeneratedColumn<String> tempPath = GeneratedColumn<String>(
    'temp_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _bytesTransferredMeta = const VerificationMeta(
    'bytesTransferred',
  );
  @override
  late final GeneratedColumn<int> bytesTransferred = GeneratedColumn<int>(
    'bytes_transferred',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    peerId,
    messageId,
    direction,
    fileName,
    fileSize,
    mimeType,
    localPath,
    tempPath,
    bytesTransferred,
    state,
    error,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'file_transfers';
  @override
  VerificationContext validateIntegrity(
    Insertable<FileTransfer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('message_id')) {
      context.handle(
        _messageIdMeta,
        messageId.isAcceptableOrUnknown(data['message_id']!, _messageIdMeta),
      );
    } else if (isInserting) {
      context.missing(_messageIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('file_name')) {
      context.handle(
        _fileNameMeta,
        fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta),
      );
    } else if (isInserting) {
      context.missing(_fileNameMeta);
    }
    if (data.containsKey('file_size')) {
      context.handle(
        _fileSizeMeta,
        fileSize.isAcceptableOrUnknown(data['file_size']!, _fileSizeMeta),
      );
    } else if (isInserting) {
      context.missing(_fileSizeMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('local_path')) {
      context.handle(
        _localPathMeta,
        localPath.isAcceptableOrUnknown(data['local_path']!, _localPathMeta),
      );
    }
    if (data.containsKey('temp_path')) {
      context.handle(
        _tempPathMeta,
        tempPath.isAcceptableOrUnknown(data['temp_path']!, _tempPathMeta),
      );
    }
    if (data.containsKey('bytes_transferred')) {
      context.handle(
        _bytesTransferredMeta,
        bytesTransferred.isAcceptableOrUnknown(
          data['bytes_transferred']!,
          _bytesTransferredMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
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
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FileTransfer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FileTransfer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      messageId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      fileName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_name'],
      )!,
      fileSize: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      localPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_path'],
      ),
      tempPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}temp_path'],
      ),
      bytesTransferred: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}bytes_transferred'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FileTransfersTable createAlias(String alias) {
    return $FileTransfersTable(attachedDatabase, alias);
  }
}

class FileTransfer extends DataClass implements Insertable<FileTransfer> {
  final String id;
  final String peerId;
  final String messageId;
  final String direction;
  final String fileName;
  final int fileSize;
  final String? mimeType;
  final String? localPath;
  final String? tempPath;
  final int bytesTransferred;
  final String state;
  final String? error;
  final int createdAt;
  final int updatedAt;
  const FileTransfer({
    required this.id,
    required this.peerId,
    required this.messageId,
    required this.direction,
    required this.fileName,
    required this.fileSize,
    this.mimeType,
    this.localPath,
    this.tempPath,
    required this.bytesTransferred,
    required this.state,
    this.error,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['peer_id'] = Variable<String>(peerId);
    map['message_id'] = Variable<String>(messageId);
    map['direction'] = Variable<String>(direction);
    map['file_name'] = Variable<String>(fileName);
    map['file_size'] = Variable<int>(fileSize);
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    if (!nullToAbsent || localPath != null) {
      map['local_path'] = Variable<String>(localPath);
    }
    if (!nullToAbsent || tempPath != null) {
      map['temp_path'] = Variable<String>(tempPath);
    }
    map['bytes_transferred'] = Variable<int>(bytesTransferred);
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  FileTransfersCompanion toCompanion(bool nullToAbsent) {
    return FileTransfersCompanion(
      id: Value(id),
      peerId: Value(peerId),
      messageId: Value(messageId),
      direction: Value(direction),
      fileName: Value(fileName),
      fileSize: Value(fileSize),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      localPath: localPath == null && nullToAbsent
          ? const Value.absent()
          : Value(localPath),
      tempPath: tempPath == null && nullToAbsent
          ? const Value.absent()
          : Value(tempPath),
      bytesTransferred: Value(bytesTransferred),
      state: Value(state),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory FileTransfer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FileTransfer(
      id: serializer.fromJson<String>(json['id']),
      peerId: serializer.fromJson<String>(json['peerId']),
      messageId: serializer.fromJson<String>(json['messageId']),
      direction: serializer.fromJson<String>(json['direction']),
      fileName: serializer.fromJson<String>(json['fileName']),
      fileSize: serializer.fromJson<int>(json['fileSize']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      localPath: serializer.fromJson<String?>(json['localPath']),
      tempPath: serializer.fromJson<String?>(json['tempPath']),
      bytesTransferred: serializer.fromJson<int>(json['bytesTransferred']),
      state: serializer.fromJson<String>(json['state']),
      error: serializer.fromJson<String?>(json['error']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'peerId': serializer.toJson<String>(peerId),
      'messageId': serializer.toJson<String>(messageId),
      'direction': serializer.toJson<String>(direction),
      'fileName': serializer.toJson<String>(fileName),
      'fileSize': serializer.toJson<int>(fileSize),
      'mimeType': serializer.toJson<String?>(mimeType),
      'localPath': serializer.toJson<String?>(localPath),
      'tempPath': serializer.toJson<String?>(tempPath),
      'bytesTransferred': serializer.toJson<int>(bytesTransferred),
      'state': serializer.toJson<String>(state),
      'error': serializer.toJson<String?>(error),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  FileTransfer copyWith({
    String? id,
    String? peerId,
    String? messageId,
    String? direction,
    String? fileName,
    int? fileSize,
    Value<String?> mimeType = const Value.absent(),
    Value<String?> localPath = const Value.absent(),
    Value<String?> tempPath = const Value.absent(),
    int? bytesTransferred,
    String? state,
    Value<String?> error = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => FileTransfer(
    id: id ?? this.id,
    peerId: peerId ?? this.peerId,
    messageId: messageId ?? this.messageId,
    direction: direction ?? this.direction,
    fileName: fileName ?? this.fileName,
    fileSize: fileSize ?? this.fileSize,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    localPath: localPath.present ? localPath.value : this.localPath,
    tempPath: tempPath.present ? tempPath.value : this.tempPath,
    bytesTransferred: bytesTransferred ?? this.bytesTransferred,
    state: state ?? this.state,
    error: error.present ? error.value : this.error,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  FileTransfer copyWithCompanion(FileTransfersCompanion data) {
    return FileTransfer(
      id: data.id.present ? data.id.value : this.id,
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      messageId: data.messageId.present ? data.messageId.value : this.messageId,
      direction: data.direction.present ? data.direction.value : this.direction,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      fileSize: data.fileSize.present ? data.fileSize.value : this.fileSize,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      localPath: data.localPath.present ? data.localPath.value : this.localPath,
      tempPath: data.tempPath.present ? data.tempPath.value : this.tempPath,
      bytesTransferred: data.bytesTransferred.present
          ? data.bytesTransferred.value
          : this.bytesTransferred,
      state: data.state.present ? data.state.value : this.state,
      error: data.error.present ? data.error.value : this.error,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FileTransfer(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('messageId: $messageId, ')
          ..write('direction: $direction, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('tempPath: $tempPath, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('state: $state, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    peerId,
    messageId,
    direction,
    fileName,
    fileSize,
    mimeType,
    localPath,
    tempPath,
    bytesTransferred,
    state,
    error,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FileTransfer &&
          other.id == this.id &&
          other.peerId == this.peerId &&
          other.messageId == this.messageId &&
          other.direction == this.direction &&
          other.fileName == this.fileName &&
          other.fileSize == this.fileSize &&
          other.mimeType == this.mimeType &&
          other.localPath == this.localPath &&
          other.tempPath == this.tempPath &&
          other.bytesTransferred == this.bytesTransferred &&
          other.state == this.state &&
          other.error == this.error &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FileTransfersCompanion extends UpdateCompanion<FileTransfer> {
  final Value<String> id;
  final Value<String> peerId;
  final Value<String> messageId;
  final Value<String> direction;
  final Value<String> fileName;
  final Value<int> fileSize;
  final Value<String?> mimeType;
  final Value<String?> localPath;
  final Value<String?> tempPath;
  final Value<int> bytesTransferred;
  final Value<String> state;
  final Value<String?> error;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const FileTransfersCompanion({
    this.id = const Value.absent(),
    this.peerId = const Value.absent(),
    this.messageId = const Value.absent(),
    this.direction = const Value.absent(),
    this.fileName = const Value.absent(),
    this.fileSize = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.localPath = const Value.absent(),
    this.tempPath = const Value.absent(),
    this.bytesTransferred = const Value.absent(),
    this.state = const Value.absent(),
    this.error = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FileTransfersCompanion.insert({
    required String id,
    required String peerId,
    required String messageId,
    required String direction,
    required String fileName,
    required int fileSize,
    this.mimeType = const Value.absent(),
    this.localPath = const Value.absent(),
    this.tempPath = const Value.absent(),
    this.bytesTransferred = const Value.absent(),
    required String state,
    this.error = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       peerId = Value(peerId),
       messageId = Value(messageId),
       direction = Value(direction),
       fileName = Value(fileName),
       fileSize = Value(fileSize),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<FileTransfer> custom({
    Expression<String>? id,
    Expression<String>? peerId,
    Expression<String>? messageId,
    Expression<String>? direction,
    Expression<String>? fileName,
    Expression<int>? fileSize,
    Expression<String>? mimeType,
    Expression<String>? localPath,
    Expression<String>? tempPath,
    Expression<int>? bytesTransferred,
    Expression<String>? state,
    Expression<String>? error,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (peerId != null) 'peer_id': peerId,
      if (messageId != null) 'message_id': messageId,
      if (direction != null) 'direction': direction,
      if (fileName != null) 'file_name': fileName,
      if (fileSize != null) 'file_size': fileSize,
      if (mimeType != null) 'mime_type': mimeType,
      if (localPath != null) 'local_path': localPath,
      if (tempPath != null) 'temp_path': tempPath,
      if (bytesTransferred != null) 'bytes_transferred': bytesTransferred,
      if (state != null) 'state': state,
      if (error != null) 'error': error,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FileTransfersCompanion copyWith({
    Value<String>? id,
    Value<String>? peerId,
    Value<String>? messageId,
    Value<String>? direction,
    Value<String>? fileName,
    Value<int>? fileSize,
    Value<String?>? mimeType,
    Value<String?>? localPath,
    Value<String?>? tempPath,
    Value<int>? bytesTransferred,
    Value<String>? state,
    Value<String?>? error,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return FileTransfersCompanion(
      id: id ?? this.id,
      peerId: peerId ?? this.peerId,
      messageId: messageId ?? this.messageId,
      direction: direction ?? this.direction,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      localPath: localPath ?? this.localPath,
      tempPath: tempPath ?? this.tempPath,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      state: state ?? this.state,
      error: error ?? this.error,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (messageId.present) {
      map['message_id'] = Variable<String>(messageId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (fileSize.present) {
      map['file_size'] = Variable<int>(fileSize.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (localPath.present) {
      map['local_path'] = Variable<String>(localPath.value);
    }
    if (tempPath.present) {
      map['temp_path'] = Variable<String>(tempPath.value);
    }
    if (bytesTransferred.present) {
      map['bytes_transferred'] = Variable<int>(bytesTransferred.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FileTransfersCompanion(')
          ..write('id: $id, ')
          ..write('peerId: $peerId, ')
          ..write('messageId: $messageId, ')
          ..write('direction: $direction, ')
          ..write('fileName: $fileName, ')
          ..write('fileSize: $fileSize, ')
          ..write('mimeType: $mimeType, ')
          ..write('localPath: $localPath, ')
          ..write('tempPath: $tempPath, ')
          ..write('bytesTransferred: $bytesTransferred, ')
          ..write('state: $state, ')
          ..write('error: $error, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ConnectionMemoryTableTable extends ConnectionMemoryTable
    with TableInfo<$ConnectionMemoryTableTable, ConnectionMemoryTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectionMemoryTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastConnectedAtMeta = const VerificationMeta(
    'lastConnectedAt',
  );
  @override
  late final GeneratedColumn<int> lastConnectedAt = GeneratedColumn<int>(
    'last_connected_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cachedIceMeta = const VerificationMeta(
    'cachedIce',
  );
  @override
  late final GeneratedColumn<String> cachedIce = GeneratedColumn<String>(
    'cached_ice',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _consecutiveFailuresMeta =
      const VerificationMeta('consecutiveFailures');
  @override
  late final GeneratedColumn<int> consecutiveFailures = GeneratedColumn<int>(
    'consecutive_failures',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    peerId,
    lastConnectedAt,
    cachedIce,
    fingerprint,
    consecutiveFailures,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connection_memory_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConnectionMemoryTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('last_connected_at')) {
      context.handle(
        _lastConnectedAtMeta,
        lastConnectedAt.isAcceptableOrUnknown(
          data['last_connected_at']!,
          _lastConnectedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastConnectedAtMeta);
    }
    if (data.containsKey('cached_ice')) {
      context.handle(
        _cachedIceMeta,
        cachedIce.isAcceptableOrUnknown(data['cached_ice']!, _cachedIceMeta),
      );
    } else if (isInserting) {
      context.missing(_cachedIceMeta);
    }
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('consecutive_failures')) {
      context.handle(
        _consecutiveFailuresMeta,
        consecutiveFailures.isAcceptableOrUnknown(
          data['consecutive_failures']!,
          _consecutiveFailuresMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerId};
  @override
  ConnectionMemoryTableData map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConnectionMemoryTableData(
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      lastConnectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_connected_at'],
      )!,
      cachedIce: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cached_ice'],
      )!,
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      consecutiveFailures: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}consecutive_failures'],
      )!,
    );
  }

  @override
  $ConnectionMemoryTableTable createAlias(String alias) {
    return $ConnectionMemoryTableTable(attachedDatabase, alias);
  }
}

class ConnectionMemoryTableData extends DataClass
    implements Insertable<ConnectionMemoryTableData> {
  final String peerId;
  final int lastConnectedAt;
  final String cachedIce;
  final String fingerprint;
  final int consecutiveFailures;
  const ConnectionMemoryTableData({
    required this.peerId,
    required this.lastConnectedAt,
    required this.cachedIce,
    required this.fingerprint,
    required this.consecutiveFailures,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_id'] = Variable<String>(peerId);
    map['last_connected_at'] = Variable<int>(lastConnectedAt);
    map['cached_ice'] = Variable<String>(cachedIce);
    map['fingerprint'] = Variable<String>(fingerprint);
    map['consecutive_failures'] = Variable<int>(consecutiveFailures);
    return map;
  }

  ConnectionMemoryTableCompanion toCompanion(bool nullToAbsent) {
    return ConnectionMemoryTableCompanion(
      peerId: Value(peerId),
      lastConnectedAt: Value(lastConnectedAt),
      cachedIce: Value(cachedIce),
      fingerprint: Value(fingerprint),
      consecutiveFailures: Value(consecutiveFailures),
    );
  }

  factory ConnectionMemoryTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConnectionMemoryTableData(
      peerId: serializer.fromJson<String>(json['peerId']),
      lastConnectedAt: serializer.fromJson<int>(json['lastConnectedAt']),
      cachedIce: serializer.fromJson<String>(json['cachedIce']),
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      consecutiveFailures: serializer.fromJson<int>(
        json['consecutiveFailures'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerId': serializer.toJson<String>(peerId),
      'lastConnectedAt': serializer.toJson<int>(lastConnectedAt),
      'cachedIce': serializer.toJson<String>(cachedIce),
      'fingerprint': serializer.toJson<String>(fingerprint),
      'consecutiveFailures': serializer.toJson<int>(consecutiveFailures),
    };
  }

  ConnectionMemoryTableData copyWith({
    String? peerId,
    int? lastConnectedAt,
    String? cachedIce,
    String? fingerprint,
    int? consecutiveFailures,
  }) => ConnectionMemoryTableData(
    peerId: peerId ?? this.peerId,
    lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    cachedIce: cachedIce ?? this.cachedIce,
    fingerprint: fingerprint ?? this.fingerprint,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
  );
  ConnectionMemoryTableData copyWithCompanion(
    ConnectionMemoryTableCompanion data,
  ) {
    return ConnectionMemoryTableData(
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      lastConnectedAt: data.lastConnectedAt.present
          ? data.lastConnectedAt.value
          : this.lastConnectedAt,
      cachedIce: data.cachedIce.present ? data.cachedIce.value : this.cachedIce,
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      consecutiveFailures: data.consecutiveFailures.present
          ? data.consecutiveFailures.value
          : this.consecutiveFailures,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionMemoryTableData(')
          ..write('peerId: $peerId, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('cachedIce: $cachedIce, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('consecutiveFailures: $consecutiveFailures')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    peerId,
    lastConnectedAt,
    cachedIce,
    fingerprint,
    consecutiveFailures,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectionMemoryTableData &&
          other.peerId == this.peerId &&
          other.lastConnectedAt == this.lastConnectedAt &&
          other.cachedIce == this.cachedIce &&
          other.fingerprint == this.fingerprint &&
          other.consecutiveFailures == this.consecutiveFailures);
}

class ConnectionMemoryTableCompanion
    extends UpdateCompanion<ConnectionMemoryTableData> {
  final Value<String> peerId;
  final Value<int> lastConnectedAt;
  final Value<String> cachedIce;
  final Value<String> fingerprint;
  final Value<int> consecutiveFailures;
  final Value<int> rowid;
  const ConnectionMemoryTableCompanion({
    this.peerId = const Value.absent(),
    this.lastConnectedAt = const Value.absent(),
    this.cachedIce = const Value.absent(),
    this.fingerprint = const Value.absent(),
    this.consecutiveFailures = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConnectionMemoryTableCompanion.insert({
    required String peerId,
    required int lastConnectedAt,
    required String cachedIce,
    required String fingerprint,
    this.consecutiveFailures = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : peerId = Value(peerId),
       lastConnectedAt = Value(lastConnectedAt),
       cachedIce = Value(cachedIce),
       fingerprint = Value(fingerprint);
  static Insertable<ConnectionMemoryTableData> custom({
    Expression<String>? peerId,
    Expression<int>? lastConnectedAt,
    Expression<String>? cachedIce,
    Expression<String>? fingerprint,
    Expression<int>? consecutiveFailures,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerId != null) 'peer_id': peerId,
      if (lastConnectedAt != null) 'last_connected_at': lastConnectedAt,
      if (cachedIce != null) 'cached_ice': cachedIce,
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (consecutiveFailures != null)
        'consecutive_failures': consecutiveFailures,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConnectionMemoryTableCompanion copyWith({
    Value<String>? peerId,
    Value<int>? lastConnectedAt,
    Value<String>? cachedIce,
    Value<String>? fingerprint,
    Value<int>? consecutiveFailures,
    Value<int>? rowid,
  }) {
    return ConnectionMemoryTableCompanion(
      peerId: peerId ?? this.peerId,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      cachedIce: cachedIce ?? this.cachedIce,
      fingerprint: fingerprint ?? this.fingerprint,
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (lastConnectedAt.present) {
      map['last_connected_at'] = Variable<int>(lastConnectedAt.value);
    }
    if (cachedIce.present) {
      map['cached_ice'] = Variable<String>(cachedIce.value);
    }
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (consecutiveFailures.present) {
      map['consecutive_failures'] = Variable<int>(consecutiveFailures.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionMemoryTableCompanion(')
          ..write('peerId: $peerId, ')
          ..write('lastConnectedAt: $lastConnectedAt, ')
          ..write('cachedIce: $cachedIce, ')
          ..write('fingerprint: $fingerprint, ')
          ..write('consecutiveFailures: $consecutiveFailures, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $IdentityTableTable extends IdentityTable
    with TableInfo<$IdentityTableTable, IdentityTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentityTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    username,
    displayName,
    createdAt,
    gender,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  IdentityTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      ),
    );
  }

  @override
  $IdentityTableTable createAlias(String alias) {
    return $IdentityTableTable(attachedDatabase, alias);
  }
}

class IdentityTableData extends DataClass
    implements Insertable<IdentityTableData> {
  final int id;
  final String username;
  final String displayName;
  final int createdAt;
  final String? gender;
  const IdentityTableData({
    required this.id,
    required this.username,
    required this.displayName,
    required this.createdAt,
    this.gender,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || gender != null) {
      map['gender'] = Variable<String>(gender);
    }
    return map;
  }

  IdentityTableCompanion toCompanion(bool nullToAbsent) {
    return IdentityTableCompanion(
      id: Value(id),
      username: Value(username),
      displayName: Value(displayName),
      createdAt: Value(createdAt),
      gender: gender == null && nullToAbsent
          ? const Value.absent()
          : Value(gender),
    );
  }

  factory IdentityTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityTableData(
      id: serializer.fromJson<int>(json['id']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      gender: serializer.fromJson<String?>(json['gender']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'createdAt': serializer.toJson<int>(createdAt),
      'gender': serializer.toJson<String?>(gender),
    };
  }

  IdentityTableData copyWith({
    int? id,
    String? username,
    String? displayName,
    int? createdAt,
    Value<String?> gender = const Value.absent(),
  }) => IdentityTableData(
    id: id ?? this.id,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt ?? this.createdAt,
    gender: gender.present ? gender.value : this.gender,
  );
  IdentityTableData copyWithCompanion(IdentityTableCompanion data) {
    return IdentityTableData(
      id: data.id.present ? data.id.value : this.id,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      gender: data.gender.present ? data.gender.value : this.gender,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityTableData(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('gender: $gender')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, username, displayName, createdAt, gender);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityTableData &&
          other.id == this.id &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.createdAt == this.createdAt &&
          other.gender == this.gender);
}

class IdentityTableCompanion extends UpdateCompanion<IdentityTableData> {
  final Value<int> id;
  final Value<String> username;
  final Value<String> displayName;
  final Value<int> createdAt;
  final Value<String?> gender;
  const IdentityTableCompanion({
    this.id = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.gender = const Value.absent(),
  });
  IdentityTableCompanion.insert({
    this.id = const Value.absent(),
    required String username,
    required String displayName,
    required int createdAt,
    this.gender = const Value.absent(),
  }) : username = Value(username),
       displayName = Value(displayName),
       createdAt = Value(createdAt);
  static Insertable<IdentityTableData> custom({
    Expression<int>? id,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<int>? createdAt,
    Expression<String>? gender,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (createdAt != null) 'created_at': createdAt,
      if (gender != null) 'gender': gender,
    });
  }

  IdentityTableCompanion copyWith({
    Value<int>? id,
    Value<String>? username,
    Value<String>? displayName,
    Value<int>? createdAt,
    Value<String?>? gender,
  }) {
    return IdentityTableCompanion(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      gender: gender ?? this.gender,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentityTableCompanion(')
          ..write('id: $id, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('createdAt: $createdAt, ')
          ..write('gender: $gender')
          ..write(')'))
        .toString();
  }
}

class $MessageSeqTrackerTable extends MessageSeqTracker
    with TableInfo<$MessageSeqTrackerTable, MessageSeqTrackerData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessageSeqTrackerTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _peerIdMeta = const VerificationMeta('peerId');
  @override
  late final GeneratedColumn<String> peerId = GeneratedColumn<String>(
    'peer_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeqMeta = const VerificationMeta(
    'lastSeq',
  );
  @override
  late final GeneratedColumn<int> lastSeq = GeneratedColumn<int>(
    'last_seq',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [peerId, lastSeq];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'message_seq_tracker';
  @override
  VerificationContext validateIntegrity(
    Insertable<MessageSeqTrackerData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('peer_id')) {
      context.handle(
        _peerIdMeta,
        peerId.isAcceptableOrUnknown(data['peer_id']!, _peerIdMeta),
      );
    } else if (isInserting) {
      context.missing(_peerIdMeta);
    }
    if (data.containsKey('last_seq')) {
      context.handle(
        _lastSeqMeta,
        lastSeq.isAcceptableOrUnknown(data['last_seq']!, _lastSeqMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeqMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {peerId};
  @override
  MessageSeqTrackerData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MessageSeqTrackerData(
      peerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}peer_id'],
      )!,
      lastSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seq'],
      )!,
    );
  }

  @override
  $MessageSeqTrackerTable createAlias(String alias) {
    return $MessageSeqTrackerTable(attachedDatabase, alias);
  }
}

class MessageSeqTrackerData extends DataClass
    implements Insertable<MessageSeqTrackerData> {
  final String peerId;
  final int lastSeq;
  const MessageSeqTrackerData({required this.peerId, required this.lastSeq});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['peer_id'] = Variable<String>(peerId);
    map['last_seq'] = Variable<int>(lastSeq);
    return map;
  }

  MessageSeqTrackerCompanion toCompanion(bool nullToAbsent) {
    return MessageSeqTrackerCompanion(
      peerId: Value(peerId),
      lastSeq: Value(lastSeq),
    );
  }

  factory MessageSeqTrackerData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MessageSeqTrackerData(
      peerId: serializer.fromJson<String>(json['peerId']),
      lastSeq: serializer.fromJson<int>(json['lastSeq']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'peerId': serializer.toJson<String>(peerId),
      'lastSeq': serializer.toJson<int>(lastSeq),
    };
  }

  MessageSeqTrackerData copyWith({String? peerId, int? lastSeq}) =>
      MessageSeqTrackerData(
        peerId: peerId ?? this.peerId,
        lastSeq: lastSeq ?? this.lastSeq,
      );
  MessageSeqTrackerData copyWithCompanion(MessageSeqTrackerCompanion data) {
    return MessageSeqTrackerData(
      peerId: data.peerId.present ? data.peerId.value : this.peerId,
      lastSeq: data.lastSeq.present ? data.lastSeq.value : this.lastSeq,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MessageSeqTrackerData(')
          ..write('peerId: $peerId, ')
          ..write('lastSeq: $lastSeq')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(peerId, lastSeq);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MessageSeqTrackerData &&
          other.peerId == this.peerId &&
          other.lastSeq == this.lastSeq);
}

class MessageSeqTrackerCompanion
    extends UpdateCompanion<MessageSeqTrackerData> {
  final Value<String> peerId;
  final Value<int> lastSeq;
  final Value<int> rowid;
  const MessageSeqTrackerCompanion({
    this.peerId = const Value.absent(),
    this.lastSeq = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessageSeqTrackerCompanion.insert({
    required String peerId,
    required int lastSeq,
    this.rowid = const Value.absent(),
  }) : peerId = Value(peerId),
       lastSeq = Value(lastSeq);
  static Insertable<MessageSeqTrackerData> custom({
    Expression<String>? peerId,
    Expression<int>? lastSeq,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (peerId != null) 'peer_id': peerId,
      if (lastSeq != null) 'last_seq': lastSeq,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessageSeqTrackerCompanion copyWith({
    Value<String>? peerId,
    Value<int>? lastSeq,
    Value<int>? rowid,
  }) {
    return MessageSeqTrackerCompanion(
      peerId: peerId ?? this.peerId,
      lastSeq: lastSeq ?? this.lastSeq,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (peerId.present) {
      map['peer_id'] = Variable<String>(peerId.value);
    }
    if (lastSeq.present) {
      map['last_seq'] = Variable<int>(lastSeq.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessageSeqTrackerCompanion(')
          ..write('peerId: $peerId, ')
          ..write('lastSeq: $lastSeq, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$RainDatabase extends GeneratedDatabase {
  _$RainDatabase(QueryExecutor e) : super(e);
  $RainDatabaseManager get managers => $RainDatabaseManager(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $FriendsTable friends = $FriendsTable(this);
  late final $QueuedMessagesTable queuedMessages = $QueuedMessagesTable(this);
  late final $FileTransfersTable fileTransfers = $FileTransfersTable(this);
  late final $ConnectionMemoryTableTable connectionMemoryTable =
      $ConnectionMemoryTableTable(this);
  late final $IdentityTableTable identityTable = $IdentityTableTable(this);
  late final $MessageSeqTrackerTable messageSeqTracker =
      $MessageSeqTrackerTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    messages,
    friends,
    queuedMessages,
    fileTransfers,
    connectionMemoryTable,
    identityTable,
    messageSeqTracker,
  ];
}

typedef $$MessagesTableCreateCompanionBuilder =
    MessagesCompanion Function({
      required String id,
      required String peerId,
      required String content,
      required int sentAt,
      required int seq,
      required String type,
      required String status,
      required bool isOutgoing,
      Value<int> rowid,
    });
typedef $$MessagesTableUpdateCompanionBuilder =
    MessagesCompanion Function({
      Value<String> id,
      Value<String> peerId,
      Value<String> content,
      Value<int> sentAt,
      Value<int> seq,
      Value<String> type,
      Value<String> status,
      Value<bool> isOutgoing,
      Value<int> rowid,
    });

class $$MessagesTableFilterComposer
    extends Composer<_$RainDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessagesTableOrderingComposer
    extends Composer<_$RainDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$RainDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get isOutgoing => $composableBuilder(
    column: $table.isOutgoing,
    builder: (column) => column,
  );
}

class $$MessagesTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $MessagesTable,
          Message,
          $$MessagesTableFilterComposer,
          $$MessagesTableOrderingComposer,
          $$MessagesTableAnnotationComposer,
          $$MessagesTableCreateCompanionBuilder,
          $$MessagesTableUpdateCompanionBuilder,
          (Message, BaseReferences<_$RainDatabase, $MessagesTable, Message>),
          Message,
          PrefetchHooks Function()
        > {
  $$MessagesTableTableManager(_$RainDatabase db, $MessagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> sentAt = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> isOutgoing = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion(
                id: id,
                peerId: peerId,
                content: content,
                sentAt: sentAt,
                seq: seq,
                type: type,
                status: status,
                isOutgoing: isOutgoing,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String peerId,
                required String content,
                required int sentAt,
                required int seq,
                required String type,
                required String status,
                required bool isOutgoing,
                Value<int> rowid = const Value.absent(),
              }) => MessagesCompanion.insert(
                id: id,
                peerId: peerId,
                content: content,
                sentAt: sentAt,
                seq: seq,
                type: type,
                status: status,
                isOutgoing: isOutgoing,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $MessagesTable,
      Message,
      $$MessagesTableFilterComposer,
      $$MessagesTableOrderingComposer,
      $$MessagesTableAnnotationComposer,
      $$MessagesTableCreateCompanionBuilder,
      $$MessagesTableUpdateCompanionBuilder,
      (Message, BaseReferences<_$RainDatabase, $MessagesTable, Message>),
      Message,
      PrefetchHooks Function()
    >;
typedef $$FriendsTableCreateCompanionBuilder =
    FriendsCompanion Function({
      required String username,
      required String displayName,
      Value<String?> gender,
      required String state,
      required int addedAt,
      Value<int?> lastOnlineAt,
      Value<bool> online,
      Value<int> unreadCount,
      Value<int> rowid,
    });
typedef $$FriendsTableUpdateCompanionBuilder =
    FriendsCompanion Function({
      Value<String> username,
      Value<String> displayName,
      Value<String?> gender,
      Value<String> state,
      Value<int> addedAt,
      Value<int?> lastOnlineAt,
      Value<bool> online,
      Value<int> unreadCount,
      Value<int> rowid,
    });

class $$FriendsTableFilterComposer
    extends Composer<_$RainDatabase, $FriendsTable> {
  $$FriendsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastOnlineAt => $composableBuilder(
    column: $table.lastOnlineAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get online => $composableBuilder(
    column: $table.online,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FriendsTableOrderingComposer
    extends Composer<_$RainDatabase, $FriendsTable> {
  $$FriendsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastOnlineAt => $composableBuilder(
    column: $table.lastOnlineAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get online => $composableBuilder(
    column: $table.online,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FriendsTableAnnotationComposer
    extends Composer<_$RainDatabase, $FriendsTable> {
  $$FriendsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get lastOnlineAt => $composableBuilder(
    column: $table.lastOnlineAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get online =>
      $composableBuilder(column: $table.online, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
    column: $table.unreadCount,
    builder: (column) => column,
  );
}

class $$FriendsTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $FriendsTable,
          Friend,
          $$FriendsTableFilterComposer,
          $$FriendsTableOrderingComposer,
          $$FriendsTableAnnotationComposer,
          $$FriendsTableCreateCompanionBuilder,
          $$FriendsTableUpdateCompanionBuilder,
          (Friend, BaseReferences<_$RainDatabase, $FriendsTable, Friend>),
          Friend,
          PrefetchHooks Function()
        > {
  $$FriendsTableTableManager(_$RainDatabase db, $FriendsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FriendsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FriendsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FriendsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> gender = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int?> lastOnlineAt = const Value.absent(),
                Value<bool> online = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendsCompanion(
                username: username,
                displayName: displayName,
                gender: gender,
                state: state,
                addedAt: addedAt,
                lastOnlineAt: lastOnlineAt,
                online: online,
                unreadCount: unreadCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String username,
                required String displayName,
                Value<String?> gender = const Value.absent(),
                required String state,
                required int addedAt,
                Value<int?> lastOnlineAt = const Value.absent(),
                Value<bool> online = const Value.absent(),
                Value<int> unreadCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FriendsCompanion.insert(
                username: username,
                displayName: displayName,
                gender: gender,
                state: state,
                addedAt: addedAt,
                lastOnlineAt: lastOnlineAt,
                online: online,
                unreadCount: unreadCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FriendsTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $FriendsTable,
      Friend,
      $$FriendsTableFilterComposer,
      $$FriendsTableOrderingComposer,
      $$FriendsTableAnnotationComposer,
      $$FriendsTableCreateCompanionBuilder,
      $$FriendsTableUpdateCompanionBuilder,
      (Friend, BaseReferences<_$RainDatabase, $FriendsTable, Friend>),
      Friend,
      PrefetchHooks Function()
    >;
typedef $$QueuedMessagesTableCreateCompanionBuilder =
    QueuedMessagesCompanion Function({
      required String id,
      required String to,
      required String content,
      required int sentAt,
      required int seq,
      required String status,
      Value<int> rowid,
    });
typedef $$QueuedMessagesTableUpdateCompanionBuilder =
    QueuedMessagesCompanion Function({
      Value<String> id,
      Value<String> to,
      Value<String> content,
      Value<int> sentAt,
      Value<int> seq,
      Value<String> status,
      Value<int> rowid,
    });

class $$QueuedMessagesTableFilterComposer
    extends Composer<_$RainDatabase, $QueuedMessagesTable> {
  $$QueuedMessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get to => $composableBuilder(
    column: $table.to,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueuedMessagesTableOrderingComposer
    extends Composer<_$RainDatabase, $QueuedMessagesTable> {
  $$QueuedMessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get to => $composableBuilder(
    column: $table.to,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sentAt => $composableBuilder(
    column: $table.sentAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get seq => $composableBuilder(
    column: $table.seq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueuedMessagesTableAnnotationComposer
    extends Composer<_$RainDatabase, $QueuedMessagesTable> {
  $$QueuedMessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get to =>
      $composableBuilder(column: $table.to, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get sentAt =>
      $composableBuilder(column: $table.sentAt, builder: (column) => column);

  GeneratedColumn<int> get seq =>
      $composableBuilder(column: $table.seq, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$QueuedMessagesTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $QueuedMessagesTable,
          QueuedMessage,
          $$QueuedMessagesTableFilterComposer,
          $$QueuedMessagesTableOrderingComposer,
          $$QueuedMessagesTableAnnotationComposer,
          $$QueuedMessagesTableCreateCompanionBuilder,
          $$QueuedMessagesTableUpdateCompanionBuilder,
          (
            QueuedMessage,
            BaseReferences<_$RainDatabase, $QueuedMessagesTable, QueuedMessage>,
          ),
          QueuedMessage,
          PrefetchHooks Function()
        > {
  $$QueuedMessagesTableTableManager(
    _$RainDatabase db,
    $QueuedMessagesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueuedMessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueuedMessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueuedMessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> to = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> sentAt = const Value.absent(),
                Value<int> seq = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => QueuedMessagesCompanion(
                id: id,
                to: to,
                content: content,
                sentAt: sentAt,
                seq: seq,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String to,
                required String content,
                required int sentAt,
                required int seq,
                required String status,
                Value<int> rowid = const Value.absent(),
              }) => QueuedMessagesCompanion.insert(
                id: id,
                to: to,
                content: content,
                sentAt: sentAt,
                seq: seq,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueuedMessagesTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $QueuedMessagesTable,
      QueuedMessage,
      $$QueuedMessagesTableFilterComposer,
      $$QueuedMessagesTableOrderingComposer,
      $$QueuedMessagesTableAnnotationComposer,
      $$QueuedMessagesTableCreateCompanionBuilder,
      $$QueuedMessagesTableUpdateCompanionBuilder,
      (
        QueuedMessage,
        BaseReferences<_$RainDatabase, $QueuedMessagesTable, QueuedMessage>,
      ),
      QueuedMessage,
      PrefetchHooks Function()
    >;
typedef $$FileTransfersTableCreateCompanionBuilder =
    FileTransfersCompanion Function({
      required String id,
      required String peerId,
      required String messageId,
      required String direction,
      required String fileName,
      required int fileSize,
      Value<String?> mimeType,
      Value<String?> localPath,
      Value<String?> tempPath,
      Value<int> bytesTransferred,
      required String state,
      Value<String?> error,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$FileTransfersTableUpdateCompanionBuilder =
    FileTransfersCompanion Function({
      Value<String> id,
      Value<String> peerId,
      Value<String> messageId,
      Value<String> direction,
      Value<String> fileName,
      Value<int> fileSize,
      Value<String?> mimeType,
      Value<String?> localPath,
      Value<String?> tempPath,
      Value<int> bytesTransferred,
      Value<String> state,
      Value<String?> error,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

class $$FileTransfersTableFilterComposer
    extends Composer<_$RainDatabase, $FileTransfersTable> {
  $$FileTransfersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tempPath => $composableBuilder(
    column: $table.tempPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FileTransfersTableOrderingComposer
    extends Composer<_$RainDatabase, $FileTransfersTable> {
  $$FileTransfersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get messageId => $composableBuilder(
    column: $table.messageId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fileName => $composableBuilder(
    column: $table.fileName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSize => $composableBuilder(
    column: $table.fileSize,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localPath => $composableBuilder(
    column: $table.localPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tempPath => $composableBuilder(
    column: $table.tempPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FileTransfersTableAnnotationComposer
    extends Composer<_$RainDatabase, $FileTransfersTable> {
  $$FileTransfersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<String> get messageId =>
      $composableBuilder(column: $table.messageId, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<int> get fileSize =>
      $composableBuilder(column: $table.fileSize, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get localPath =>
      $composableBuilder(column: $table.localPath, builder: (column) => column);

  GeneratedColumn<String> get tempPath =>
      $composableBuilder(column: $table.tempPath, builder: (column) => column);

  GeneratedColumn<int> get bytesTransferred => $composableBuilder(
    column: $table.bytesTransferred,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$FileTransfersTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $FileTransfersTable,
          FileTransfer,
          $$FileTransfersTableFilterComposer,
          $$FileTransfersTableOrderingComposer,
          $$FileTransfersTableAnnotationComposer,
          $$FileTransfersTableCreateCompanionBuilder,
          $$FileTransfersTableUpdateCompanionBuilder,
          (
            FileTransfer,
            BaseReferences<_$RainDatabase, $FileTransfersTable, FileTransfer>,
          ),
          FileTransfer,
          PrefetchHooks Function()
        > {
  $$FileTransfersTableTableManager(_$RainDatabase db, $FileTransfersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FileTransfersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FileTransfersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FileTransfersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> peerId = const Value.absent(),
                Value<String> messageId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<String> fileName = const Value.absent(),
                Value<int> fileSize = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> tempPath = const Value.absent(),
                Value<int> bytesTransferred = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> error = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FileTransfersCompanion(
                id: id,
                peerId: peerId,
                messageId: messageId,
                direction: direction,
                fileName: fileName,
                fileSize: fileSize,
                mimeType: mimeType,
                localPath: localPath,
                tempPath: tempPath,
                bytesTransferred: bytesTransferred,
                state: state,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String peerId,
                required String messageId,
                required String direction,
                required String fileName,
                required int fileSize,
                Value<String?> mimeType = const Value.absent(),
                Value<String?> localPath = const Value.absent(),
                Value<String?> tempPath = const Value.absent(),
                Value<int> bytesTransferred = const Value.absent(),
                required String state,
                Value<String?> error = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FileTransfersCompanion.insert(
                id: id,
                peerId: peerId,
                messageId: messageId,
                direction: direction,
                fileName: fileName,
                fileSize: fileSize,
                mimeType: mimeType,
                localPath: localPath,
                tempPath: tempPath,
                bytesTransferred: bytesTransferred,
                state: state,
                error: error,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FileTransfersTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $FileTransfersTable,
      FileTransfer,
      $$FileTransfersTableFilterComposer,
      $$FileTransfersTableOrderingComposer,
      $$FileTransfersTableAnnotationComposer,
      $$FileTransfersTableCreateCompanionBuilder,
      $$FileTransfersTableUpdateCompanionBuilder,
      (
        FileTransfer,
        BaseReferences<_$RainDatabase, $FileTransfersTable, FileTransfer>,
      ),
      FileTransfer,
      PrefetchHooks Function()
    >;
typedef $$ConnectionMemoryTableTableCreateCompanionBuilder =
    ConnectionMemoryTableCompanion Function({
      required String peerId,
      required int lastConnectedAt,
      required String cachedIce,
      required String fingerprint,
      Value<int> consecutiveFailures,
      Value<int> rowid,
    });
typedef $$ConnectionMemoryTableTableUpdateCompanionBuilder =
    ConnectionMemoryTableCompanion Function({
      Value<String> peerId,
      Value<int> lastConnectedAt,
      Value<String> cachedIce,
      Value<String> fingerprint,
      Value<int> consecutiveFailures,
      Value<int> rowid,
    });

class $$ConnectionMemoryTableTableFilterComposer
    extends Composer<_$RainDatabase, $ConnectionMemoryTableTable> {
  $$ConnectionMemoryTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cachedIce => $composableBuilder(
    column: $table.cachedIce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get consecutiveFailures => $composableBuilder(
    column: $table.consecutiveFailures,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ConnectionMemoryTableTableOrderingComposer
    extends Composer<_$RainDatabase, $ConnectionMemoryTableTable> {
  $$ConnectionMemoryTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cachedIce => $composableBuilder(
    column: $table.cachedIce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get consecutiveFailures => $composableBuilder(
    column: $table.consecutiveFailures,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConnectionMemoryTableTableAnnotationComposer
    extends Composer<_$RainDatabase, $ConnectionMemoryTableTable> {
  $$ConnectionMemoryTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<int> get lastConnectedAt => $composableBuilder(
    column: $table.lastConnectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cachedIce =>
      $composableBuilder(column: $table.cachedIce, builder: (column) => column);

  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<int> get consecutiveFailures => $composableBuilder(
    column: $table.consecutiveFailures,
    builder: (column) => column,
  );
}

class $$ConnectionMemoryTableTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $ConnectionMemoryTableTable,
          ConnectionMemoryTableData,
          $$ConnectionMemoryTableTableFilterComposer,
          $$ConnectionMemoryTableTableOrderingComposer,
          $$ConnectionMemoryTableTableAnnotationComposer,
          $$ConnectionMemoryTableTableCreateCompanionBuilder,
          $$ConnectionMemoryTableTableUpdateCompanionBuilder,
          (
            ConnectionMemoryTableData,
            BaseReferences<
              _$RainDatabase,
              $ConnectionMemoryTableTable,
              ConnectionMemoryTableData
            >,
          ),
          ConnectionMemoryTableData,
          PrefetchHooks Function()
        > {
  $$ConnectionMemoryTableTableTableManager(
    _$RainDatabase db,
    $ConnectionMemoryTableTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConnectionMemoryTableTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ConnectionMemoryTableTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ConnectionMemoryTableTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> peerId = const Value.absent(),
                Value<int> lastConnectedAt = const Value.absent(),
                Value<String> cachedIce = const Value.absent(),
                Value<String> fingerprint = const Value.absent(),
                Value<int> consecutiveFailures = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionMemoryTableCompanion(
                peerId: peerId,
                lastConnectedAt: lastConnectedAt,
                cachedIce: cachedIce,
                fingerprint: fingerprint,
                consecutiveFailures: consecutiveFailures,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerId,
                required int lastConnectedAt,
                required String cachedIce,
                required String fingerprint,
                Value<int> consecutiveFailures = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionMemoryTableCompanion.insert(
                peerId: peerId,
                lastConnectedAt: lastConnectedAt,
                cachedIce: cachedIce,
                fingerprint: fingerprint,
                consecutiveFailures: consecutiveFailures,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ConnectionMemoryTableTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $ConnectionMemoryTableTable,
      ConnectionMemoryTableData,
      $$ConnectionMemoryTableTableFilterComposer,
      $$ConnectionMemoryTableTableOrderingComposer,
      $$ConnectionMemoryTableTableAnnotationComposer,
      $$ConnectionMemoryTableTableCreateCompanionBuilder,
      $$ConnectionMemoryTableTableUpdateCompanionBuilder,
      (
        ConnectionMemoryTableData,
        BaseReferences<
          _$RainDatabase,
          $ConnectionMemoryTableTable,
          ConnectionMemoryTableData
        >,
      ),
      ConnectionMemoryTableData,
      PrefetchHooks Function()
    >;
typedef $$IdentityTableTableCreateCompanionBuilder =
    IdentityTableCompanion Function({
      Value<int> id,
      required String username,
      required String displayName,
      required int createdAt,
      Value<String?> gender,
    });
typedef $$IdentityTableTableUpdateCompanionBuilder =
    IdentityTableCompanion Function({
      Value<int> id,
      Value<String> username,
      Value<String> displayName,
      Value<int> createdAt,
      Value<String?> gender,
    });

class $$IdentityTableTableFilterComposer
    extends Composer<_$RainDatabase, $IdentityTableTable> {
  $$IdentityTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IdentityTableTableOrderingComposer
    extends Composer<_$RainDatabase, $IdentityTableTable> {
  $$IdentityTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IdentityTableTableAnnotationComposer
    extends Composer<_$RainDatabase, $IdentityTableTable> {
  $$IdentityTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);
}

class $$IdentityTableTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $IdentityTableTable,
          IdentityTableData,
          $$IdentityTableTableFilterComposer,
          $$IdentityTableTableOrderingComposer,
          $$IdentityTableTableAnnotationComposer,
          $$IdentityTableTableCreateCompanionBuilder,
          $$IdentityTableTableUpdateCompanionBuilder,
          (
            IdentityTableData,
            BaseReferences<
              _$RainDatabase,
              $IdentityTableTable,
              IdentityTableData
            >,
          ),
          IdentityTableData,
          PrefetchHooks Function()
        > {
  $$IdentityTableTableTableManager(_$RainDatabase db, $IdentityTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentityTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentityTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentityTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> gender = const Value.absent(),
              }) => IdentityTableCompanion(
                id: id,
                username: username,
                displayName: displayName,
                createdAt: createdAt,
                gender: gender,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String username,
                required String displayName,
                required int createdAt,
                Value<String?> gender = const Value.absent(),
              }) => IdentityTableCompanion.insert(
                id: id,
                username: username,
                displayName: displayName,
                createdAt: createdAt,
                gender: gender,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IdentityTableTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $IdentityTableTable,
      IdentityTableData,
      $$IdentityTableTableFilterComposer,
      $$IdentityTableTableOrderingComposer,
      $$IdentityTableTableAnnotationComposer,
      $$IdentityTableTableCreateCompanionBuilder,
      $$IdentityTableTableUpdateCompanionBuilder,
      (
        IdentityTableData,
        BaseReferences<_$RainDatabase, $IdentityTableTable, IdentityTableData>,
      ),
      IdentityTableData,
      PrefetchHooks Function()
    >;
typedef $$MessageSeqTrackerTableCreateCompanionBuilder =
    MessageSeqTrackerCompanion Function({
      required String peerId,
      required int lastSeq,
      Value<int> rowid,
    });
typedef $$MessageSeqTrackerTableUpdateCompanionBuilder =
    MessageSeqTrackerCompanion Function({
      Value<String> peerId,
      Value<int> lastSeq,
      Value<int> rowid,
    });

class $$MessageSeqTrackerTableFilterComposer
    extends Composer<_$RainDatabase, $MessageSeqTrackerTable> {
  $$MessageSeqTrackerTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeq => $composableBuilder(
    column: $table.lastSeq,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MessageSeqTrackerTableOrderingComposer
    extends Composer<_$RainDatabase, $MessageSeqTrackerTable> {
  $$MessageSeqTrackerTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get peerId => $composableBuilder(
    column: $table.peerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeq => $composableBuilder(
    column: $table.lastSeq,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MessageSeqTrackerTableAnnotationComposer
    extends Composer<_$RainDatabase, $MessageSeqTrackerTable> {
  $$MessageSeqTrackerTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get peerId =>
      $composableBuilder(column: $table.peerId, builder: (column) => column);

  GeneratedColumn<int> get lastSeq =>
      $composableBuilder(column: $table.lastSeq, builder: (column) => column);
}

class $$MessageSeqTrackerTableTableManager
    extends
        RootTableManager<
          _$RainDatabase,
          $MessageSeqTrackerTable,
          MessageSeqTrackerData,
          $$MessageSeqTrackerTableFilterComposer,
          $$MessageSeqTrackerTableOrderingComposer,
          $$MessageSeqTrackerTableAnnotationComposer,
          $$MessageSeqTrackerTableCreateCompanionBuilder,
          $$MessageSeqTrackerTableUpdateCompanionBuilder,
          (
            MessageSeqTrackerData,
            BaseReferences<
              _$RainDatabase,
              $MessageSeqTrackerTable,
              MessageSeqTrackerData
            >,
          ),
          MessageSeqTrackerData,
          PrefetchHooks Function()
        > {
  $$MessageSeqTrackerTableTableManager(
    _$RainDatabase db,
    $MessageSeqTrackerTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessageSeqTrackerTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessageSeqTrackerTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessageSeqTrackerTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> peerId = const Value.absent(),
                Value<int> lastSeq = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MessageSeqTrackerCompanion(
                peerId: peerId,
                lastSeq: lastSeq,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String peerId,
                required int lastSeq,
                Value<int> rowid = const Value.absent(),
              }) => MessageSeqTrackerCompanion.insert(
                peerId: peerId,
                lastSeq: lastSeq,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MessageSeqTrackerTableProcessedTableManager =
    ProcessedTableManager<
      _$RainDatabase,
      $MessageSeqTrackerTable,
      MessageSeqTrackerData,
      $$MessageSeqTrackerTableFilterComposer,
      $$MessageSeqTrackerTableOrderingComposer,
      $$MessageSeqTrackerTableAnnotationComposer,
      $$MessageSeqTrackerTableCreateCompanionBuilder,
      $$MessageSeqTrackerTableUpdateCompanionBuilder,
      (
        MessageSeqTrackerData,
        BaseReferences<
          _$RainDatabase,
          $MessageSeqTrackerTable,
          MessageSeqTrackerData
        >,
      ),
      MessageSeqTrackerData,
      PrefetchHooks Function()
    >;

class $RainDatabaseManager {
  final _$RainDatabase _db;
  $RainDatabaseManager(this._db);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$FriendsTableTableManager get friends =>
      $$FriendsTableTableManager(_db, _db.friends);
  $$QueuedMessagesTableTableManager get queuedMessages =>
      $$QueuedMessagesTableTableManager(_db, _db.queuedMessages);
  $$FileTransfersTableTableManager get fileTransfers =>
      $$FileTransfersTableTableManager(_db, _db.fileTransfers);
  $$ConnectionMemoryTableTableTableManager get connectionMemoryTable =>
      $$ConnectionMemoryTableTableTableManager(_db, _db.connectionMemoryTable);
  $$IdentityTableTableTableManager get identityTable =>
      $$IdentityTableTableTableManager(_db, _db.identityTable);
  $$MessageSeqTrackerTableTableManager get messageSeqTracker =>
      $$MessageSeqTrackerTableTableManager(_db, _db.messageSeqTracker);
}
