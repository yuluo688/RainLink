import 'package:drift/drift.dart';

part 'app_database.g.dart';

class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class Nodes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get protocol => text()();
  TextColumn get server => text()();
  IntColumn get port => integer()();
  BoolColumn get tls => boolean().withDefault(const Constant(false))();
  TextColumn get credential => text().withDefault(const Constant(''))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get options => text().withDefault(const Constant('{}'))();
  TextColumn get groupId => text().nullable()();
  TextColumn get sourceKey => text().withDefault(const Constant(''))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('NodeOverrideRecord')
class NodeOverrides extends Table {
  TextColumn get nodeId =>
      text().references(Nodes, #id, onDelete: KeyAction.cascade)();
  TextColumn get alias => text().withDefault(const Constant(''))();
  BoolColumn get favorite => boolean().withDefault(const Constant(false))();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {nodeId};
}

@DataClassName('NodeGroupRecord')
class NodeGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  BoolColumn get customName => boolean().withDefault(const Constant(false))();
  TextColumn get urlCipher => text().withDefault(const Constant(''))();
  TextColumn get urlHash => text().withDefault(const Constant(''))();
  IntColumn get uploaded => integer().nullable()();
  IntColumn get downloaded => integer().nullable()();
  IntColumn get total => integer().nullable()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get attemptedAt => dateTime().nullable()();
  TextColumn get updateError => text().withDefault(const Constant(''))();
  IntColumn get skippedNodes => integer().withDefault(const Constant(0))();
  TextColumn get compatibilityIssues =>
      text().withDefault(const Constant('[]'))();
  BoolColumn get autoUpdate => boolean().withDefault(const Constant(true))();
  IntColumn get intervalHours => integer().withDefault(const Constant(24))();
  TextColumn get lastSelectedNodeId => text().nullable()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CoreLogRecord')
class CoreLogs extends Table {
  TextColumn get id => text()();
  // Keep core timestamps at millisecond precision.
  IntColumn get at => integer()();
  IntColumn get sequence => integer().withDefault(const Constant(0))();
  TextColumn get level => text()();
  TextColumn get source => text()();
  TextColumn get message => text()();
  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('TrafficBucketRecord')
class TrafficBuckets extends Table {
  TextColumn get day => text()();
  IntColumn get slot => integer()();
  IntColumn get upload => integer()();
  IntColumn get download => integer()();
  @override
  Set<Column<Object>> get primaryKey => {day, slot};
}

@DataClassName('TrafficSourceRecord')
class TrafficSources extends Table {
  TextColumn get day => text()();
  TextColumn get targetId => text()();
  TextColumn get kind => text()();
  TextColumn get name => text()();
  IntColumn get upload => integer()();
  IntColumn get download => integer()();
  @override
  Set<Column<Object>> get primaryKey => {day, kind, targetId};
}

@DataClassName('TrafficCheckpointRecord')
class TrafficCheckpoints extends Table {
  TextColumn get sessionId => text()();
  IntColumn get upload => integer()();
  IntColumn get download => integer()();
  TextColumn get epoch => text().withDefault(const Constant(''))();
  IntColumn get sampledAt => integer().withDefault(const Constant(0))();
  @override
  Set<Column<Object>> get primaryKey => {sessionId};
}

@DataClassName('TrafficSourceCheckpointRecord')
class TrafficSourceCheckpoints extends Table {
  TextColumn get sessionId => text()();
  TextColumn get kind => text()();
  TextColumn get targetId => text()();
  IntColumn get upload => integer()();
  IntColumn get download => integer()();
  @override
  Set<Column<Object>> get primaryKey => {sessionId, kind, targetId};
}

@DriftDatabase(
  tables: [
    Preferences,
    Nodes,
    NodeGroups,
    CoreLogs,
    NodeOverrides,
    TrafficBuckets,
    TrafficSources,
    TrafficCheckpoints,
    TrafficSourceCheckpoints,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  Future<void>? _closing;

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await migrator.createTable(nodes);
      if (from < 3) {
        if (from >= 2) {
          await migrator.addColumn(nodes, nodes.options);
          await migrator.addColumn(nodes, nodes.groupId);
          await migrator.addColumn(nodes, nodes.sourceKey);
        }
        await migrator.createTable(nodeGroups);
      }
      if (from < 4) await migrator.createTable(coreLogs);
      if (from < 5) await migrator.createTable(nodeOverrides);
      if (from < 6) {
        await migrator.createTable(trafficBuckets);
        await migrator.createTable(trafficSources);
        await migrator.createTable(trafficCheckpoints);
      }
      if (from >= 3 && from < 7) {
        await migrator.addColumn(nodeGroups, nodeGroups.compatibilityIssues);
      }
      if (from < 8) {
        if (from >= 6) {
          await migrator.addColumn(
            trafficCheckpoints,
            trafficCheckpoints.epoch,
          );
          await migrator.addColumn(
            trafficCheckpoints,
            trafficCheckpoints.sampledAt,
          );
        }
        await migrator.createTable(trafficSourceCheckpoints);
      }
    },
    beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
  );

  @override
  Future<void> close() => _closing ??= super.close();
}
