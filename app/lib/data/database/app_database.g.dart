// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $PreferencesTable extends Preferences
    with TableInfo<$PreferencesTable, Preference> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PreferencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'preferences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Preference> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Preference map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preference(
      key:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}key'],
          )!,
      value:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}value'],
          )!,
    );
  }

  @override
  $PreferencesTable createAlias(String alias) {
    return $PreferencesTable(attachedDatabase, alias);
  }
}

class Preference extends DataClass implements Insertable<Preference> {
  final String key;
  final String value;
  const Preference({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  PreferencesCompanion toCompanion(bool nullToAbsent) {
    return PreferencesCompanion(key: Value(key), value: Value(value));
  }

  factory Preference.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preference(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Preference copyWith({String? key, String? value}) =>
      Preference(key: key ?? this.key, value: value ?? this.value);
  Preference copyWithCompanion(PreferencesCompanion data) {
    return Preference(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Preference(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preference &&
          other.key == this.key &&
          other.value == this.value);
}

class PreferencesCompanion extends UpdateCompanion<Preference> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const PreferencesCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PreferencesCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Preference> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PreferencesCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return PreferencesCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PreferencesCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NodesTable extends Nodes with TableInfo<$NodesTable, Node> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverMeta = const VerificationMeta('server');
  @override
  late final GeneratedColumn<String> server = GeneratedColumn<String>(
    'server',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tlsMeta = const VerificationMeta('tls');
  @override
  late final GeneratedColumn<bool> tls = GeneratedColumn<bool>(
    'tls',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("tls" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _credentialMeta = const VerificationMeta(
    'credential',
  );
  @override
  late final GeneratedColumn<String> credential = GeneratedColumn<String>(
    'credential',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _optionsMeta = const VerificationMeta(
    'options',
  );
  @override
  late final GeneratedColumn<String> options = GeneratedColumn<String>(
    'options',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceKeyMeta = const VerificationMeta(
    'sourceKey',
  );
  @override
  late final GeneratedColumn<String> sourceKey = GeneratedColumn<String>(
    'source_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    protocol,
    server,
    port,
    tls,
    credential,
    revision,
    options,
    groupId,
    sourceKey,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Node> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    } else if (isInserting) {
      context.missing(_protocolMeta);
    }
    if (data.containsKey('server')) {
      context.handle(
        _serverMeta,
        server.isAcceptableOrUnknown(data['server']!, _serverMeta),
      );
    } else if (isInserting) {
      context.missing(_serverMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('tls')) {
      context.handle(
        _tlsMeta,
        tls.isAcceptableOrUnknown(data['tls']!, _tlsMeta),
      );
    }
    if (data.containsKey('credential')) {
      context.handle(
        _credentialMeta,
        credential.isAcceptableOrUnknown(data['credential']!, _credentialMeta),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    if (data.containsKey('options')) {
      context.handle(
        _optionsMeta,
        options.isAcceptableOrUnknown(data['options']!, _optionsMeta),
      );
    }
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    }
    if (data.containsKey('source_key')) {
      context.handle(
        _sourceKeyMeta,
        sourceKey.isAcceptableOrUnknown(data['source_key']!, _sourceKeyMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Node map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Node(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      protocol:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}protocol'],
          )!,
      server:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}server'],
          )!,
      port:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}port'],
          )!,
      tls:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}tls'],
          )!,
      credential:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}credential'],
          )!,
      revision:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}revision'],
          )!,
      options:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}options'],
          )!,
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      ),
      sourceKey:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source_key'],
          )!,
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }
}

class Node extends DataClass implements Insertable<Node> {
  final String id;
  final String name;
  final String protocol;
  final String server;
  final int port;
  final bool tls;
  final String credential;
  final int revision;
  final String options;
  final String? groupId;
  final String sourceKey;
  const Node({
    required this.id,
    required this.name,
    required this.protocol,
    required this.server,
    required this.port,
    required this.tls,
    required this.credential,
    required this.revision,
    required this.options,
    this.groupId,
    required this.sourceKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['protocol'] = Variable<String>(protocol);
    map['server'] = Variable<String>(server);
    map['port'] = Variable<int>(port);
    map['tls'] = Variable<bool>(tls);
    map['credential'] = Variable<String>(credential);
    map['revision'] = Variable<int>(revision);
    map['options'] = Variable<String>(options);
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    map['source_key'] = Variable<String>(sourceKey);
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      id: Value(id),
      name: Value(name),
      protocol: Value(protocol),
      server: Value(server),
      port: Value(port),
      tls: Value(tls),
      credential: Value(credential),
      revision: Value(revision),
      options: Value(options),
      groupId:
          groupId == null && nullToAbsent
              ? const Value.absent()
              : Value(groupId),
      sourceKey: Value(sourceKey),
    );
  }

  factory Node.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Node(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      protocol: serializer.fromJson<String>(json['protocol']),
      server: serializer.fromJson<String>(json['server']),
      port: serializer.fromJson<int>(json['port']),
      tls: serializer.fromJson<bool>(json['tls']),
      credential: serializer.fromJson<String>(json['credential']),
      revision: serializer.fromJson<int>(json['revision']),
      options: serializer.fromJson<String>(json['options']),
      groupId: serializer.fromJson<String?>(json['groupId']),
      sourceKey: serializer.fromJson<String>(json['sourceKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'protocol': serializer.toJson<String>(protocol),
      'server': serializer.toJson<String>(server),
      'port': serializer.toJson<int>(port),
      'tls': serializer.toJson<bool>(tls),
      'credential': serializer.toJson<String>(credential),
      'revision': serializer.toJson<int>(revision),
      'options': serializer.toJson<String>(options),
      'groupId': serializer.toJson<String?>(groupId),
      'sourceKey': serializer.toJson<String>(sourceKey),
    };
  }

  Node copyWith({
    String? id,
    String? name,
    String? protocol,
    String? server,
    int? port,
    bool? tls,
    String? credential,
    int? revision,
    String? options,
    Value<String?> groupId = const Value.absent(),
    String? sourceKey,
  }) => Node(
    id: id ?? this.id,
    name: name ?? this.name,
    protocol: protocol ?? this.protocol,
    server: server ?? this.server,
    port: port ?? this.port,
    tls: tls ?? this.tls,
    credential: credential ?? this.credential,
    revision: revision ?? this.revision,
    options: options ?? this.options,
    groupId: groupId.present ? groupId.value : this.groupId,
    sourceKey: sourceKey ?? this.sourceKey,
  );
  Node copyWithCompanion(NodesCompanion data) {
    return Node(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      server: data.server.present ? data.server.value : this.server,
      port: data.port.present ? data.port.value : this.port,
      tls: data.tls.present ? data.tls.value : this.tls,
      credential:
          data.credential.present ? data.credential.value : this.credential,
      revision: data.revision.present ? data.revision.value : this.revision,
      options: data.options.present ? data.options.value : this.options,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      sourceKey: data.sourceKey.present ? data.sourceKey.value : this.sourceKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Node(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('protocol: $protocol, ')
          ..write('server: $server, ')
          ..write('port: $port, ')
          ..write('tls: $tls, ')
          ..write('credential: $credential, ')
          ..write('revision: $revision, ')
          ..write('options: $options, ')
          ..write('groupId: $groupId, ')
          ..write('sourceKey: $sourceKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    protocol,
    server,
    port,
    tls,
    credential,
    revision,
    options,
    groupId,
    sourceKey,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Node &&
          other.id == this.id &&
          other.name == this.name &&
          other.protocol == this.protocol &&
          other.server == this.server &&
          other.port == this.port &&
          other.tls == this.tls &&
          other.credential == this.credential &&
          other.revision == this.revision &&
          other.options == this.options &&
          other.groupId == this.groupId &&
          other.sourceKey == this.sourceKey);
}

class NodesCompanion extends UpdateCompanion<Node> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> protocol;
  final Value<String> server;
  final Value<int> port;
  final Value<bool> tls;
  final Value<String> credential;
  final Value<int> revision;
  final Value<String> options;
  final Value<String?> groupId;
  final Value<String> sourceKey;
  final Value<int> rowid;
  const NodesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.protocol = const Value.absent(),
    this.server = const Value.absent(),
    this.port = const Value.absent(),
    this.tls = const Value.absent(),
    this.credential = const Value.absent(),
    this.revision = const Value.absent(),
    this.options = const Value.absent(),
    this.groupId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodesCompanion.insert({
    required String id,
    required String name,
    required String protocol,
    required String server,
    required int port,
    this.tls = const Value.absent(),
    this.credential = const Value.absent(),
    this.revision = const Value.absent(),
    this.options = const Value.absent(),
    this.groupId = const Value.absent(),
    this.sourceKey = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       protocol = Value(protocol),
       server = Value(server),
       port = Value(port);
  static Insertable<Node> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? protocol,
    Expression<String>? server,
    Expression<int>? port,
    Expression<bool>? tls,
    Expression<String>? credential,
    Expression<int>? revision,
    Expression<String>? options,
    Expression<String>? groupId,
    Expression<String>? sourceKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (protocol != null) 'protocol': protocol,
      if (server != null) 'server': server,
      if (port != null) 'port': port,
      if (tls != null) 'tls': tls,
      if (credential != null) 'credential': credential,
      if (revision != null) 'revision': revision,
      if (options != null) 'options': options,
      if (groupId != null) 'group_id': groupId,
      if (sourceKey != null) 'source_key': sourceKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? protocol,
    Value<String>? server,
    Value<int>? port,
    Value<bool>? tls,
    Value<String>? credential,
    Value<int>? revision,
    Value<String>? options,
    Value<String?>? groupId,
    Value<String>? sourceKey,
    Value<int>? rowid,
  }) {
    return NodesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      server: server ?? this.server,
      port: port ?? this.port,
      tls: tls ?? this.tls,
      credential: credential ?? this.credential,
      revision: revision ?? this.revision,
      options: options ?? this.options,
      groupId: groupId ?? this.groupId,
      sourceKey: sourceKey ?? this.sourceKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (server.present) {
      map['server'] = Variable<String>(server.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (tls.present) {
      map['tls'] = Variable<bool>(tls.value);
    }
    if (credential.present) {
      map['credential'] = Variable<String>(credential.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (options.present) {
      map['options'] = Variable<String>(options.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (sourceKey.present) {
      map['source_key'] = Variable<String>(sourceKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('protocol: $protocol, ')
          ..write('server: $server, ')
          ..write('port: $port, ')
          ..write('tls: $tls, ')
          ..write('credential: $credential, ')
          ..write('revision: $revision, ')
          ..write('options: $options, ')
          ..write('groupId: $groupId, ')
          ..write('sourceKey: $sourceKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NodeGroupsTable extends NodeGroups
    with TableInfo<$NodeGroupsTable, NodeGroupRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodeGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<bool> customName = GeneratedColumn<bool>(
    'custom_name',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("custom_name" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _urlCipherMeta = const VerificationMeta(
    'urlCipher',
  );
  @override
  late final GeneratedColumn<String> urlCipher = GeneratedColumn<String>(
    'url_cipher',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _urlHashMeta = const VerificationMeta(
    'urlHash',
  );
  @override
  late final GeneratedColumn<String> urlHash = GeneratedColumn<String>(
    'url_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _uploadedMeta = const VerificationMeta(
    'uploaded',
  );
  @override
  late final GeneratedColumn<int> uploaded = GeneratedColumn<int>(
    'uploaded',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _downloadedMeta = const VerificationMeta(
    'downloaded',
  );
  @override
  late final GeneratedColumn<int> downloaded = GeneratedColumn<int>(
    'downloaded',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _totalMeta = const VerificationMeta('total');
  @override
  late final GeneratedColumn<int> total = GeneratedColumn<int>(
    'total',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _expiresAtMeta = const VerificationMeta(
    'expiresAt',
  );
  @override
  late final GeneratedColumn<DateTime> expiresAt = GeneratedColumn<DateTime>(
    'expires_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _attemptedAtMeta = const VerificationMeta(
    'attemptedAt',
  );
  @override
  late final GeneratedColumn<DateTime> attemptedAt = GeneratedColumn<DateTime>(
    'attempted_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updateErrorMeta = const VerificationMeta(
    'updateError',
  );
  @override
  late final GeneratedColumn<String> updateError = GeneratedColumn<String>(
    'update_error',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _skippedNodesMeta = const VerificationMeta(
    'skippedNodes',
  );
  @override
  late final GeneratedColumn<int> skippedNodes = GeneratedColumn<int>(
    'skipped_nodes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _compatibilityIssuesMeta =
      const VerificationMeta('compatibilityIssues');
  @override
  late final GeneratedColumn<String> compatibilityIssues =
      GeneratedColumn<String>(
        'compatibility_issues',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      );
  static const VerificationMeta _autoUpdateMeta = const VerificationMeta(
    'autoUpdate',
  );
  @override
  late final GeneratedColumn<bool> autoUpdate = GeneratedColumn<bool>(
    'auto_update',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("auto_update" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _intervalHoursMeta = const VerificationMeta(
    'intervalHours',
  );
  @override
  late final GeneratedColumn<int> intervalHours = GeneratedColumn<int>(
    'interval_hours',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(24),
  );
  static const VerificationMeta _lastSelectedNodeIdMeta =
      const VerificationMeta('lastSelectedNodeId');
  @override
  late final GeneratedColumn<String> lastSelectedNodeId =
      GeneratedColumn<String>(
        'last_selected_node_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _revisionMeta = const VerificationMeta(
    'revision',
  );
  @override
  late final GeneratedColumn<int> revision = GeneratedColumn<int>(
    'revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    kind,
    customName,
    urlCipher,
    urlHash,
    uploaded,
    downloaded,
    total,
    expiresAt,
    updatedAt,
    attemptedAt,
    updateError,
    skippedNodes,
    compatibilityIssues,
    autoUpdate,
    intervalHours,
    lastSelectedNodeId,
    revision,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'node_groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<NodeGroupRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    if (data.containsKey('url_cipher')) {
      context.handle(
        _urlCipherMeta,
        urlCipher.isAcceptableOrUnknown(data['url_cipher']!, _urlCipherMeta),
      );
    }
    if (data.containsKey('url_hash')) {
      context.handle(
        _urlHashMeta,
        urlHash.isAcceptableOrUnknown(data['url_hash']!, _urlHashMeta),
      );
    }
    if (data.containsKey('uploaded')) {
      context.handle(
        _uploadedMeta,
        uploaded.isAcceptableOrUnknown(data['uploaded']!, _uploadedMeta),
      );
    }
    if (data.containsKey('downloaded')) {
      context.handle(
        _downloadedMeta,
        downloaded.isAcceptableOrUnknown(data['downloaded']!, _downloadedMeta),
      );
    }
    if (data.containsKey('total')) {
      context.handle(
        _totalMeta,
        total.isAcceptableOrUnknown(data['total']!, _totalMeta),
      );
    }
    if (data.containsKey('expires_at')) {
      context.handle(
        _expiresAtMeta,
        expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('attempted_at')) {
      context.handle(
        _attemptedAtMeta,
        attemptedAt.isAcceptableOrUnknown(
          data['attempted_at']!,
          _attemptedAtMeta,
        ),
      );
    }
    if (data.containsKey('update_error')) {
      context.handle(
        _updateErrorMeta,
        updateError.isAcceptableOrUnknown(
          data['update_error']!,
          _updateErrorMeta,
        ),
      );
    }
    if (data.containsKey('skipped_nodes')) {
      context.handle(
        _skippedNodesMeta,
        skippedNodes.isAcceptableOrUnknown(
          data['skipped_nodes']!,
          _skippedNodesMeta,
        ),
      );
    }
    if (data.containsKey('compatibility_issues')) {
      context.handle(
        _compatibilityIssuesMeta,
        compatibilityIssues.isAcceptableOrUnknown(
          data['compatibility_issues']!,
          _compatibilityIssuesMeta,
        ),
      );
    }
    if (data.containsKey('auto_update')) {
      context.handle(
        _autoUpdateMeta,
        autoUpdate.isAcceptableOrUnknown(data['auto_update']!, _autoUpdateMeta),
      );
    }
    if (data.containsKey('interval_hours')) {
      context.handle(
        _intervalHoursMeta,
        intervalHours.isAcceptableOrUnknown(
          data['interval_hours']!,
          _intervalHoursMeta,
        ),
      );
    }
    if (data.containsKey('last_selected_node_id')) {
      context.handle(
        _lastSelectedNodeIdMeta,
        lastSelectedNodeId.isAcceptableOrUnknown(
          data['last_selected_node_id']!,
          _lastSelectedNodeIdMeta,
        ),
      );
    }
    if (data.containsKey('revision')) {
      context.handle(
        _revisionMeta,
        revision.isAcceptableOrUnknown(data['revision']!, _revisionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NodeGroupRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NodeGroupRecord(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      customName:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}custom_name'],
          )!,
      urlCipher:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url_cipher'],
          )!,
      urlHash:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}url_hash'],
          )!,
      uploaded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded'],
      ),
      downloaded: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}downloaded'],
      ),
      total: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}total'],
      ),
      expiresAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}expires_at'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      attemptedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}attempted_at'],
      ),
      updateError:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}update_error'],
          )!,
      skippedNodes:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}skipped_nodes'],
          )!,
      compatibilityIssues:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}compatibility_issues'],
          )!,
      autoUpdate:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}auto_update'],
          )!,
      intervalHours:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}interval_hours'],
          )!,
      lastSelectedNodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_selected_node_id'],
      ),
      revision:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}revision'],
          )!,
    );
  }

