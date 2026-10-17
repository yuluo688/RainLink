import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/logs/drift_core_log_repository.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/export/data_export.dart';
import 'package:rainlink/platform/core/core_telemetry_protocol.dart';

import 'support/telemetry_fixture.dart';

void main() {
  test(
      'pause preserves the view, explicit close uses the core and failure preserves rows',
      () async {
    final gateway = FixtureTelemetryGateway();
    final controller = ConnectionsController(gateway);
    addTearDown(controller.dispose);
    controller.setSession('session');
    await controller.refresh();
    expect(controller.state.snapshot?.entries, hasLength(6));
    controller.togglePaused();
    final reads = gateway.reads;
    await controller.refresh();
    expect(gateway.reads, reads);
    expect(gateway.closed, isEmpty);
    gateway.closeFailure = const CoreGatewayException('failure', '核心未确认关闭');
    await controller.closeConnection('fixture-0');
    expect(controller.state.snapshot?.entries, hasLength(6));
    expect(controller.state.error, contains('核心未确认'));
    gateway.closeFailure = null;
    await controller.closeConnection('fixture-0');
    expect(gateway.closed, ['fixture-0']);
    expect(controller.state.snapshot?.entries, hasLength(5));
    expect(controller.state.paused, isTrue);
    await controller.closeConnection();
    expect(controller.state.snapshot?.entries, isEmpty);
  });

  test('late observation cannot overwrite a new session or a disconnected page',
      () async {
    final gateway = FixtureTelemetryGateway();
    final first = Completer<ConnectionsSnapshot>();
    gateway.onConnections = (id) => id == 'old'
        ? first.future
        : Future.value(
            ConnectionsSnapshot(sessionId: id, at: telemetryFixtureAt));
    final controller = ConnectionsController(gateway);
    addTearDown(controller.dispose);
    controller.setSession('old');
    controller.setSession('new');
    first.complete(ConnectionsSnapshot(
        sessionId: 'old',
        at: telemetryFixtureAt,
        entries: telemetryFixtureConnections()));
    await controller.refresh();
    await Future<void>.delayed(Duration.zero);
    await controller.refresh();
    expect(controller.state.snapshot?.sessionId, 'new');
    controller.setSession(null);
    expect(controller.state.snapshot, isNull);
  });

  test(
      'database preserves millisecond order, deduplicates, bounds capacity and expires logs',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var now = telemetryFixtureAt;
    final repository = DriftCoreLogRepository(database, now: () => now);
    final entries = [
      for (var i = 1; i <= CoreLogRepository.maxEntries + 2; i++)
        CoreLogEntry(
            id: 'host:$i',
            sequence: i,
            at: now,
            level: CoreLogLevel.info,
            source: 'core',
            message: 'event $i')
    ];
    await repository.append(entries);
    await repository.append([entries.last]);
    final saved = await repository.watch().first;
    expect(saved, hasLength(CoreLogRepository.maxEntries));
    expect(saved.first.sequence, 3);
    expect(saved.last.sequence, CoreLogRepository.maxEntries + 2);
    expect(saved.last.at.millisecond, 158);
    now = now.add(const Duration(days: 8));
    await repository.prune();
    expect(await repository.watch().first, isEmpty);
  });

  test(
      'schema 3 migrates without losing nodes or preferences; logs survive reopen',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-logs-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    final previous = _SchemaThreeDatabase(NativeDatabase(file));
    await previous
        .into(previous.preferences)
        .insert(PreferencesCompanion.insert(key: 'theme', value: 'dark'));
    await previous.into(previous.nodes).insert(NodesCompanion.insert(
        id: 'retained',
        name: '手动节点',
        protocol: 'http',
        server: 'example.test',
        port: 8080));
    await previous.close();
    var database = AppDatabase(NativeDatabase(file));
    var repository =
        DriftCoreLogRepository(database, now: () => telemetryFixtureAt);
    await repository.append(telemetryFixtureLogs());
    expect((await database.select(database.nodes).get()).single.id, 'retained');
    expect((await database.select(database.preferences).get()).single.value,
        'dark');
    await database.close();
    database = AppDatabase(NativeDatabase(file));
    repository =
        DriftCoreLogRepository(database, now: () => telemetryFixtureAt);
    expect(await repository.watch().first, hasLength(8));
    await repository.clear();
    expect(await repository.watch().first, isEmpty);
    await database.close();
  });

  test(
      'collector checkpoints only persisted batches and serializes clear after reads',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository =
        DriftCoreLogRepository(database, now: () => telemetryFixtureAt);
    final gateway = FixtureTelemetryGateway();
    final collector = CoreLogCollector(gateway, repository);
    addTearDown(collector.dispose);
    final batch = Completer<CoreLogBatch>();
    gateway.onLogs = (_, __) => batch.future;
    final collecting = collector.collect();
    final clearing = collector.clear();
    batch.complete(CoreLogBatch(
        stream: 'fixture',
        cursor: 8,
        more: false,
        dropped: false,
        entries: telemetryFixtureLogs()));
    await collecting;
    await clearing;
    expect(await repository.watch().first, isEmpty);
    expect(gateway.logClears, 1);
    gateway.onLogs = null;
    gateway.logCursor = 9;
    gateway.logEntries.add(CoreLogEntry(
        id: 'fixture:9',
        sequence: 9,
        at: telemetryFixtureAt,
        level: CoreLogLevel.info,
        source: 'core',
        message: 'new event'));
    await collector.collect();
    await collector.collect();
    expect((await repository.watch().first).single.message, 'new event');
  });

  test('telemetry boundary rejects invalid cursors, levels and counters', () {
    final valid = <String, Object?>{
      'stream': 'host',
      'cursor': 1,
      'more': false,
      'dropped': false,
      'entries': [
        <String, Object?>{
          'id': 'host:1',
          'seq': 1,
          'at': 1792140000158,
          'level': 'warning',
          'source': 'core',
          'message': 'timeout'
        }
      ]
    };
    expect(CoreTelemetryProtocol.logs(valid).entries.single.level,
        CoreLogLevel.warning);
    expect(() => CoreTelemetryProtocol.logs({...valid, 'cursor': -1}),
        throwsA(isA<CoreGatewayException>()));
    expect(() => CoreTelemetryProtocol.logs({...valid, 'stream': 'different'}),
        throwsA(isA<CoreGatewayException>()));
    final duplicate = <String, Object?>{
      ...valid,
      'entries': [
        ...(valid['entries'] as List<Object?>),
        ...(valid['entries'] as List<Object?>)
      ]
    };
    expect(() => CoreTelemetryProtocol.logs(duplicate),
        throwsA(isA<CoreGatewayException>()));
    expect(
        () => CoreTelemetryProtocol.connections({'entries': [], 'total': -1}),
        throwsA(isA<CoreGatewayException>()));
  });

  test('CSV export matches filters and neutralizes spreadsheet injection', () {
    final entries = telemetryFixtureConnections();
    final visible =
        entries.where((entry) => entry.matches('GITHUB tcp')).toList();
    final csv =
        connectionsCsv(ConnectionsSnapshot(at: telemetryFixtureAt), visible);
    expect(csv, contains('api.github.com:443'));
    expect(csv, isNot(contains('registry.npmjs.org')));
    expect(csvCell('=HYPERLINK("bad")'), startsWith('"\'='));
    expect(csvCell('  @SUM(1)'), startsWith('"\'  @'));
    expect(logsCsv(telemetryFixtureLogs()), contains('警告'));
  });
}

class _SchemaThreeDatabase extends AppDatabase {
  _SchemaThreeDatabase(super.executor);
  @override
  int get schemaVersion => 3;
  @override
  MigrationStrategy get migration =>
      MigrationStrategy(onCreate: (migrator) async {
        await migrator.createTable(preferences);
        await migrator.createTable(nodes);
        await migrator.createTable(nodeGroups);
        // Generated tables describe the latest schema; this fixture is v3.
        await customStatement(
            'ALTER TABLE node_groups DROP COLUMN compatibility_issues');
      });
}
