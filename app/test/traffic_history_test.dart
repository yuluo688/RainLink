import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/connection/traffic_attribution.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/connection/traffic_history.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/export/data_export.dart';

const _target = TrafficAttribution(id: 'node-a', name: '工作线路', kind: 'node');

void main() {
  test('session checkpoints survive reopen and interleaved late observations',
      () async {
    final dir = await Directory.systemTemp.createTemp('rainlink-traffic-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    var now = DateTime(2026, 10, 16, 9);
    var db = AppDatabase(NativeDatabase(file));
    var repo = DriftTrafficRepository(db, now: () => now);
    await repo.record('a', 100, 400, attribution: _target);
    await repo.record('b', 5, 20);
    await repo.record('a', 110, 450, attribution: _target);
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    repo = DriftTrafficRepository(db, now: () => now);
    await repo.record('b', 5, 20);
    await repo.record('a', 100, 400, attribution: _target);
    var archive = await repo.watchArchive().first;
    expect(archive.days.single.total, 585);
    expect(archive.buckets.single.total, 585);
    now = DateTime(2026, 10, 17, 0, 2);
    await repo.record('a', 120, 480, attribution: _target);
    // A time zone or clock moving back must update the existing civil day.
    now = DateTime(2026, 10, 16, 23, 59);
    await repo.record('b', 10, 25);
    now = DateTime(2026, 10, 17, 0, 3);
    archive = await repo.watchArchive().first;
    expect(archive.days.map((d) => d.total), [595, 40]);
    expect(archive.buckets.fold(0, (sum, b) => sum + b.total), 635);
    final report = archive.forPeriod(TrafficPeriod.month, now);
    expect(report.ranking.fold(0, (sum, item) => sum + item.total),
        report.report.total);
    expect(report.ranking.first.target.id, 'node-a');
  });

  test('old detailed buckets expire while daily history stays available',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2024, 10, 1);
    final repo = DriftTrafficRepository(db, now: () => now);
    await repo.record('old', 10, 90);
    now = DateTime(2026, 10, 16);
    await repo.record('new', 20, 80);
    expect((await repo.watchHistory().first).length, 2);
    expect((await db.select(db.trafficBuckets).get()).single.day, '2026-10-16');
    expect(
        (await repo.watchArchive(TrafficPeriod.today).first).days.single.total,
        100);
  });

  test('recorded zero buckets remain distinct from absent intervals', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2026, 10, 16, 9);
    final repo = DriftTrafficRepository(db, now: () => now);
    await repo.record('a', 0, 0);
    now = DateTime(2026, 10, 16, 9, 45);
    await repo.record('a', 10, 20);
    final archive = await repo.watchArchive().first;
    expect(archive.buckets.map((b) => b.slot), [36, 39]);
    expect(archive.buckets.first.total, 0);
    expect(archive.forPeriod(TrafficPeriod.today, now).observedDays,
        {'2026-10-16'});
    expect(archive.buckets.last.label, '09:45');
  });

  test(
      'schema 5 and legacy checkpoint migrate without inventing history or attribution',
      () async {
    final dir =
        await Directory.systemTemp.createTemp('rainlink-traffic-migration-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/test.sqlite');
    var db = AppDatabase(NativeDatabase(file));
    await db.into(db.preferences).insert(PreferencesCompanion.insert(
        key: 'traffic.daily',
        value: jsonEncode({
          'day': '2026-10-16',
          'session': 'a',
          'upload': 100,
          'download': 400,
          'lastUp': 100,
          'lastDown': 400,
        })));
    for (final table in [
      'traffic_buckets',
      'traffic_sources',
      'traffic_checkpoints'
    ]) {
      await db.customStatement('DROP TABLE $table');
    }
    await db.customStatement(
        'ALTER TABLE node_groups DROP COLUMN compatibility_issues');
    await db.customStatement('PRAGMA user_version = 5');
    await db.close();
    db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final now = DateTime(2026, 10, 16, 12);
    final repo = DriftTrafficRepository(db, now: () => now);
    var archive = await repo.watchArchive().first;
    expect(archive.days.single.total, 500);
    expect(archive.buckets, isEmpty);
    expect(
        archive.forPeriod(TrafficPeriod.today, now).ranking.single.target.kind,
        'unknown');
    await repo.record('a', 120, 420, attribution: _target);
    await repo.record('b', 1, 2);
    await repo.record('a', 120, 420, attribution: _target);
    archive = await repo.watchArchive().first;
    expect(archive.days.single.total, 543);
    expect(archive.buckets.single.total, 43);
    final ranking = archive.forPeriod(TrafficPeriod.today, now).ranking;
    expect(ranking.first.target.kind, 'unknown');
    expect(ranking.first.total, 503);
    expect(ranking.last.total, 40);
  });

  test('period queries exclude other dates and invalid attribution rolls back',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    var now = DateTime(2026, 10, 31);
    final repo = DriftTrafficRepository(db, now: () => now);
    await repo.record('a', 10, 90, attribution: _target);
    now = DateTime(2026, 11, 1);
    await repo.record('a', 20, 180, attribution: _target);
    expect((await repo.watchArchive(TrafficPeriod.week).first).days.length, 2);
    expect(
        (await repo.watchArchive(TrafficPeriod.month).first).days.single.total,
        100);
    await expectLater(
        repo.record('bad', 10, 10,
            attribution:
                const TrafficAttribution(id: 'x', name: 'x', kind: 'process')),
        throwsFormatException);
    expect((await db.select(db.trafficCheckpoints).get()).length, 1);
    expect((await repo.watchToday().first).total, 100);
  });

  test(
      'mode and target changes permanently invalidate aggregate attribution for that session',
      () {
    ActiveConnectionSnapshot active(ProxyMode mode, {String id = 'session'}) =>
        ActiveConnectionSnapshot(
            sessionId: id,
            mode: mode,
            configRevision: 'config',
            target: const ProxyTarget(id: 'a', name: 'A', revision: 1));
    final tracker = SessionTrafficAttribution();
    tracker.start(active(ProxyMode.global));
    expect(tracker.resolve(active(ProxyMode.global)).kind, 'node');
    tracker.invalidate();
    expect(tracker.resolve(active(ProxyMode.global)).kind, 'unknown');
    tracker.start(active(ProxyMode.rule));
    expect(tracker.resolve(active(ProxyMode.rule)).kind, 'unknown');
    tracker.start(active(ProxyMode.direct));
    expect(tracker.resolve(active(ProxyMode.direct)).kind, 'direct');
    expect(tracker.resolve(active(ProxyMode.global)).kind, 'unknown');
    expect(tracker.resolve(active(ProxyMode.direct)).kind, 'unknown');
    tracker.start(active(ProxyMode.global));
    expect(tracker.resolve(active(ProxyMode.global, id: 'another')).kind,
        'unknown');
  });

  test('CSV contains exact displayed period and neutralizes untrusted names',
      () {
    final now = DateTime(2026, 10, 16);
    final archive = TrafficArchive(days: [
      TrafficDay(day: now, upload: 100, download: 200)
    ], buckets: [
      const TrafficBucket(
          day: '2026-10-16', slot: 36, upload: 100, download: 200)
    ], usage: [
      const TrafficUsage(
          day: '2026-10-16',
          target:
              TrafficAttribution(id: 'a', name: '=danger,"line"', kind: 'node'),
          upload: 100,
          download: 200),
      const TrafficUsage(day: '2026-10-15', target: _target, download: 900)
    ]);
    final text = trafficCsv(archive.forPeriod(TrafficPeriod.today, now));
    expect(text, startsWith('\uFEFF'));
    expect(text, contains('"09:00"'));
    expect(text, contains("'=danger,"));
    expect(text, contains('"100","200","300"'));
    expect(text, isNot(contains('900')));
    expect(text.split('\r\n').where((s) => s.isNotEmpty).length, 4);
  });
}