  @override
  $NodeGroupsTable createAlias(String alias) {
    return $NodeGroupsTable(attachedDatabase, alias);
  }
}

class NodeGroupRecord extends DataClass implements Insertable<NodeGroupRecord> {
  final String id;
  final String name;
  final String kind;
  final bool customName;
  final String urlCipher;
  final String urlHash;
  final int? uploaded;
  final int? downloaded;
  final int? total;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final DateTime? attemptedAt;
  final String updateError;
  final int skippedNodes;
  final String compatibilityIssues;
  final bool autoUpdate;
  final int intervalHours;
  final String? lastSelectedNodeId;
  final int revision;
  const NodeGroupRecord({
    required this.id,
    required this.name,
    required this.kind,
    required this.customName,
    required this.urlCipher,
    required this.urlHash,
    this.uploaded,
    this.downloaded,
    this.total,
    this.expiresAt,
    this.updatedAt,
    this.attemptedAt,
    required this.updateError,
    required this.skippedNodes,
    required this.compatibilityIssues,
    required this.autoUpdate,
    required this.intervalHours,
    this.lastSelectedNodeId,
    required this.revision,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['kind'] = Variable<String>(kind);
    map['custom_name'] = Variable<bool>(customName);
    map['url_cipher'] = Variable<String>(urlCipher);
    map['url_hash'] = Variable<String>(urlHash);
    if (!nullToAbsent || uploaded != null) {
      map['uploaded'] = Variable<int>(uploaded);
    }
    if (!nullToAbsent || downloaded != null) {
      map['downloaded'] = Variable<int>(downloaded);
    }
    if (!nullToAbsent || total != null) {
      map['total'] = Variable<int>(total);
    }
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<DateTime>(expiresAt);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || attemptedAt != null) {
      map['attempted_at'] = Variable<DateTime>(attemptedAt);
    }
    map['update_error'] = Variable<String>(updateError);
    map['skipped_nodes'] = Variable<int>(skippedNodes);
    map['compatibility_issues'] = Variable<String>(compatibilityIssues);
    map['auto_update'] = Variable<bool>(autoUpdate);
    map['interval_hours'] = Variable<int>(intervalHours);
    if (!nullToAbsent || lastSelectedNodeId != null) {
      map['last_selected_node_id'] = Variable<String>(lastSelectedNodeId);
    }
    map['revision'] = Variable<int>(revision);
    return map;
  }

  NodeGroupsCompanion toCompanion(bool nullToAbsent) {
    return NodeGroupsCompanion(
      id: Value(id),
      name: Value(name),
      kind: Value(kind),
      customName: Value(customName),
      urlCipher: Value(urlCipher),
      urlHash: Value(urlHash),
      uploaded:
          uploaded == null && nullToAbsent
              ? const Value.absent()
              : Value(uploaded),
      downloaded:
          downloaded == null && nullToAbsent
              ? const Value.absent()
              : Value(downloaded),
      total:
          total == null && nullToAbsent ? const Value.absent() : Value(total),
      expiresAt:
          expiresAt == null && nullToAbsent
              ? const Value.absent()
              : Value(expiresAt),
      updatedAt:
          updatedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(updatedAt),
      attemptedAt:
          attemptedAt == null && nullToAbsent
              ? const Value.absent()
              : Value(attemptedAt),
      updateError: Value(updateError),
      skippedNodes: Value(skippedNodes),
      compatibilityIssues: Value(compatibilityIssues),
      autoUpdate: Value(autoUpdate),
      intervalHours: Value(intervalHours),
      lastSelectedNodeId:
          lastSelectedNodeId == null && nullToAbsent
              ? const Value.absent()
              : Value(lastSelectedNodeId),
      revision: Value(revision),
    );
  }

