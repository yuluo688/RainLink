import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/traffic_accounting.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/platform/core/core_traffic_protocol.dart';

const _node = TrafficAttribution(id: 'node', name: '工作节点', kind: 'node');
const _browser = TrafficAttribution(
  id: 'browser',
  name: 'browser.exe',
  kind: 'application',
);

TrafficCounter _row(TrafficAttribution target, int up, int down) =>
    TrafficCounter(target: target, upload: up, download: down);

TrafficAccountingSnapshot sample(
  List<TrafficCounter> targets, {
  String session = 'session',
  String epoch = 'epoch',
  int at = 1,
  List<TrafficCounter>? applications,
}) {
  final up = targets.fold(0, (sum, row) => sum + row.upload);
  final down = targets.fold(0, (sum, row) => sum + row.download);
  return TrafficAccountingSnapshot(
    sessionId: session,
    epoch: epoch,
    sampledAt: DateTime(2026, 10, 20, 10, 0, at),
    upload: up,
    download: down,
    targets: targets,
    applications: applications ?? [_row(_browser, up, down)],
  );
}

void main() {
  test(
    'closed-flow partitions persist across dates, sessions and reopening without duplicates',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rainlink-accounting-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/traffic.sqlite');
      var now = DateTime(2026, 10, 20, 23, 59);
      var db = AppDatabase(NativeDatabase(file));
      var repository = DriftTrafficRepository(db, now: () => now);
      final first = sample(
        [_row(_node, 10, 40), _row(TrafficAttribution.direct, 5, 10)],
        applications: [
          _row(_browser, 12, 45),
          _row(TrafficAttribution.unknownApplication, 3, 5),
        ],
      );
      await repository.recordAccounting(first);
      now = DateTime(2026, 10, 21, 0, 1);
      final second = sample(
        [_row(_node, 20, 50), _row(TrafficAttribution.direct, 10, 30)],
        at: 2,
        applications: [
          _row(_browser, 22, 70),
          _row(TrafficAttribution.unknownApplication, 8, 10),
        ],
      );
      await repository.recordAccounting(second);
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      repository = DriftTrafficRepository(db, now: () => now);
      await repository.recordAccounting(first);
      await repository.recordAccounting(second);
      await repository.recordAccounting(
        sample(
          [_row(_node, 4, 6)],
          session: 'next-session',
          epoch: 'next-epoch',
        ),
      );
      final archive = await repository.watchArchive().first;
      expect(archive.days.map((r) => r.total), [65, 55]);
      expect(archive.buckets.fold(0, (sum, r) => sum + r.total), 120);
      final view = archive.forPeriod(TrafficPeriod.month, now);
      expect(view.report.total, 120);
      for (final dimension in [view.ranking, view.applicationRanking]) {
        expect(
          dimension.fold(0, (sum, r) => sum + r.upload),
          view.report.upload,
        );
        expect(
          dimension.fold(0, (sum, r) => sum + r.download),
          view.report.download,
        );
      }
      expect(view.ranking.singleWhere((r) => r.target.id == 'node').total, 80);
      expect(
        view.applicationRanking
            .singleWhere((r) => r.target.id == 'browser')
            .total,
        102,
      );
    },
  );

  test(
    'legacy baseline preserves historical attribution and only later precise deltas become known',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final now = DateTime(2026, 10, 20);
      final repository = DriftTrafficRepository(db, now: () => now);
      const legacy = TrafficAttribution(
        id: 'legacy',
        name: '旧节点',
        kind: 'node',
      );
      await repository.record('session', 100, 400, attribution: legacy);
      await repository.recordAccounting(sample([_row(_node, 100, 600)]));
      await repository.recordAccounting(sample([_row(_node, 110, 650)], at: 2));
      final archive = await repository.watchArchive().first;
      final view = archive.forPeriod(TrafficPeriod.today, now);
      expect(view.report.total, 760);
      expect(
        view.ranking.singleWhere((r) => r.target.id == 'legacy').total,
        500,
      );
      expect(view.ranking.singleWhere((r) => r.target.id == 'node').total, 60);
      expect(
        view.ranking.singleWhere((r) => r.target.kind == 'unknown').total,
        200,
      );
      expect(
        view.applicationRanking
            .singleWhere((r) => r.target.id == 'browser')
            .total,
        60,
      );
      expect(
        view.applicationRanking
            .singleWhere((r) => r.target.id == 'unassigned')
            .total,
        700,
      );
      await expectLater(
        repository.record('session', 120, 700),
        throwsFormatException,
      );
      expect((await repository.watchToday().first).total, 760);
    },
  );

  test(
    'per-source rollback, missing sources, epoch reuse and invalid partitions are atomic',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftTrafficRepository(db);
      await repository.recordAccounting(
        sample([_row(_node, 10, 40), _row(TrafficAttribution.direct, 5, 10)]),
      );
      for (final bad in [
        sample([
          _row(_node, 9, 50),
          _row(TrafficAttribution.direct, 10, 20),
        ], at: 2),
        sample([_row(_node, 20, 60)], at: 2),
        sample([_row(_node, 20, 60)], epoch: 'unexpected', at: 2),
        sample(
          [_row(_node, 20, 60)],
          applications: [_row(_browser, 1, 1)],
          at: 2,
        ),
        sample([_row(_node, 10, 40), _row(_node, 5, 10)], at: 2),
      ]) {
        await expectLater(
          repository.recordAccounting(bad),
          throwsFormatException,
        );
        expect((await repository.watchToday().first).total, 65);
        expect(
          (await db.select(db.trafficCheckpoints).get()).single.upload,
          15,
        );
        expect((await db.select(db.trafficSourceCheckpoints).get()).length, 3);
      }
      // A clock correction cannot freeze valid cumulative counters. Older byte
      // snapshots still remain stale even if their wall timestamp is later.
      await repository.recordAccounting(
        sample([
          _row(_node, 20, 50),
          _row(TrafficAttribution.direct, 10, 20),
        ], at: 0),
      );
      expect((await repository.watchToday().first).total, 100);
      await repository.recordAccounting(
        sample([
          _row(_node, 10, 40),
          _row(TrafficAttribution.direct, 5, 10),
        ], at: 2),
      );
      expect((await repository.watchToday().first).total, 100);
    },
  );

  test('daily overflow rolls back all counters and checkpoints', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repository = DriftTrafficRepository(db);
    await repository.recordAccounting(
      sample([_row(_node, maximumTrafficCounter, 0)]),
    );
    await expectLater(
      repository.recordAccounting(
        sample([_row(_node, 1, 0)], session: 'other'),
      ),
      throwsFormatException,
    );
    expect((await repository.watchToday().first).upload, maximumTrafficCounter);
    expect((await db.select(db.trafficCheckpoints).get()).length, 1);
  });

  test(
    'schema 7 migration retains old ledger and starts source checkpoints safely',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'rainlink-accounting-migration-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/traffic.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      await DriftTrafficRepository(db).record('session', 10, 40);
      await db.customStatement('DROP TABLE traffic_source_checkpoints');
      await db.customStatement(
        'ALTER TABLE traffic_checkpoints DROP COLUMN epoch',
      );
      await db.customStatement(
        'ALTER TABLE traffic_checkpoints DROP COLUMN sampled_at',
      );
      await db.customStatement('PRAGMA user_version = 7');
      await db.close();
      db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final repository = DriftTrafficRepository(db);
      await repository.recordAccounting(sample([_row(_node, 20, 60)]));
      await repository.recordAccounting(sample([_row(_node, 21, 69)], at: 2));
      expect((await repository.watchToday().first).total, 90);
      expect(
        (await db.select(db.trafficCheckpoints).get()).single.epoch,
        'epoch',
      );
      expect((await db.select(db.trafficSourceCheckpoints).get()).length, 2);
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        8,
      );
    },
  );

  test(
    'public parser rejects cross-session, inconsistent and private-path samples',
    () {
      Map<String, Object?> data() => {
        'version': 1,
        'sessionId': 'session',
        'epoch': 'epoch',
        'sampledAt': DateTime(2026, 10, 20).millisecondsSinceEpoch,
        'uploadTotal': 10,
        'downloadTotal': 40,
        'limited': false,
        'targets': [
          {
            'kind': 'node',
            'id': 'node',
            'name': '节点',
            'upload': 10,
            'download': 40,
          },
        ],
        'applications': [
          {
            'kind': 'application',
            'id': 'app',
            'name': 'browser.exe',
            'upload': 10,
            'download': 40,
          },
        ],
      };
      expect(CoreTrafficProtocol.parse(data(), sessionId: 'session').total, 50);
      for (final invalid in [
        {...data(), 'version': 2},
        {...data(), 'sessionId': 'other'},
        {...data(), 'uploadTotal': 11},
        {...data(), 'limited': null},
        {...data(), 'targets': null},
        {...data(), 'epoch': ''},
        {...data(), 'sampledAt': maximumTrafficCounter},
        {
          ...data(),
          'applications': [
            {
              'kind': 'application',
              'id': 'app',
              'name': r'C:\private\browser.exe',
              'upload': 10,
              'download': 40,
            },
          ],
        },
      ]) {
        expect(
          () => CoreTrafficProtocol.parse(invalid, sessionId: 'session'),
          throwsA(isA<CoreGatewayException>()),
        );
      }
    },
  );
}
