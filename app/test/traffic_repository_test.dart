import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';

void main() {
  test(
      'legacy totals migrate once and earlier days survive restart and rollover',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.preferences)
        .insert(PreferencesCompanion.insert(
            key: 'traffic.daily',
            value: jsonEncode({
              'day': '2026-10-15',
              'session': 'a',
              'upload': 200,
              'download': 800,
              'lastUp': 200,
              'lastDown': 800,
            })));
    var now = DateTime(2026, 10, 16, 0, 1);
    var repository = DriftTrafficRepository(database, now: () => now);
    expect((await repository.watchHistory().first).single.total, 1000);
    await repository.record('a', 250, 850);
    var history = await repository.watchHistory().first;
    expect(history.map((day) => day.total), [1000, 100]);
    repository = DriftTrafficRepository(database, now: () => now);
    await repository.record('a', 250, 850);
    await repository.record('b', 20, 80);
    expect((await repository.watchToday().first).total, 200);
    now = DateTime(2026, 10, 17);
    await repository.record('b', 30, 90);
    history = await repository.watchHistory().first;
    expect(history.map((day) => day.total), [1000, 200, 20]);
    expect((await repository.watchToday().first).total, 20);
  });

  test(
      'late and repeated samples do not double count, invalid values do not write',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository =
        DriftTrafficRepository(database, now: () => DateTime(2026, 10, 16));
    await repository.record('a', 100, 400);
    await repository.record('a', 50, 200);
    await repository.record('a', 100, 400);
    expect((await repository.watchHistory().first).single.total, 500);
    await expectLater(repository.record('a', -1, 500), throwsFormatException);
    expect((await repository.watchToday().first).total, 500);
  });

  test('reports use calendar weeks and months and exclude future records', () {
    final records = [
      TrafficDay(day: DateTime(2026, 10, 31), download: 100),
      TrafficDay(day: DateTime(2026, 11, 1), download: 200),
      TrafficDay(day: DateTime(2026, 11, 2), upload: 10, download: 300),
      TrafficDay(day: DateTime(2026, 11, 4), download: 900),
    ];
    final now = DateTime(2026, 11, 3, 23);
    final week = TrafficReport.fromDays(records, TrafficPeriod.week, now);
    expect(week.total, 310);
    expect(week.days.length, 2);
    expect(week.days.last.total, 0);
    expect(
        TrafficReport.fromDays(records, TrafficPeriod.month, now).total, 510);
    expect(TrafficReport.fromDays(records, TrafficPeriod.today, now).total, 0);
    final leapMonth =
        TrafficReport.fromDays([], TrafficPeriod.month, DateTime(2028, 2, 29));
    expect(leapMonth.days.length, 29);
  });
}