  factory NodeGroupRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NodeGroupRecord(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      kind: serializer.fromJson<String>(json['kind']),
      customName: serializer.fromJson<bool>(json['customName']),
      urlCipher: serializer.fromJson<String>(json['urlCipher']),
      urlHash: serializer.fromJson<String>(json['urlHash']),
      uploaded: serializer.fromJson<int?>(json['uploaded']),
      downloaded: serializer.fromJson<int?>(json['downloaded']),
      total: serializer.fromJson<int?>(json['total']),
      expiresAt: serializer.fromJson<DateTime?>(json['expiresAt']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      attemptedAt: serializer.fromJson<DateTime?>(json['attemptedAt']),
      updateError: serializer.fromJson<String>(json['updateError']),
      skippedNodes: serializer.fromJson<int>(json['skippedNodes']),
      compatibilityIssues: serializer.fromJson<String>(
        json['compatibilityIssues'],
      ),
      autoUpdate: serializer.fromJson<bool>(json['autoUpdate']),
      intervalHours: serializer.fromJson<int>(json['intervalHours']),
      lastSelectedNodeId: serializer.fromJson<String?>(
        json['lastSelectedNodeId'],
      ),
      revision: serializer.fromJson<int>(json['revision']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'kind': serializer.toJson<String>(kind),
      'customName': serializer.toJson<bool>(customName),
      'urlCipher': serializer.toJson<String>(urlCipher),
      'urlHash': serializer.toJson<String>(urlHash),
      'uploaded': serializer.toJson<int?>(uploaded),
      'downloaded': serializer.toJson<int?>(downloaded),
      'total': serializer.toJson<int?>(total),
      'expiresAt': serializer.toJson<DateTime?>(expiresAt),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'attemptedAt': serializer.toJson<DateTime?>(attemptedAt),
      'updateError': serializer.toJson<String>(updateError),
      'skippedNodes': serializer.toJson<int>(skippedNodes),
      'compatibilityIssues': serializer.toJson<String>(compatibilityIssues),
      'autoUpdate': serializer.toJson<bool>(autoUpdate),
      'intervalHours': serializer.toJson<int>(intervalHours),
      'lastSelectedNodeId': serializer.toJson<String?>(lastSelectedNodeId),
      'revision': serializer.toJson<int>(revision),
    };
  }

  NodeGroupRecord copyWith({
    String? id,
    String? name,
    String? kind,
    bool? customName,
    String? urlCipher,
    String? urlHash,
    Value<int?> uploaded = const Value.absent(),
    Value<int?> downloaded = const Value.absent(),
    Value<int?> total = const Value.absent(),
    Value<DateTime?> expiresAt = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<DateTime?> attemptedAt = const Value.absent(),
    String? updateError,
    int? skippedNodes,
    String? compatibilityIssues,
    bool? autoUpdate,
    int? intervalHours,
    Value<String?> lastSelectedNodeId = const Value.absent(),
    int? revision,
  }) => NodeGroupRecord(
    id: id ?? this.id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    customName: customName ?? this.customName,
    urlCipher: urlCipher ?? this.urlCipher,
    urlHash: urlHash ?? this.urlHash,
    uploaded: uploaded.present ? uploaded.value : this.uploaded,
    downloaded: downloaded.present ? downloaded.value : this.downloaded,
    total: total.present ? total.value : this.total,
    expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    attemptedAt: attemptedAt.present ? attemptedAt.value : this.attemptedAt,
    updateError: updateError ?? this.updateError,
    skippedNodes: skippedNodes ?? this.skippedNodes,
    compatibilityIssues: compatibilityIssues ?? this.compatibilityIssues,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    intervalHours: intervalHours ?? this.intervalHours,
    lastSelectedNodeId:
        lastSelectedNodeId.present
            ? lastSelectedNodeId.value
            : this.lastSelectedNodeId,
    revision: revision ?? this.revision,
  );
  NodeGroupRecord copyWithCompanion(NodeGroupsCompanion data) {
    return NodeGroupRecord(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      kind: data.kind.present ? data.kind.value : this.kind,
      customName:
          data.customName.present ? data.customName.value : this.customName,
      urlCipher: data.urlCipher.present ? data.urlCipher.value : this.urlCipher,
      urlHash: data.urlHash.present ? data.urlHash.value : this.urlHash,
      uploaded: data.uploaded.present ? data.uploaded.value : this.uploaded,
      downloaded:
          data.downloaded.present ? data.downloaded.value : this.downloaded,
      total: data.total.present ? data.total.value : this.total,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      attemptedAt:
          data.attemptedAt.present ? data.attemptedAt.value : this.attemptedAt,
      updateError:
          data.updateError.present ? data.updateError.value : this.updateError,
      skippedNodes:
          data.skippedNodes.present
              ? data.skippedNodes.value
              : this.skippedNodes,
      compatibilityIssues:
          data.compatibilityIssues.present
              ? data.compatibilityIssues.value
              : this.compatibilityIssues,
      autoUpdate:
          data.autoUpdate.present ? data.autoUpdate.value : this.autoUpdate,
      intervalHours:
          data.intervalHours.present
              ? data.intervalHours.value
              : this.intervalHours,
      lastSelectedNodeId:
          data.lastSelectedNodeId.present
              ? data.lastSelectedNodeId.value
              : this.lastSelectedNodeId,
      revision: data.revision.present ? data.revision.value : this.revision,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NodeGroupRecord(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('customName: $customName, ')
          ..write('urlCipher: $urlCipher, ')
          ..write('urlHash: $urlHash, ')
          ..write('uploaded: $uploaded, ')
          ..write('downloaded: $downloaded, ')
          ..write('total: $total, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attemptedAt: $attemptedAt, ')
          ..write('updateError: $updateError, ')
          ..write('skippedNodes: $skippedNodes, ')
          ..write('compatibilityIssues: $compatibilityIssues, ')
          ..write('autoUpdate: $autoUpdate, ')
          ..write('intervalHours: $intervalHours, ')
          ..write('lastSelectedNodeId: $lastSelectedNodeId, ')
          ..write('revision: $revision')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    kind,
    customName,
    urlCipher,
    urlHash,
    uploaded,
    downloaded,
    total,
    expiresAt,
    updatedAt,
    attemptedAt,
    updateError,
    skippedNodes,
    compatibilityIssues,
    autoUpdate,
    intervalHours,
    lastSelectedNodeId,
    revision,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeGroupRecord &&
          other.id == this.id &&
          other.name == this.name &&
          other.kind == this.kind &&
          other.customName == this.customName &&
          other.urlCipher == this.urlCipher &&
          other.urlHash == this.urlHash &&
          other.uploaded == this.uploaded &&
          other.downloaded == this.downloaded &&
          other.total == this.total &&
          other.expiresAt == this.expiresAt &&
          other.updatedAt == this.updatedAt &&
          other.attemptedAt == this.attemptedAt &&
          other.updateError == this.updateError &&
          other.skippedNodes == this.skippedNodes &&
          other.compatibilityIssues == this.compatibilityIssues &&
          other.autoUpdate == this.autoUpdate &&
          other.intervalHours == this.intervalHours &&
          other.lastSelectedNodeId == this.lastSelectedNodeId &&
          other.revision == this.revision);
}

class NodeGroupsCompanion extends UpdateCompanion<NodeGroupRecord> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> kind;
  final Value<bool> customName;
  final Value<String> urlCipher;
  final Value<String> urlHash;
  final Value<int?> uploaded;
  final Value<int?> downloaded;
  final Value<int?> total;
  final Value<DateTime?> expiresAt;
  final Value<DateTime?> updatedAt;
  final Value<DateTime?> attemptedAt;
  final Value<String> updateError;
  final Value<int> skippedNodes;
  final Value<String> compatibilityIssues;
  final Value<bool> autoUpdate;
  final Value<int> intervalHours;
  final Value<String?> lastSelectedNodeId;
  final Value<int> revision;
  final Value<int> rowid;
  const NodeGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.kind = const Value.absent(),
    this.customName = const Value.absent(),
    this.urlCipher = const Value.absent(),
    this.urlHash = const Value.absent(),
    this.uploaded = const Value.absent(),
    this.downloaded = const Value.absent(),
    this.total = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attemptedAt = const Value.absent(),
    this.updateError = const Value.absent(),
    this.skippedNodes = const Value.absent(),
    this.compatibilityIssues = const Value.absent(),
    this.autoUpdate = const Value.absent(),
    this.intervalHours = const Value.absent(),
    this.lastSelectedNodeId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodeGroupsCompanion.insert({
    required String id,
    required String name,
    required String kind,
    this.customName = const Value.absent(),
    this.urlCipher = const Value.absent(),
    this.urlHash = const Value.absent(),
    this.uploaded = const Value.absent(),
    this.downloaded = const Value.absent(),
    this.total = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.attemptedAt = const Value.absent(),
    this.updateError = const Value.absent(),
    this.skippedNodes = const Value.absent(),
    this.compatibilityIssues = const Value.absent(),
    this.autoUpdate = const Value.absent(),
    this.intervalHours = const Value.absent(),
    this.lastSelectedNodeId = const Value.absent(),
    this.revision = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       kind = Value(kind);
  static Insertable<NodeGroupRecord> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? kind,
    Expression<bool>? customName,
    Expression<String>? urlCipher,
    Expression<String>? urlHash,
    Expression<int>? uploaded,
    Expression<int>? downloaded,
    Expression<int>? total,
    Expression<DateTime>? expiresAt,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? attemptedAt,
    Expression<String>? updateError,
    Expression<int>? skippedNodes,
    Expression<String>? compatibilityIssues,
    Expression<bool>? autoUpdate,
    Expression<int>? intervalHours,
    Expression<String>? lastSelectedNodeId,
    Expression<int>? revision,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (kind != null) 'kind': kind,
      if (customName != null) 'custom_name': customName,
      if (urlCipher != null) 'url_cipher': urlCipher,
      if (urlHash != null) 'url_hash': urlHash,
      if (uploaded != null) 'uploaded': uploaded,
      if (downloaded != null) 'downloaded': downloaded,
      if (total != null) 'total': total,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (attemptedAt != null) 'attempted_at': attemptedAt,
      if (updateError != null) 'update_error': updateError,
      if (skippedNodes != null) 'skipped_nodes': skippedNodes,
      if (compatibilityIssues != null)
        'compatibility_issues': compatibilityIssues,
      if (autoUpdate != null) 'auto_update': autoUpdate,
      if (intervalHours != null) 'interval_hours': intervalHours,
      if (lastSelectedNodeId != null)
        'last_selected_node_id': lastSelectedNodeId,
      if (revision != null) 'revision': revision,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodeGroupsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? kind,
    Value<bool>? customName,
    Value<String>? urlCipher,
    Value<String>? urlHash,
    Value<int?>? uploaded,
    Value<int?>? downloaded,
    Value<int?>? total,
    Value<DateTime?>? expiresAt,
    Value<DateTime?>? updatedAt,
    Value<DateTime?>? attemptedAt,
    Value<String>? updateError,
    Value<int>? skippedNodes,
    Value<String>? compatibilityIssues,
    Value<bool>? autoUpdate,
    Value<int>? intervalHours,
    Value<String?>? lastSelectedNodeId,
    Value<int>? revision,
    Value<int>? rowid,
  }) {
    return NodeGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      customName: customName ?? this.customName,
      urlCipher: urlCipher ?? this.urlCipher,
      urlHash: urlHash ?? this.urlHash,
      uploaded: uploaded ?? this.uploaded,
      downloaded: downloaded ?? this.downloaded,
      total: total ?? this.total,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      attemptedAt: attemptedAt ?? this.attemptedAt,
      updateError: updateError ?? this.updateError,
      skippedNodes: skippedNodes ?? this.skippedNodes,
      compatibilityIssues: compatibilityIssues ?? this.compatibilityIssues,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      intervalHours: intervalHours ?? this.intervalHours,
      lastSelectedNodeId: lastSelectedNodeId ?? this.lastSelectedNodeId,
      revision: revision ?? this.revision,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<bool>(customName.value);
    }
    if (urlCipher.present) {
      map['url_cipher'] = Variable<String>(urlCipher.value);
    }
    if (urlHash.present) {
      map['url_hash'] = Variable<String>(urlHash.value);
    }
    if (uploaded.present) {
      map['uploaded'] = Variable<int>(uploaded.value);
    }
    if (downloaded.present) {
      map['downloaded'] = Variable<int>(downloaded.value);
    }
    if (total.present) {
      map['total'] = Variable<int>(total.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<DateTime>(expiresAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (attemptedAt.present) {
      map['attempted_at'] = Variable<DateTime>(attemptedAt.value);
    }
    if (updateError.present) {
      map['update_error'] = Variable<String>(updateError.value);
    }
    if (skippedNodes.present) {
      map['skipped_nodes'] = Variable<int>(skippedNodes.value);
    }
    if (compatibilityIssues.present) {
      map['compatibility_issues'] = Variable<String>(compatibilityIssues.value);
    }
    if (autoUpdate.present) {
      map['auto_update'] = Variable<bool>(autoUpdate.value);
    }
    if (intervalHours.present) {
      map['interval_hours'] = Variable<int>(intervalHours.value);
    }
    if (lastSelectedNodeId.present) {
      map['last_selected_node_id'] = Variable<String>(lastSelectedNodeId.value);
    }
    if (revision.present) {
      map['revision'] = Variable<int>(revision.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodeGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('kind: $kind, ')
          ..write('customName: $customName, ')
          ..write('urlCipher: $urlCipher, ')
          ..write('urlHash: $urlHash, ')
          ..write('uploaded: $uploaded, ')
          ..write('downloaded: $downloaded, ')
          ..write('total: $total, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('attemptedAt: $attemptedAt, ')
          ..write('updateError: $updateError, ')
          ..write('skippedNodes: $skippedNodes, ')
          ..write('compatibilityIssues: $compatibilityIssues, ')
          ..write('autoUpdate: $autoUpdate, ')
          ..write('intervalHours: $intervalHours, ')
          ..write('lastSelectedNodeId: $lastSelectedNodeId, ')
          ..write('revision: $revision, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CoreLogsTable extends CoreLogs
    with TableInfo<$CoreLogsTable, CoreLogRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CoreLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<int> at = GeneratedColumn<int>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<String> level = GeneratedColumn<String>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    at,
    sequence,
    level,
    source,
    message,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'core_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<CoreLogRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    } else if (isInserting) {
      context.missing(_levelMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    } else if (isInserting) {
      context.missing(_messageMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CoreLogRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CoreLogRecord(
      id:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      at:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}at'],
          )!,
      sequence:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sequence'],
          )!,
      level:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}level'],
          )!,
      source:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}source'],
          )!,
      message:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}message'],
          )!,
    );
  }

  @override
  $CoreLogsTable createAlias(String alias) {
    return $CoreLogsTable(attachedDatabase, alias);
  }
}

class CoreLogRecord extends DataClass implements Insertable<CoreLogRecord> {
  final String id;
  final int at;
  final int sequence;
  final String level;
  final String source;
  final String message;
  const CoreLogRecord({
    required this.id,
    required this.at,
    required this.sequence,
    required this.level,
    required this.source,
    required this.message,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['at'] = Variable<int>(at);
    map['sequence'] = Variable<int>(sequence);
    map['level'] = Variable<String>(level);
    map['source'] = Variable<String>(source);
    map['message'] = Variable<String>(message);
    return map;
  }

  CoreLogsCompanion toCompanion(bool nullToAbsent) {
    return CoreLogsCompanion(
      id: Value(id),
      at: Value(at),
      sequence: Value(sequence),
      level: Value(level),
      source: Value(source),
      message: Value(message),
    );
  }

  factory CoreLogRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CoreLogRecord(
      id: serializer.fromJson<String>(json['id']),
      at: serializer.fromJson<int>(json['at']),
      sequence: serializer.fromJson<int>(json['sequence']),
      level: serializer.fromJson<String>(json['level']),
      source: serializer.fromJson<String>(json['source']),
      message: serializer.fromJson<String>(json['message']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'at': serializer.toJson<int>(at),
      'sequence': serializer.toJson<int>(sequence),
      'level': serializer.toJson<String>(level),
      'source': serializer.toJson<String>(source),
      'message': serializer.toJson<String>(message),
    };
  }

  CoreLogRecord copyWith({
    String? id,
    int? at,
    int? sequence,
    String? level,
    String? source,
    String? message,
  }) => CoreLogRecord(
    id: id ?? this.id,
    at: at ?? this.at,
    sequence: sequence ?? this.sequence,
    level: level ?? this.level,
    source: source ?? this.source,
    message: message ?? this.message,
  );
  CoreLogRecord copyWithCompanion(CoreLogsCompanion data) {
    return CoreLogRecord(
      id: data.id.present ? data.id.value : this.id,
      at: data.at.present ? data.at.value : this.at,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      level: data.level.present ? data.level.value : this.level,
      source: data.source.present ? data.source.value : this.source,
      message: data.message.present ? data.message.value : this.message,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CoreLogRecord(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('sequence: $sequence, ')
          ..write('level: $level, ')
          ..write('source: $source, ')
          ..write('message: $message')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, at, sequence, level, source, message);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CoreLogRecord &&
          other.id == this.id &&
          other.at == this.at &&
          other.sequence == this.sequence &&
          other.level == this.level &&
          other.source == this.source &&
          other.message == this.message);
}

class CoreLogsCompanion extends UpdateCompanion<CoreLogRecord> {
  final Value<String> id;
  final Value<int> at;
  final Value<int> sequence;
  final Value<String> level;
  final Value<String> source;
  final Value<String> message;
  final Value<int> rowid;
  const CoreLogsCompanion({
    this.id = const Value.absent(),
    this.at = const Value.absent(),
    this.sequence = const Value.absent(),
    this.level = const Value.absent(),
    this.source = const Value.absent(),
    this.message = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CoreLogsCompanion.insert({
    required String id,
    required int at,
    this.sequence = const Value.absent(),
    required String level,
    required String source,
    required String message,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       at = Value(at),
       level = Value(level),
       source = Value(source),
       message = Value(message);
  static Insertable<CoreLogRecord> custom({
    Expression<String>? id,
    Expression<int>? at,
    Expression<int>? sequence,
    Expression<String>? level,
    Expression<String>? source,
    Expression<String>? message,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (at != null) 'at': at,
      if (sequence != null) 'sequence': sequence,
      if (level != null) 'level': level,
      if (source != null) 'source': source,
      if (message != null) 'message': message,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CoreLogsCompanion copyWith({
    Value<String>? id,
    Value<int>? at,
    Value<int>? sequence,
    Value<String>? level,
    Value<String>? source,
    Value<String>? message,
    Value<int>? rowid,
  }) {
    return CoreLogsCompanion(
      id: id ?? this.id,
      at: at ?? this.at,
      sequence: sequence ?? this.sequence,
      level: level ?? this.level,
      source: source ?? this.source,
      message: message ?? this.message,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(at.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (level.present) {
      map['level'] = Variable<String>(level.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CoreLogsCompanion(')
          ..write('id: $id, ')
          ..write('at: $at, ')
          ..write('sequence: $sequence, ')
          ..write('level: $level, ')
          ..write('source: $source, ')
          ..write('message: $message, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NodeOverridesTable extends NodeOverrides
    with TableInfo<$NodeOverridesTable, NodeOverrideRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodeOverridesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _aliasMeta = const VerificationMeta('alias');
  @override
  late final GeneratedColumn<String> alias = GeneratedColumn<String>(
    'alias',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _hiddenMeta = const VerificationMeta('hidden');
  @override
  late final GeneratedColumn<bool> hidden = GeneratedColumn<bool>(
    'hidden',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("hidden" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [nodeId, alias, favorite, hidden];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'node_overrides';
  @override
  VerificationContext validateIntegrity(
    Insertable<NodeOverrideRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('alias')) {
      context.handle(
        _aliasMeta,
        alias.isAcceptableOrUnknown(data['alias']!, _aliasMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('hidden')) {
      context.handle(
        _hiddenMeta,
        hidden.isAcceptableOrUnknown(data['hidden']!, _hiddenMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {nodeId};
  @override
  NodeOverrideRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NodeOverrideRecord(
      nodeId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}node_id'],
          )!,
      alias:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}alias'],
          )!,
      favorite:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}favorite'],
          )!,
      hidden:
          attachedDatabase.typeMapping.read(
            DriftSqlType.bool,
            data['${effectivePrefix}hidden'],
          )!,
    );
  }

  @override
  $NodeOverridesTable createAlias(String alias) {
    return $NodeOverridesTable(attachedDatabase, alias);
  }
}

class NodeOverrideRecord extends DataClass
    implements Insertable<NodeOverrideRecord> {
  final String nodeId;
  final String alias;
  final bool favorite;
  final bool hidden;
  const NodeOverrideRecord({
    required this.nodeId,
    required this.alias,
    required this.favorite,
    required this.hidden,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['node_id'] = Variable<String>(nodeId);
    map['alias'] = Variable<String>(alias);
    map['favorite'] = Variable<bool>(favorite);
    map['hidden'] = Variable<bool>(hidden);
    return map;
  }

  NodeOverridesCompanion toCompanion(bool nullToAbsent) {
    return NodeOverridesCompanion(
      nodeId: Value(nodeId),
      alias: Value(alias),
      favorite: Value(favorite),
      hidden: Value(hidden),
    );
  }

  factory NodeOverrideRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NodeOverrideRecord(
      nodeId: serializer.fromJson<String>(json['nodeId']),
      alias: serializer.fromJson<String>(json['alias']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      hidden: serializer.fromJson<bool>(json['hidden']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'nodeId': serializer.toJson<String>(nodeId),
      'alias': serializer.toJson<String>(alias),
      'favorite': serializer.toJson<bool>(favorite),
      'hidden': serializer.toJson<bool>(hidden),
    };
  }

  NodeOverrideRecord copyWith({
    String? nodeId,
    String? alias,
    bool? favorite,
    bool? hidden,
  }) => NodeOverrideRecord(
    nodeId: nodeId ?? this.nodeId,
    alias: alias ?? this.alias,
    favorite: favorite ?? this.favorite,
    hidden: hidden ?? this.hidden,
  );
  NodeOverrideRecord copyWithCompanion(NodeOverridesCompanion data) {
    return NodeOverrideRecord(
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      alias: data.alias.present ? data.alias.value : this.alias,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      hidden: data.hidden.present ? data.hidden.value : this.hidden,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NodeOverrideRecord(')
          ..write('nodeId: $nodeId, ')
          ..write('alias: $alias, ')
          ..write('favorite: $favorite, ')
          ..write('hidden: $hidden')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(nodeId, alias, favorite, hidden);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NodeOverrideRecord &&
          other.nodeId == this.nodeId &&
          other.alias == this.alias &&
          other.favorite == this.favorite &&
          other.hidden == this.hidden);
}

class NodeOverridesCompanion extends UpdateCompanion<NodeOverrideRecord> {
  final Value<String> nodeId;
  final Value<String> alias;
  final Value<bool> favorite;
  final Value<bool> hidden;
  final Value<int> rowid;
  const NodeOverridesCompanion({
    this.nodeId = const Value.absent(),
    this.alias = const Value.absent(),
    this.favorite = const Value.absent(),
    this.hidden = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodeOverridesCompanion.insert({
    required String nodeId,
    this.alias = const Value.absent(),
    this.favorite = const Value.absent(),
    this.hidden = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : nodeId = Value(nodeId);
  static Insertable<NodeOverrideRecord> custom({
    Expression<String>? nodeId,
    Expression<String>? alias,
    Expression<bool>? favorite,
    Expression<bool>? hidden,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (nodeId != null) 'node_id': nodeId,
      if (alias != null) 'alias': alias,
      if (favorite != null) 'favorite': favorite,
      if (hidden != null) 'hidden': hidden,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodeOverridesCompanion copyWith({
    Value<String>? nodeId,
    Value<String>? alias,
    Value<bool>? favorite,
    Value<bool>? hidden,
    Value<int>? rowid,
  }) {
    return NodeOverridesCompanion(
      nodeId: nodeId ?? this.nodeId,
      alias: alias ?? this.alias,
      favorite: favorite ?? this.favorite,
      hidden: hidden ?? this.hidden,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (alias.present) {
      map['alias'] = Variable<String>(alias.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (hidden.present) {
      map['hidden'] = Variable<bool>(hidden.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodeOverridesCompanion(')
          ..write('nodeId: $nodeId, ')
          ..write('alias: $alias, ')
          ..write('favorite: $favorite, ')
          ..write('hidden: $hidden, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrafficBucketsTable extends TrafficBuckets
    with TableInfo<$TrafficBucketsTable, TrafficBucketRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrafficBucketsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slotMeta = const VerificationMeta('slot');
  @override
  late final GeneratedColumn<int> slot = GeneratedColumn<int>(
    'slot',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadMeta = const VerificationMeta('upload');
  @override
  late final GeneratedColumn<int> upload = GeneratedColumn<int>(
    'upload',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadMeta = const VerificationMeta(
    'download',
  );
  @override
  late final GeneratedColumn<int> download = GeneratedColumn<int>(
    'download',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [day, slot, upload, download];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'traffic_buckets';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrafficBucketRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('slot')) {
      context.handle(
        _slotMeta,
        slot.isAcceptableOrUnknown(data['slot']!, _slotMeta),
      );
    } else if (isInserting) {
      context.missing(_slotMeta);
    }
    if (data.containsKey('upload')) {
      context.handle(
        _uploadMeta,
        upload.isAcceptableOrUnknown(data['upload']!, _uploadMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadMeta);
    }
    if (data.containsKey('download')) {
      context.handle(
        _downloadMeta,
        download.isAcceptableOrUnknown(data['download']!, _downloadMeta),
      );
    } else if (isInserting) {
      context.missing(_downloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day, slot};
  @override
  TrafficBucketRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrafficBucketRecord(
      day:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}day'],
          )!,
      slot:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}slot'],
          )!,
      upload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}upload'],
          )!,
      download:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}download'],
          )!,
    );
  }

  @override
  $TrafficBucketsTable createAlias(String alias) {
    return $TrafficBucketsTable(attachedDatabase, alias);
  }
}

class TrafficBucketRecord extends DataClass
    implements Insertable<TrafficBucketRecord> {
  final String day;
  final int slot;
  final int upload;
  final int download;
  const TrafficBucketRecord({
    required this.day,
    required this.slot,
    required this.upload,
    required this.download,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['slot'] = Variable<int>(slot);
    map['upload'] = Variable<int>(upload);
    map['download'] = Variable<int>(download);
    return map;
  }

  TrafficBucketsCompanion toCompanion(bool nullToAbsent) {
    return TrafficBucketsCompanion(
      day: Value(day),
      slot: Value(slot),
      upload: Value(upload),
      download: Value(download),
    );
  }

  factory TrafficBucketRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrafficBucketRecord(
      day: serializer.fromJson<String>(json['day']),
      slot: serializer.fromJson<int>(json['slot']),
      upload: serializer.fromJson<int>(json['upload']),
      download: serializer.fromJson<int>(json['download']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'slot': serializer.toJson<int>(slot),
      'upload': serializer.toJson<int>(upload),
      'download': serializer.toJson<int>(download),
    };
  }

  TrafficBucketRecord copyWith({
    String? day,
    int? slot,
    int? upload,
    int? download,
  }) => TrafficBucketRecord(
    day: day ?? this.day,
    slot: slot ?? this.slot,
    upload: upload ?? this.upload,
    download: download ?? this.download,
  );
  TrafficBucketRecord copyWithCompanion(TrafficBucketsCompanion data) {
    return TrafficBucketRecord(
      day: data.day.present ? data.day.value : this.day,
      slot: data.slot.present ? data.slot.value : this.slot,
      upload: data.upload.present ? data.upload.value : this.upload,
      download: data.download.present ? data.download.value : this.download,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrafficBucketRecord(')
          ..write('day: $day, ')
          ..write('slot: $slot, ')
          ..write('upload: $upload, ')
          ..write('download: $download')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, slot, upload, download);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrafficBucketRecord &&
          other.day == this.day &&
          other.slot == this.slot &&
          other.upload == this.upload &&
          other.download == this.download);
}

class TrafficBucketsCompanion extends UpdateCompanion<TrafficBucketRecord> {
  final Value<String> day;
  final Value<int> slot;
  final Value<int> upload;
  final Value<int> download;
  final Value<int> rowid;
  const TrafficBucketsCompanion({
    this.day = const Value.absent(),
    this.slot = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrafficBucketsCompanion.insert({
    required String day,
    required int slot,
    required int upload,
    required int download,
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       slot = Value(slot),
       upload = Value(upload),
       download = Value(download);
  static Insertable<TrafficBucketRecord> custom({
    Expression<String>? day,
    Expression<int>? slot,
    Expression<int>? upload,
    Expression<int>? download,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (slot != null) 'slot': slot,
      if (upload != null) 'upload': upload,
      if (download != null) 'download': download,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrafficBucketsCompanion copyWith({
    Value<String>? day,
    Value<int>? slot,
    Value<int>? upload,
    Value<int>? download,
    Value<int>? rowid,
  }) {
    return TrafficBucketsCompanion(
      day: day ?? this.day,
      slot: slot ?? this.slot,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (slot.present) {
      map['slot'] = Variable<int>(slot.value);
    }
    if (upload.present) {
      map['upload'] = Variable<int>(upload.value);
    }
    if (download.present) {
      map['download'] = Variable<int>(download.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrafficBucketsCompanion(')
          ..write('day: $day, ')
          ..write('slot: $slot, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrafficSourcesTable extends TrafficSources
    with TableInfo<$TrafficSourcesTable, TrafficSourceRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrafficSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _dayMeta = const VerificationMeta('day');
  @override
  late final GeneratedColumn<String> day = GeneratedColumn<String>(
    'day',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadMeta = const VerificationMeta('upload');
  @override
  late final GeneratedColumn<int> upload = GeneratedColumn<int>(
    'upload',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadMeta = const VerificationMeta(
    'download',
  );
  @override
  late final GeneratedColumn<int> download = GeneratedColumn<int>(
    'download',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    day,
    targetId,
    kind,
    name,
    upload,
    download,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'traffic_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrafficSourceRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('day')) {
      context.handle(
        _dayMeta,
        day.isAcceptableOrUnknown(data['day']!, _dayMeta),
      );
    } else if (isInserting) {
      context.missing(_dayMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('upload')) {
      context.handle(
        _uploadMeta,
        upload.isAcceptableOrUnknown(data['upload']!, _uploadMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadMeta);
    }
    if (data.containsKey('download')) {
      context.handle(
        _downloadMeta,
        download.isAcceptableOrUnknown(data['download']!, _downloadMeta),
      );
    } else if (isInserting) {
      context.missing(_downloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {day, kind, targetId};
  @override
  TrafficSourceRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrafficSourceRecord(
      day:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}day'],
          )!,
      targetId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}target_id'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      name:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
      upload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}upload'],
          )!,
      download:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}download'],
          )!,
    );
  }

  @override
  $TrafficSourcesTable createAlias(String alias) {
    return $TrafficSourcesTable(attachedDatabase, alias);
  }
}

class TrafficSourceRecord extends DataClass
    implements Insertable<TrafficSourceRecord> {
  final String day;
  final String targetId;
  final String kind;
  final String name;
  final int upload;
  final int download;
  const TrafficSourceRecord({
    required this.day,
    required this.targetId,
    required this.kind,
    required this.name,
    required this.upload,
    required this.download,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['day'] = Variable<String>(day);
    map['target_id'] = Variable<String>(targetId);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['upload'] = Variable<int>(upload);
    map['download'] = Variable<int>(download);
    return map;
  }

  TrafficSourcesCompanion toCompanion(bool nullToAbsent) {
    return TrafficSourcesCompanion(
      day: Value(day),
      targetId: Value(targetId),
      kind: Value(kind),
      name: Value(name),
      upload: Value(upload),
      download: Value(download),
    );
  }

  factory TrafficSourceRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrafficSourceRecord(
      day: serializer.fromJson<String>(json['day']),
      targetId: serializer.fromJson<String>(json['targetId']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      upload: serializer.fromJson<int>(json['upload']),
      download: serializer.fromJson<int>(json['download']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'day': serializer.toJson<String>(day),
      'targetId': serializer.toJson<String>(targetId),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'upload': serializer.toJson<int>(upload),
      'download': serializer.toJson<int>(download),
    };
  }

  TrafficSourceRecord copyWith({
    String? day,
    String? targetId,
    String? kind,
    String? name,
    int? upload,
    int? download,
  }) => TrafficSourceRecord(
    day: day ?? this.day,
    targetId: targetId ?? this.targetId,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    upload: upload ?? this.upload,
    download: download ?? this.download,
  );
  TrafficSourceRecord copyWithCompanion(TrafficSourcesCompanion data) {
    return TrafficSourceRecord(
      day: data.day.present ? data.day.value : this.day,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      upload: data.upload.present ? data.upload.value : this.upload,
      download: data.download.present ? data.download.value : this.download,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrafficSourceRecord(')
          ..write('day: $day, ')
          ..write('targetId: $targetId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('upload: $upload, ')
          ..write('download: $download')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(day, targetId, kind, name, upload, download);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrafficSourceRecord &&
          other.day == this.day &&
          other.targetId == this.targetId &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.upload == this.upload &&
          other.download == this.download);
}

class TrafficSourcesCompanion extends UpdateCompanion<TrafficSourceRecord> {
  final Value<String> day;
  final Value<String> targetId;
  final Value<String> kind;
  final Value<String> name;
  final Value<int> upload;
  final Value<int> download;
  final Value<int> rowid;
  const TrafficSourcesCompanion({
    this.day = const Value.absent(),
    this.targetId = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrafficSourcesCompanion.insert({
    required String day,
    required String targetId,
    required String kind,
    required String name,
    required int upload,
    required int download,
    this.rowid = const Value.absent(),
  }) : day = Value(day),
       targetId = Value(targetId),
       kind = Value(kind),
       name = Value(name),
       upload = Value(upload),
       download = Value(download);
  static Insertable<TrafficSourceRecord> custom({
    Expression<String>? day,
    Expression<String>? targetId,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<int>? upload,
    Expression<int>? download,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (day != null) 'day': day,
      if (targetId != null) 'target_id': targetId,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (upload != null) 'upload': upload,
      if (download != null) 'download': download,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrafficSourcesCompanion copyWith({
    Value<String>? day,
    Value<String>? targetId,
    Value<String>? kind,
    Value<String>? name,
    Value<int>? upload,
    Value<int>? download,
    Value<int>? rowid,
  }) {
    return TrafficSourcesCompanion(
      day: day ?? this.day,
      targetId: targetId ?? this.targetId,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (day.present) {
      map['day'] = Variable<String>(day.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (upload.present) {
      map['upload'] = Variable<int>(upload.value);
    }
    if (download.present) {
      map['download'] = Variable<int>(download.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrafficSourcesCompanion(')
          ..write('day: $day, ')
          ..write('targetId: $targetId, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrafficCheckpointsTable extends TrafficCheckpoints
    with TableInfo<$TrafficCheckpointsTable, TrafficCheckpointRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrafficCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadMeta = const VerificationMeta('upload');
  @override
  late final GeneratedColumn<int> upload = GeneratedColumn<int>(
    'upload',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadMeta = const VerificationMeta(
    'download',
  );
  @override
  late final GeneratedColumn<int> download = GeneratedColumn<int>(
    'download',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<String> epoch = GeneratedColumn<String>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sampledAtMeta = const VerificationMeta(
    'sampledAt',
  );
  @override
  late final GeneratedColumn<int> sampledAt = GeneratedColumn<int>(
    'sampled_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    upload,
    download,
    epoch,
    sampledAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'traffic_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrafficCheckpointRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('upload')) {
      context.handle(
        _uploadMeta,
        upload.isAcceptableOrUnknown(data['upload']!, _uploadMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadMeta);
    }
    if (data.containsKey('download')) {
      context.handle(
        _downloadMeta,
        download.isAcceptableOrUnknown(data['download']!, _downloadMeta),
      );
    } else if (isInserting) {
      context.missing(_downloadMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    }
    if (data.containsKey('sampled_at')) {
      context.handle(
        _sampledAtMeta,
        sampledAt.isAcceptableOrUnknown(data['sampled_at']!, _sampledAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  TrafficCheckpointRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrafficCheckpointRecord(
      sessionId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}session_id'],
          )!,
      upload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}upload'],
          )!,
      download:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}download'],
          )!,
      epoch:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}epoch'],
          )!,
      sampledAt:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}sampled_at'],
          )!,
    );
  }

  @override
  $TrafficCheckpointsTable createAlias(String alias) {
    return $TrafficCheckpointsTable(attachedDatabase, alias);
  }
}

class TrafficCheckpointRecord extends DataClass
    implements Insertable<TrafficCheckpointRecord> {
  final String sessionId;
  final int upload;
  final int download;
  final String epoch;
  final int sampledAt;
  const TrafficCheckpointRecord({
    required this.sessionId,
    required this.upload,
    required this.download,
    required this.epoch,
    required this.sampledAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['upload'] = Variable<int>(upload);
    map['download'] = Variable<int>(download);
    map['epoch'] = Variable<String>(epoch);
    map['sampled_at'] = Variable<int>(sampledAt);
    return map;
  }

  TrafficCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return TrafficCheckpointsCompanion(
      sessionId: Value(sessionId),
      upload: Value(upload),
      download: Value(download),
      epoch: Value(epoch),
      sampledAt: Value(sampledAt),
    );
  }

  factory TrafficCheckpointRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrafficCheckpointRecord(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      upload: serializer.fromJson<int>(json['upload']),
      download: serializer.fromJson<int>(json['download']),
      epoch: serializer.fromJson<String>(json['epoch']),
      sampledAt: serializer.fromJson<int>(json['sampledAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'upload': serializer.toJson<int>(upload),
      'download': serializer.toJson<int>(download),
      'epoch': serializer.toJson<String>(epoch),
      'sampledAt': serializer.toJson<int>(sampledAt),
    };
  }

  TrafficCheckpointRecord copyWith({
    String? sessionId,
    int? upload,
    int? download,
    String? epoch,
    int? sampledAt,
  }) => TrafficCheckpointRecord(
    sessionId: sessionId ?? this.sessionId,
    upload: upload ?? this.upload,
    download: download ?? this.download,
    epoch: epoch ?? this.epoch,
    sampledAt: sampledAt ?? this.sampledAt,
  );
  TrafficCheckpointRecord copyWithCompanion(TrafficCheckpointsCompanion data) {
    return TrafficCheckpointRecord(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      upload: data.upload.present ? data.upload.value : this.upload,
      download: data.download.present ? data.download.value : this.download,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      sampledAt: data.sampledAt.present ? data.sampledAt.value : this.sampledAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrafficCheckpointRecord(')
          ..write('sessionId: $sessionId, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('epoch: $epoch, ')
          ..write('sampledAt: $sampledAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, upload, download, epoch, sampledAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrafficCheckpointRecord &&
          other.sessionId == this.sessionId &&
          other.upload == this.upload &&
          other.download == this.download &&
          other.epoch == this.epoch &&
          other.sampledAt == this.sampledAt);
}

class TrafficCheckpointsCompanion
    extends UpdateCompanion<TrafficCheckpointRecord> {
  final Value<String> sessionId;
  final Value<int> upload;
  final Value<int> download;
  final Value<String> epoch;
  final Value<int> sampledAt;
  final Value<int> rowid;
  const TrafficCheckpointsCompanion({
    this.sessionId = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.epoch = const Value.absent(),
    this.sampledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrafficCheckpointsCompanion.insert({
    required String sessionId,
    required int upload,
    required int download,
    this.epoch = const Value.absent(),
    this.sampledAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       upload = Value(upload),
       download = Value(download);
  static Insertable<TrafficCheckpointRecord> custom({
    Expression<String>? sessionId,
    Expression<int>? upload,
    Expression<int>? download,
    Expression<String>? epoch,
    Expression<int>? sampledAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (upload != null) 'upload': upload,
      if (download != null) 'download': download,
      if (epoch != null) 'epoch': epoch,
      if (sampledAt != null) 'sampled_at': sampledAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrafficCheckpointsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? upload,
    Value<int>? download,
    Value<String>? epoch,
    Value<int>? sampledAt,
    Value<int>? rowid,
  }) {
    return TrafficCheckpointsCompanion(
      sessionId: sessionId ?? this.sessionId,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      epoch: epoch ?? this.epoch,
      sampledAt: sampledAt ?? this.sampledAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (upload.present) {
      map['upload'] = Variable<int>(upload.value);
    }
    if (download.present) {
      map['download'] = Variable<int>(download.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<String>(epoch.value);
    }
    if (sampledAt.present) {
      map['sampled_at'] = Variable<int>(sampledAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrafficCheckpointsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('epoch: $epoch, ')
          ..write('sampledAt: $sampledAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TrafficSourceCheckpointsTable extends TrafficSourceCheckpoints
    with
        TableInfo<
          $TrafficSourceCheckpointsTable,
          TrafficSourceCheckpointRecord
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TrafficSourceCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetIdMeta = const VerificationMeta(
    'targetId',
  );
  @override
  late final GeneratedColumn<String> targetId = GeneratedColumn<String>(
    'target_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _uploadMeta = const VerificationMeta('upload');
  @override
  late final GeneratedColumn<int> upload = GeneratedColumn<int>(
    'upload',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _downloadMeta = const VerificationMeta(
    'download',
  );
  @override
  late final GeneratedColumn<int> download = GeneratedColumn<int>(
    'download',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    kind,
    targetId,
    upload,
    download,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'traffic_source_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<TrafficSourceCheckpointRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target_id')) {
      context.handle(
        _targetIdMeta,
        targetId.isAcceptableOrUnknown(data['target_id']!, _targetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_targetIdMeta);
    }
    if (data.containsKey('upload')) {
      context.handle(
        _uploadMeta,
        upload.isAcceptableOrUnknown(data['upload']!, _uploadMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadMeta);
    }
    if (data.containsKey('download')) {
      context.handle(
        _downloadMeta,
        download.isAcceptableOrUnknown(data['download']!, _downloadMeta),
      );
    } else if (isInserting) {
      context.missing(_downloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, kind, targetId};
  @override
  TrafficSourceCheckpointRecord map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TrafficSourceCheckpointRecord(
      sessionId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}session_id'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      targetId:
          attachedDatabase.typeMapping.read(
            DriftSqlType.string,
            data['${effectivePrefix}target_id'],
          )!,
      upload:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}upload'],
          )!,
      download:
          attachedDatabase.typeMapping.read(
            DriftSqlType.int,
            data['${effectivePrefix}download'],
          )!,
    );
  }

  @override
  $TrafficSourceCheckpointsTable createAlias(String alias) {
    return $TrafficSourceCheckpointsTable(attachedDatabase, alias);
  }
}

class TrafficSourceCheckpointRecord extends DataClass
    implements Insertable<TrafficSourceCheckpointRecord> {
  final String sessionId;
  final String kind;
  final String targetId;
  final int upload;
  final int download;
  const TrafficSourceCheckpointRecord({
    required this.sessionId,
    required this.kind,
    required this.targetId,
    required this.upload,
    required this.download,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['kind'] = Variable<String>(kind);
    map['target_id'] = Variable<String>(targetId);
    map['upload'] = Variable<int>(upload);
    map['download'] = Variable<int>(download);
    return map;
  }

  TrafficSourceCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return TrafficSourceCheckpointsCompanion(
      sessionId: Value(sessionId),
      kind: Value(kind),
      targetId: Value(targetId),
      upload: Value(upload),
      download: Value(download),
    );
  }

  factory TrafficSourceCheckpointRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TrafficSourceCheckpointRecord(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      kind: serializer.fromJson<String>(json['kind']),
      targetId: serializer.fromJson<String>(json['targetId']),
      upload: serializer.fromJson<int>(json['upload']),
      download: serializer.fromJson<int>(json['download']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'kind': serializer.toJson<String>(kind),
      'targetId': serializer.toJson<String>(targetId),
      'upload': serializer.toJson<int>(upload),
      'download': serializer.toJson<int>(download),
    };
  }

  TrafficSourceCheckpointRecord copyWith({
    String? sessionId,
    String? kind,
    String? targetId,
    int? upload,
    int? download,
  }) => TrafficSourceCheckpointRecord(
    sessionId: sessionId ?? this.sessionId,
    kind: kind ?? this.kind,
    targetId: targetId ?? this.targetId,
    upload: upload ?? this.upload,
    download: download ?? this.download,
  );
  TrafficSourceCheckpointRecord copyWithCompanion(
    TrafficSourceCheckpointsCompanion data,
  ) {
    return TrafficSourceCheckpointRecord(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      kind: data.kind.present ? data.kind.value : this.kind,
      targetId: data.targetId.present ? data.targetId.value : this.targetId,
      upload: data.upload.present ? data.upload.value : this.upload,
      download: data.download.present ? data.download.value : this.download,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TrafficSourceCheckpointRecord(')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('upload: $upload, ')
          ..write('download: $download')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, kind, targetId, upload, download);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TrafficSourceCheckpointRecord &&
          other.sessionId == this.sessionId &&
          other.kind == this.kind &&
          other.targetId == this.targetId &&
          other.upload == this.upload &&
          other.download == this.download);
}

class TrafficSourceCheckpointsCompanion
    extends UpdateCompanion<TrafficSourceCheckpointRecord> {
  final Value<String> sessionId;
  final Value<String> kind;
  final Value<String> targetId;
  final Value<int> upload;
  final Value<int> download;
  final Value<int> rowid;
  const TrafficSourceCheckpointsCompanion({
    this.sessionId = const Value.absent(),
    this.kind = const Value.absent(),
    this.targetId = const Value.absent(),
    this.upload = const Value.absent(),
    this.download = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TrafficSourceCheckpointsCompanion.insert({
    required String sessionId,
    required String kind,
    required String targetId,
    required int upload,
    required int download,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       kind = Value(kind),
       targetId = Value(targetId),
       upload = Value(upload),
       download = Value(download);
  static Insertable<TrafficSourceCheckpointRecord> custom({
    Expression<String>? sessionId,
    Expression<String>? kind,
    Expression<String>? targetId,
    Expression<int>? upload,
    Expression<int>? download,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (kind != null) 'kind': kind,
      if (targetId != null) 'target_id': targetId,
      if (upload != null) 'upload': upload,
      if (download != null) 'download': download,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TrafficSourceCheckpointsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? kind,
    Value<String>? targetId,
    Value<int>? upload,
    Value<int>? download,
    Value<int>? rowid,
  }) {
    return TrafficSourceCheckpointsCompanion(
      sessionId: sessionId ?? this.sessionId,
      kind: kind ?? this.kind,
      targetId: targetId ?? this.targetId,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (targetId.present) {
      map['target_id'] = Variable<String>(targetId.value);
    }
    if (upload.present) {
      map['upload'] = Variable<int>(upload.value);
    }
    if (download.present) {
      map['download'] = Variable<int>(download.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TrafficSourceCheckpointsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('kind: $kind, ')
          ..write('targetId: $targetId, ')
          ..write('upload: $upload, ')
          ..write('download: $download, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $PreferencesTable preferences = $PreferencesTable(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $NodeGroupsTable nodeGroups = $NodeGroupsTable(this);
  late final $CoreLogsTable coreLogs = $CoreLogsTable(this);
  late final $NodeOverridesTable nodeOverrides = $NodeOverridesTable(this);
  late final $TrafficBucketsTable trafficBuckets = $TrafficBucketsTable(this);
  late final $TrafficSourcesTable trafficSources = $TrafficSourcesTable(this);
  late final $TrafficCheckpointsTable trafficCheckpoints =
      $TrafficCheckpointsTable(this);
  late final $TrafficSourceCheckpointsTable trafficSourceCheckpoints =
      $TrafficSourceCheckpointsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    preferences,
    nodes,
    nodeGroups,
    coreLogs,
    nodeOverrides,
    trafficBuckets,
    trafficSources,
    trafficCheckpoints,
    trafficSourceCheckpoints,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'nodes',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('node_overrides', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$PreferencesTableCreateCompanionBuilder =
    PreferencesCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$PreferencesTableUpdateCompanionBuilder =
    PreferencesCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$PreferencesTableFilterComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PreferencesTableOrderingComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PreferencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PreferencesTable> {
  $$PreferencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$PreferencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PreferencesTable,
          Preference,
          $$PreferencesTableFilterComposer,
          $$PreferencesTableOrderingComposer,
          $$PreferencesTableAnnotationComposer,
          $$PreferencesTableCreateCompanionBuilder,
          $$PreferencesTableUpdateCompanionBuilder,
          (
            Preference,
            BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
          ),
          Preference,
          PrefetchHooks Function()
        > {
  $$PreferencesTableTableManager(_$AppDatabase db, $PreferencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$PreferencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$PreferencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () =>
                  $$PreferencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => PreferencesCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PreferencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PreferencesTable,
      Preference,
      $$PreferencesTableFilterComposer,
      $$PreferencesTableOrderingComposer,
      $$PreferencesTableAnnotationComposer,
      $$PreferencesTableCreateCompanionBuilder,
      $$PreferencesTableUpdateCompanionBuilder,
      (
        Preference,
        BaseReferences<_$AppDatabase, $PreferencesTable, Preference>,
      ),
      Preference,
      PrefetchHooks Function()
    >;
typedef $$NodesTableCreateCompanionBuilder =
    NodesCompanion Function({
      required String id,
      required String name,
      required String protocol,
      required String server,
      required int port,
      Value<bool> tls,
      Value<String> credential,
      Value<int> revision,
      Value<String> options,
      Value<String?> groupId,
      Value<String> sourceKey,
      Value<int> rowid,
    });
typedef $$NodesTableUpdateCompanionBuilder =
    NodesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> protocol,
      Value<String> server,
      Value<int> port,
      Value<bool> tls,
      Value<String> credential,
      Value<int> revision,
      Value<String> options,
      Value<String?> groupId,
      Value<String> sourceKey,
      Value<int> rowid,
    });

final class $$NodesTableReferences
    extends BaseReferences<_$AppDatabase, $NodesTable, Node> {
  $$NodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$NodeOverridesTable, List<NodeOverrideRecord>>
  _nodeOverridesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.nodeOverrides,
    aliasName: $_aliasNameGenerator(db.nodes.id, db.nodeOverrides.nodeId),
  );

  $$NodeOverridesTableProcessedTableManager get nodeOverridesRefs {
    final manager = $$NodeOverridesTableTableManager(
      $_db,
      $_db.nodeOverrides,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_nodeOverridesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NodesTableFilterComposer extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get tls => $composableBuilder(
    column: $table.tls,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get options => $composableBuilder(
    column: $table.options,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> nodeOverridesRefs(
    Expression<bool> Function($$NodeOverridesTableFilterComposer f) f,
  ) {
    final $$NodeOverridesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.nodeOverrides,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodeOverridesTableFilterComposer(
            $db: $db,
            $table: $db.nodeOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableOrderingComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get server => $composableBuilder(
    column: $table.server,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get tls => $composableBuilder(
    column: $table.tls,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get options => $composableBuilder(
    column: $table.options,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKey => $composableBuilder(
    column: $table.sourceKey,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get server =>
      $composableBuilder(column: $table.server, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<bool> get tls =>
      $composableBuilder(column: $table.tls, builder: (column) => column);

  GeneratedColumn<String> get credential => $composableBuilder(
    column: $table.credential,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);

  GeneratedColumn<String> get options =>
      $composableBuilder(column: $table.options, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get sourceKey =>
      $composableBuilder(column: $table.sourceKey, builder: (column) => column);

  Expression<T> nodeOverridesRefs<T extends Object>(
    Expression<T> Function($$NodeOverridesTableAnnotationComposer a) f,
  ) {
    final $$NodeOverridesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.nodeOverrides,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodeOverridesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodeOverrides,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodesTable,
          Node,
          $$NodesTableFilterComposer,
          $$NodesTableOrderingComposer,
          $$NodesTableAnnotationComposer,
          $$NodesTableCreateCompanionBuilder,
          $$NodesTableUpdateCompanionBuilder,
          (Node, $$NodesTableReferences),
          Node,
          PrefetchHooks Function({bool nodeOverridesRefs})
        > {
  $$NodesTableTableManager(_$AppDatabase db, $NodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> protocol = const Value.absent(),
                Value<String> server = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<bool> tls = const Value.absent(),
                Value<String> credential = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> options = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion(
                id: id,
                name: name,
                protocol: protocol,
                server: server,
                port: port,
                tls: tls,
                credential: credential,
                revision: revision,
                options: options,
                groupId: groupId,
                sourceKey: sourceKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String protocol,
                required String server,
                required int port,
                Value<bool> tls = const Value.absent(),
                Value<String> credential = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<String> options = const Value.absent(),
                Value<String?> groupId = const Value.absent(),
                Value<String> sourceKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion.insert(
                id: id,
                name: name,
                protocol: protocol,
                server: server,
                port: port,
                tls: tls,
                credential: credential,
                revision: revision,
                options: options,
                groupId: groupId,
                sourceKey: sourceKey,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NodesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({nodeOverridesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (nodeOverridesRefs) db.nodeOverrides,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (nodeOverridesRefs)
                    await $_getPrefetchedData(
                      currentTable: table,
                      referencedTable: $$NodesTableReferences
                          ._nodeOverridesRefsTable(db),
                      managerFromTypedResult:
                          (p0) =>
                              $$NodesTableReferences(
                                db,
                                table,
                                p0,
                              ).nodeOverridesRefs,
                      referencedItemsForCurrentItem:
                          (item, referencedItems) =>
                              referencedItems.where((e) => e.nodeId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodesTable,
      Node,
      $$NodesTableFilterComposer,
      $$NodesTableOrderingComposer,
      $$NodesTableAnnotationComposer,
      $$NodesTableCreateCompanionBuilder,
      $$NodesTableUpdateCompanionBuilder,
      (Node, $$NodesTableReferences),
      Node,
      PrefetchHooks Function({bool nodeOverridesRefs})
    >;
typedef $$NodeGroupsTableCreateCompanionBuilder =
    NodeGroupsCompanion Function({
      required String id,
      required String name,
      required String kind,
      Value<bool> customName,
      Value<String> urlCipher,
      Value<String> urlHash,
      Value<int?> uploaded,
      Value<int?> downloaded,
      Value<int?> total,
      Value<DateTime?> expiresAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> attemptedAt,
      Value<String> updateError,
      Value<int> skippedNodes,
      Value<String> compatibilityIssues,
      Value<bool> autoUpdate,
      Value<int> intervalHours,
      Value<String?> lastSelectedNodeId,
      Value<int> revision,
      Value<int> rowid,
    });
typedef $$NodeGroupsTableUpdateCompanionBuilder =
    NodeGroupsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> kind,
      Value<bool> customName,
      Value<String> urlCipher,
      Value<String> urlHash,
      Value<int?> uploaded,
      Value<int?> downloaded,
      Value<int?> total,
      Value<DateTime?> expiresAt,
      Value<DateTime?> updatedAt,
      Value<DateTime?> attemptedAt,
      Value<String> updateError,
      Value<int> skippedNodes,
      Value<String> compatibilityIssues,
      Value<bool> autoUpdate,
      Value<int> intervalHours,
      Value<String?> lastSelectedNodeId,
      Value<int> revision,
      Value<int> rowid,
    });

class $$NodeGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $NodeGroupsTable> {
  $$NodeGroupsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlCipher => $composableBuilder(
    column: $table.urlCipher,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get urlHash => $composableBuilder(
    column: $table.urlHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploaded => $composableBuilder(
    column: $table.uploaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get downloaded => $composableBuilder(
    column: $table.downloaded,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get updateError => $composableBuilder(
    column: $table.updateError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get skippedNodes => $composableBuilder(
    column: $table.skippedNodes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get compatibilityIssues => $composableBuilder(
    column: $table.compatibilityIssues,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoUpdate => $composableBuilder(
    column: $table.autoUpdate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSelectedNodeId => $composableBuilder(
    column: $table.lastSelectedNodeId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnFilters(column),
  );
}

class $$NodeGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $NodeGroupsTable> {
  $$NodeGroupsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlCipher => $composableBuilder(
    column: $table.urlCipher,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get urlHash => $composableBuilder(
    column: $table.urlHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploaded => $composableBuilder(
    column: $table.uploaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get downloaded => $composableBuilder(
    column: $table.downloaded,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get total => $composableBuilder(
    column: $table.total,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get expiresAt => $composableBuilder(
    column: $table.expiresAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get updateError => $composableBuilder(
    column: $table.updateError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get skippedNodes => $composableBuilder(
    column: $table.skippedNodes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get compatibilityIssues => $composableBuilder(
    column: $table.compatibilityIssues,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoUpdate => $composableBuilder(
    column: $table.autoUpdate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSelectedNodeId => $composableBuilder(
    column: $table.lastSelectedNodeId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revision => $composableBuilder(
    column: $table.revision,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodeGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodeGroupsTable> {
  $$NodeGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<bool> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get urlCipher =>
      $composableBuilder(column: $table.urlCipher, builder: (column) => column);

  GeneratedColumn<String> get urlHash =>
      $composableBuilder(column: $table.urlHash, builder: (column) => column);

  GeneratedColumn<int> get uploaded =>
      $composableBuilder(column: $table.uploaded, builder: (column) => column);

  GeneratedColumn<int> get downloaded => $composableBuilder(
    column: $table.downloaded,
    builder: (column) => column,
  );

  GeneratedColumn<int> get total =>
      $composableBuilder(column: $table.total, builder: (column) => column);

  GeneratedColumn<DateTime> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get attemptedAt => $composableBuilder(
    column: $table.attemptedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get updateError => $composableBuilder(
    column: $table.updateError,
    builder: (column) => column,
  );

  GeneratedColumn<int> get skippedNodes => $composableBuilder(
    column: $table.skippedNodes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get compatibilityIssues => $composableBuilder(
    column: $table.compatibilityIssues,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoUpdate => $composableBuilder(
    column: $table.autoUpdate,
    builder: (column) => column,
  );

  GeneratedColumn<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastSelectedNodeId => $composableBuilder(
    column: $table.lastSelectedNodeId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revision =>
      $composableBuilder(column: $table.revision, builder: (column) => column);
}

class $$NodeGroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodeGroupsTable,
          NodeGroupRecord,
          $$NodeGroupsTableFilterComposer,
          $$NodeGroupsTableOrderingComposer,
          $$NodeGroupsTableAnnotationComposer,
          $$NodeGroupsTableCreateCompanionBuilder,
          $$NodeGroupsTableUpdateCompanionBuilder,
          (
            NodeGroupRecord,
            BaseReferences<_$AppDatabase, $NodeGroupsTable, NodeGroupRecord>,
          ),
          NodeGroupRecord,
          PrefetchHooks Function()
        > {
  $$NodeGroupsTableTableManager(_$AppDatabase db, $NodeGroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NodeGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$NodeGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NodeGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<bool> customName = const Value.absent(),
                Value<String> urlCipher = const Value.absent(),
                Value<String> urlHash = const Value.absent(),
                Value<int?> uploaded = const Value.absent(),
                Value<int?> downloaded = const Value.absent(),
                Value<int?> total = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> attemptedAt = const Value.absent(),
                Value<String> updateError = const Value.absent(),
                Value<int> skippedNodes = const Value.absent(),
                Value<String> compatibilityIssues = const Value.absent(),
                Value<bool> autoUpdate = const Value.absent(),
                Value<int> intervalHours = const Value.absent(),
                Value<String?> lastSelectedNodeId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeGroupsCompanion(
                id: id,
                name: name,
                kind: kind,
                customName: customName,
                urlCipher: urlCipher,
                urlHash: urlHash,
                uploaded: uploaded,
                downloaded: downloaded,
                total: total,
                expiresAt: expiresAt,
                updatedAt: updatedAt,
                attemptedAt: attemptedAt,
                updateError: updateError,
                skippedNodes: skippedNodes,
                compatibilityIssues: compatibilityIssues,
                autoUpdate: autoUpdate,
                intervalHours: intervalHours,
                lastSelectedNodeId: lastSelectedNodeId,
                revision: revision,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String kind,
                Value<bool> customName = const Value.absent(),
                Value<String> urlCipher = const Value.absent(),
                Value<String> urlHash = const Value.absent(),
                Value<int?> uploaded = const Value.absent(),
                Value<int?> downloaded = const Value.absent(),
                Value<int?> total = const Value.absent(),
                Value<DateTime?> expiresAt = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> attemptedAt = const Value.absent(),
                Value<String> updateError = const Value.absent(),
                Value<int> skippedNodes = const Value.absent(),
                Value<String> compatibilityIssues = const Value.absent(),
                Value<bool> autoUpdate = const Value.absent(),
                Value<int> intervalHours = const Value.absent(),
                Value<String?> lastSelectedNodeId = const Value.absent(),
                Value<int> revision = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeGroupsCompanion.insert(
                id: id,
                name: name,
                kind: kind,
                customName: customName,
                urlCipher: urlCipher,
                urlHash: urlHash,
                uploaded: uploaded,
                downloaded: downloaded,
                total: total,
                expiresAt: expiresAt,
                updatedAt: updatedAt,
                attemptedAt: attemptedAt,
                updateError: updateError,
                skippedNodes: skippedNodes,
                compatibilityIssues: compatibilityIssues,
                autoUpdate: autoUpdate,
                intervalHours: intervalHours,
                lastSelectedNodeId: lastSelectedNodeId,
                revision: revision,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$NodeGroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodeGroupsTable,
      NodeGroupRecord,
      $$NodeGroupsTableFilterComposer,
      $$NodeGroupsTableOrderingComposer,
      $$NodeGroupsTableAnnotationComposer,
      $$NodeGroupsTableCreateCompanionBuilder,
      $$NodeGroupsTableUpdateCompanionBuilder,
      (
        NodeGroupRecord,
        BaseReferences<_$AppDatabase, $NodeGroupsTable, NodeGroupRecord>,
      ),
      NodeGroupRecord,
      PrefetchHooks Function()
    >;
typedef $$CoreLogsTableCreateCompanionBuilder =
    CoreLogsCompanion Function({
      required String id,
      required int at,
      Value<int> sequence,
      required String level,
      required String source,
      required String message,
      Value<int> rowid,
    });
typedef $$CoreLogsTableUpdateCompanionBuilder =
    CoreLogsCompanion Function({
      Value<String> id,
      Value<int> at,
      Value<int> sequence,
      Value<String> level,
      Value<String> source,
      Value<String> message,
      Value<int> rowid,
    });

class $$CoreLogsTableFilterComposer
    extends Composer<_$AppDatabase, $CoreLogsTable> {
  $$CoreLogsTableFilterComposer({
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

  ColumnFilters<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CoreLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $CoreLogsTable> {
  $$CoreLogsTableOrderingComposer({
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

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CoreLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CoreLogsTable> {
  $$CoreLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);
}

class $$CoreLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CoreLogsTable,
          CoreLogRecord,
          $$CoreLogsTableFilterComposer,
          $$CoreLogsTableOrderingComposer,
          $$CoreLogsTableAnnotationComposer,
          $$CoreLogsTableCreateCompanionBuilder,
          $$CoreLogsTableUpdateCompanionBuilder,
          (
            CoreLogRecord,
            BaseReferences<_$AppDatabase, $CoreLogsTable, CoreLogRecord>,
          ),
          CoreLogRecord,
          PrefetchHooks Function()
        > {
  $$CoreLogsTableTableManager(_$AppDatabase db, $CoreLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$CoreLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => $$CoreLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$CoreLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> at = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> level = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CoreLogsCompanion(
                id: id,
                at: at,
                sequence: sequence,
                level: level,
                source: source,
                message: message,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int at,
                Value<int> sequence = const Value.absent(),
                required String level,
                required String source,
                required String message,
                Value<int> rowid = const Value.absent(),
              }) => CoreLogsCompanion.insert(
                id: id,
                at: at,
                sequence: sequence,
                level: level,
                source: source,
                message: message,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CoreLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CoreLogsTable,
      CoreLogRecord,
      $$CoreLogsTableFilterComposer,
      $$CoreLogsTableOrderingComposer,
      $$CoreLogsTableAnnotationComposer,
      $$CoreLogsTableCreateCompanionBuilder,
      $$CoreLogsTableUpdateCompanionBuilder,
      (
        CoreLogRecord,
        BaseReferences<_$AppDatabase, $CoreLogsTable, CoreLogRecord>,
      ),
      CoreLogRecord,
      PrefetchHooks Function()
    >;
typedef $$NodeOverridesTableCreateCompanionBuilder =
    NodeOverridesCompanion Function({
      required String nodeId,
      Value<String> alias,
      Value<bool> favorite,
      Value<bool> hidden,
      Value<int> rowid,
    });
typedef $$NodeOverridesTableUpdateCompanionBuilder =
    NodeOverridesCompanion Function({
      Value<String> nodeId,
      Value<String> alias,
      Value<bool> favorite,
      Value<bool> hidden,
      Value<int> rowid,
    });

final class $$NodeOverridesTableReferences
    extends
        BaseReferences<_$AppDatabase, $NodeOverridesTable, NodeOverrideRecord> {
  $$NodeOverridesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NodesTable _nodeIdTable(_$AppDatabase db) => db.nodes.createAlias(
    $_aliasNameGenerator(db.nodeOverrides.nodeId, db.nodes.id),
  );

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<String>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$NodeOverridesTableFilterComposer
    extends Composer<_$AppDatabase, $NodeOverridesTable> {
  $$NodeOverridesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnFilters(column),
  );

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NodeOverridesTableOrderingComposer
    extends Composer<_$AppDatabase, $NodeOverridesTable> {
  $$NodeOverridesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get alias => $composableBuilder(
    column: $table.alias,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hidden => $composableBuilder(
    column: $table.hidden,
    builder: (column) => ColumnOrderings(column),
  );

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NodeOverridesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodeOverridesTable> {
  $$NodeOverridesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get alias =>
      $composableBuilder(column: $table.alias, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<bool> get hidden =>
      $composableBuilder(column: $table.hidden, builder: (column) => column);

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$NodeOverridesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodeOverridesTable,
          NodeOverrideRecord,
          $$NodeOverridesTableFilterComposer,
          $$NodeOverridesTableOrderingComposer,
          $$NodeOverridesTableAnnotationComposer,
          $$NodeOverridesTableCreateCompanionBuilder,
          $$NodeOverridesTableUpdateCompanionBuilder,
          (NodeOverrideRecord, $$NodeOverridesTableReferences),
          NodeOverrideRecord,
          PrefetchHooks Function({bool nodeId})
        > {
  $$NodeOverridesTableTableManager(_$AppDatabase db, $NodeOverridesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$NodeOverridesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$NodeOverridesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$NodeOverridesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> nodeId = const Value.absent(),
                Value<String> alias = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeOverridesCompanion(
                nodeId: nodeId,
                alias: alias,
                favorite: favorite,
                hidden: hidden,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String nodeId,
                Value<String> alias = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<bool> hidden = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodeOverridesCompanion.insert(
                nodeId: nodeId,
                alias: alias,
                favorite: favorite,
                hidden: hidden,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          $$NodeOverridesTableReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: ({nodeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                T extends TableManagerState<
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic,
                  dynamic
                >
              >(state) {
                if (nodeId) {
                  state =
                      state.withJoin(
                            currentTable: table,
                            currentColumn: table.nodeId,
                            referencedTable: $$NodeOverridesTableReferences
                                ._nodeIdTable(db),
                            referencedColumn:
                                $$NodeOverridesTableReferences
                                    ._nodeIdTable(db)
                                    .id,
                          )
                          as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$NodeOverridesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodeOverridesTable,
      NodeOverrideRecord,
      $$NodeOverridesTableFilterComposer,
      $$NodeOverridesTableOrderingComposer,
      $$NodeOverridesTableAnnotationComposer,
      $$NodeOverridesTableCreateCompanionBuilder,
      $$NodeOverridesTableUpdateCompanionBuilder,
      (NodeOverrideRecord, $$NodeOverridesTableReferences),
      NodeOverrideRecord,
      PrefetchHooks Function({bool nodeId})
    >;
typedef $$TrafficBucketsTableCreateCompanionBuilder =
    TrafficBucketsCompanion Function({
      required String day,
      required int slot,
      required int upload,
      required int download,
      Value<int> rowid,
    });
typedef $$TrafficBucketsTableUpdateCompanionBuilder =
    TrafficBucketsCompanion Function({
      Value<String> day,
      Value<int> slot,
      Value<int> upload,
      Value<int> download,
      Value<int> rowid,
    });

class $$TrafficBucketsTableFilterComposer
    extends Composer<_$AppDatabase, $TrafficBucketsTable> {
  $$TrafficBucketsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrafficBucketsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrafficBucketsTable> {
  $$TrafficBucketsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get slot => $composableBuilder(
    column: $table.slot,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrafficBucketsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrafficBucketsTable> {
  $$TrafficBucketsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<int> get slot =>
      $composableBuilder(column: $table.slot, builder: (column) => column);

  GeneratedColumn<int> get upload =>
      $composableBuilder(column: $table.upload, builder: (column) => column);

  GeneratedColumn<int> get download =>
      $composableBuilder(column: $table.download, builder: (column) => column);
}

class $$TrafficBucketsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrafficBucketsTable,
          TrafficBucketRecord,
          $$TrafficBucketsTableFilterComposer,
          $$TrafficBucketsTableOrderingComposer,
          $$TrafficBucketsTableAnnotationComposer,
          $$TrafficBucketsTableCreateCompanionBuilder,
          $$TrafficBucketsTableUpdateCompanionBuilder,
          (
            TrafficBucketRecord,
            BaseReferences<
              _$AppDatabase,
              $TrafficBucketsTable,
              TrafficBucketRecord
            >,
          ),
          TrafficBucketRecord,
          PrefetchHooks Function()
        > {
  $$TrafficBucketsTableTableManager(
    _$AppDatabase db,
    $TrafficBucketsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TrafficBucketsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$TrafficBucketsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TrafficBucketsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<int> slot = const Value.absent(),
                Value<int> upload = const Value.absent(),
                Value<int> download = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrafficBucketsCompanion(
                day: day,
                slot: slot,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                required int slot,
                required int upload,
                required int download,
                Value<int> rowid = const Value.absent(),
              }) => TrafficBucketsCompanion.insert(
                day: day,
                slot: slot,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrafficBucketsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrafficBucketsTable,
      TrafficBucketRecord,
      $$TrafficBucketsTableFilterComposer,
      $$TrafficBucketsTableOrderingComposer,
      $$TrafficBucketsTableAnnotationComposer,
      $$TrafficBucketsTableCreateCompanionBuilder,
      $$TrafficBucketsTableUpdateCompanionBuilder,
      (
        TrafficBucketRecord,
        BaseReferences<
          _$AppDatabase,
          $TrafficBucketsTable,
          TrafficBucketRecord
        >,
      ),
      TrafficBucketRecord,
      PrefetchHooks Function()
    >;
typedef $$TrafficSourcesTableCreateCompanionBuilder =
    TrafficSourcesCompanion Function({
      required String day,
      required String targetId,
      required String kind,
      required String name,
      required int upload,
      required int download,
      Value<int> rowid,
    });
typedef $$TrafficSourcesTableUpdateCompanionBuilder =
    TrafficSourcesCompanion Function({
      Value<String> day,
      Value<String> targetId,
      Value<String> kind,
      Value<String> name,
      Value<int> upload,
      Value<int> download,
      Value<int> rowid,
    });

class $$TrafficSourcesTableFilterComposer
    extends Composer<_$AppDatabase, $TrafficSourcesTable> {
  $$TrafficSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrafficSourcesTableOrderingComposer
    extends Composer<_$AppDatabase, $TrafficSourcesTable> {
  $$TrafficSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get day => $composableBuilder(
    column: $table.day,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrafficSourcesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrafficSourcesTable> {
  $$TrafficSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get day =>
      $composableBuilder(column: $table.day, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get upload =>
      $composableBuilder(column: $table.upload, builder: (column) => column);

  GeneratedColumn<int> get download =>
      $composableBuilder(column: $table.download, builder: (column) => column);
}

class $$TrafficSourcesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrafficSourcesTable,
          TrafficSourceRecord,
          $$TrafficSourcesTableFilterComposer,
          $$TrafficSourcesTableOrderingComposer,
          $$TrafficSourcesTableAnnotationComposer,
          $$TrafficSourcesTableCreateCompanionBuilder,
          $$TrafficSourcesTableUpdateCompanionBuilder,
          (
            TrafficSourceRecord,
            BaseReferences<
              _$AppDatabase,
              $TrafficSourcesTable,
              TrafficSourceRecord
            >,
          ),
          TrafficSourceRecord,
          PrefetchHooks Function()
        > {
  $$TrafficSourcesTableTableManager(
    _$AppDatabase db,
    $TrafficSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TrafficSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  $$TrafficSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => $$TrafficSourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> day = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> upload = const Value.absent(),
                Value<int> download = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrafficSourcesCompanion(
                day: day,
                targetId: targetId,
                kind: kind,
                name: name,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String day,
                required String targetId,
                required String kind,
                required String name,
                required int upload,
                required int download,
                Value<int> rowid = const Value.absent(),
              }) => TrafficSourcesCompanion.insert(
                day: day,
                targetId: targetId,
                kind: kind,
                name: name,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrafficSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrafficSourcesTable,
      TrafficSourceRecord,
      $$TrafficSourcesTableFilterComposer,
      $$TrafficSourcesTableOrderingComposer,
      $$TrafficSourcesTableAnnotationComposer,
      $$TrafficSourcesTableCreateCompanionBuilder,
      $$TrafficSourcesTableUpdateCompanionBuilder,
      (
        TrafficSourceRecord,
        BaseReferences<
          _$AppDatabase,
          $TrafficSourcesTable,
          TrafficSourceRecord
        >,
      ),
      TrafficSourceRecord,
      PrefetchHooks Function()
    >;
typedef $$TrafficCheckpointsTableCreateCompanionBuilder =
    TrafficCheckpointsCompanion Function({
      required String sessionId,
      required int upload,
      required int download,
      Value<String> epoch,
      Value<int> sampledAt,
      Value<int> rowid,
    });
typedef $$TrafficCheckpointsTableUpdateCompanionBuilder =
    TrafficCheckpointsCompanion Function({
      Value<String> sessionId,
      Value<int> upload,
      Value<int> download,
      Value<String> epoch,
      Value<int> sampledAt,
      Value<int> rowid,
    });

class $$TrafficCheckpointsTableFilterComposer
    extends Composer<_$AppDatabase, $TrafficCheckpointsTable> {
  $$TrafficCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampledAt => $composableBuilder(
    column: $table.sampledAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrafficCheckpointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrafficCheckpointsTable> {
  $$TrafficCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampledAt => $composableBuilder(
    column: $table.sampledAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrafficCheckpointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrafficCheckpointsTable> {
  $$TrafficCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get upload =>
      $composableBuilder(column: $table.upload, builder: (column) => column);

  GeneratedColumn<int> get download =>
      $composableBuilder(column: $table.download, builder: (column) => column);

  GeneratedColumn<String> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<int> get sampledAt =>
      $composableBuilder(column: $table.sampledAt, builder: (column) => column);
}

class $$TrafficCheckpointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrafficCheckpointsTable,
          TrafficCheckpointRecord,
          $$TrafficCheckpointsTableFilterComposer,
          $$TrafficCheckpointsTableOrderingComposer,
          $$TrafficCheckpointsTableAnnotationComposer,
          $$TrafficCheckpointsTableCreateCompanionBuilder,
          $$TrafficCheckpointsTableUpdateCompanionBuilder,
          (
            TrafficCheckpointRecord,
            BaseReferences<
              _$AppDatabase,
              $TrafficCheckpointsTable,
              TrafficCheckpointRecord
            >,
          ),
          TrafficCheckpointRecord,
          PrefetchHooks Function()
        > {
  $$TrafficCheckpointsTableTableManager(
    _$AppDatabase db,
    $TrafficCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TrafficCheckpointsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$TrafficCheckpointsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$TrafficCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> upload = const Value.absent(),
                Value<int> download = const Value.absent(),
                Value<String> epoch = const Value.absent(),
                Value<int> sampledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrafficCheckpointsCompanion(
                sessionId: sessionId,
                upload: upload,
                download: download,
                epoch: epoch,
                sampledAt: sampledAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required int upload,
                required int download,
                Value<String> epoch = const Value.absent(),
                Value<int> sampledAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrafficCheckpointsCompanion.insert(
                sessionId: sessionId,
                upload: upload,
                download: download,
                epoch: epoch,
                sampledAt: sampledAt,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrafficCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrafficCheckpointsTable,
      TrafficCheckpointRecord,
      $$TrafficCheckpointsTableFilterComposer,
      $$TrafficCheckpointsTableOrderingComposer,
      $$TrafficCheckpointsTableAnnotationComposer,
      $$TrafficCheckpointsTableCreateCompanionBuilder,
      $$TrafficCheckpointsTableUpdateCompanionBuilder,
      (
        TrafficCheckpointRecord,
        BaseReferences<
          _$AppDatabase,
          $TrafficCheckpointsTable,
          TrafficCheckpointRecord
        >,
      ),
      TrafficCheckpointRecord,
      PrefetchHooks Function()
    >;
typedef $$TrafficSourceCheckpointsTableCreateCompanionBuilder =
    TrafficSourceCheckpointsCompanion Function({
      required String sessionId,
      required String kind,
      required String targetId,
      required int upload,
      required int download,
      Value<int> rowid,
    });
typedef $$TrafficSourceCheckpointsTableUpdateCompanionBuilder =
    TrafficSourceCheckpointsCompanion Function({
      Value<String> sessionId,
      Value<String> kind,
      Value<String> targetId,
      Value<int> upload,
      Value<int> download,
      Value<int> rowid,
    });

class $$TrafficSourceCheckpointsTableFilterComposer
    extends Composer<_$AppDatabase, $TrafficSourceCheckpointsTable> {
  $$TrafficSourceCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TrafficSourceCheckpointsTableOrderingComposer
    extends Composer<_$AppDatabase, $TrafficSourceCheckpointsTable> {
  $$TrafficSourceCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetId => $composableBuilder(
    column: $table.targetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get upload => $composableBuilder(
    column: $table.upload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get download => $composableBuilder(
    column: $table.download,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TrafficSourceCheckpointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TrafficSourceCheckpointsTable> {
  $$TrafficSourceCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get targetId =>
      $composableBuilder(column: $table.targetId, builder: (column) => column);

  GeneratedColumn<int> get upload =>
      $composableBuilder(column: $table.upload, builder: (column) => column);

  GeneratedColumn<int> get download =>
      $composableBuilder(column: $table.download, builder: (column) => column);
}

class $$TrafficSourceCheckpointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TrafficSourceCheckpointsTable,
          TrafficSourceCheckpointRecord,
          $$TrafficSourceCheckpointsTableFilterComposer,
          $$TrafficSourceCheckpointsTableOrderingComposer,
          $$TrafficSourceCheckpointsTableAnnotationComposer,
          $$TrafficSourceCheckpointsTableCreateCompanionBuilder,
          $$TrafficSourceCheckpointsTableUpdateCompanionBuilder,
          (
            TrafficSourceCheckpointRecord,
            BaseReferences<
              _$AppDatabase,
              $TrafficSourceCheckpointsTable,
              TrafficSourceCheckpointRecord
            >,
          ),
          TrafficSourceCheckpointRecord,
          PrefetchHooks Function()
        > {
  $$TrafficSourceCheckpointsTableTableManager(
    _$AppDatabase db,
    $TrafficSourceCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => $$TrafficSourceCheckpointsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer:
              () => $$TrafficSourceCheckpointsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => $$TrafficSourceCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> targetId = const Value.absent(),
                Value<int> upload = const Value.absent(),
                Value<int> download = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TrafficSourceCheckpointsCompanion(
                sessionId: sessionId,
                kind: kind,
                targetId: targetId,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String kind,
                required String targetId,
                required int upload,
                required int download,
                Value<int> rowid = const Value.absent(),
              }) => TrafficSourceCheckpointsCompanion.insert(
                sessionId: sessionId,
                kind: kind,
                targetId: targetId,
                upload: upload,
                download: download,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TrafficSourceCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TrafficSourceCheckpointsTable,
      TrafficSourceCheckpointRecord,
      $$TrafficSourceCheckpointsTableFilterComposer,
      $$TrafficSourceCheckpointsTableOrderingComposer,
      $$TrafficSourceCheckpointsTableAnnotationComposer,
      $$TrafficSourceCheckpointsTableCreateCompanionBuilder,
      $$TrafficSourceCheckpointsTableUpdateCompanionBuilder,
      (
        TrafficSourceCheckpointRecord,
        BaseReferences<
          _$AppDatabase,
          $TrafficSourceCheckpointsTable,
          TrafficSourceCheckpointRecord
        >,
      ),
      TrafficSourceCheckpointRecord,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$PreferencesTableTableManager get preferences =>
      $$PreferencesTableTableManager(_db, _db.preferences);
  $$NodesTableTableManager get nodes =>
      $$NodesTableTableManager(_db, _db.nodes);
  $$NodeGroupsTableTableManager get nodeGroups =>
      $$NodeGroupsTableTableManager(_db, _db.nodeGroups);
  $$CoreLogsTableTableManager get coreLogs =>
      $$CoreLogsTableTableManager(_db, _db.coreLogs);
  $$NodeOverridesTableTableManager get nodeOverrides =>
      $$NodeOverridesTableTableManager(_db, _db.nodeOverrides);
  $$TrafficBucketsTableTableManager get trafficBuckets =>
      $$TrafficBucketsTableTableManager(_db, _db.trafficBuckets);
  $$TrafficSourcesTableTableManager get trafficSources =>
      $$TrafficSourcesTableTableManager(_db, _db.trafficSources);
  $$TrafficCheckpointsTableTableManager get trafficCheckpoints =>
      $$TrafficCheckpointsTableTableManager(_db, _db.trafficCheckpoints);
  $$TrafficSourceCheckpointsTableTableManager get trafficSourceCheckpoints =>
      $$TrafficSourceCheckpointsTableTableManager(
        _db,
        _db.trafficSourceCheckpoints,
      );
}
