import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/connection/traffic_repository.dart';
import '../../domain/connection/traffic_history.dart';
import '../database/app_database.dart';

class DriftTrafficRepository implements TrafficArchiveRepository {
  DriftTrafficRepository(this.database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() _now;
  static const _key = 'traffic.daily';
  static const _dayPrefix = 'traffic.day.';
  static const _bucketRetentionDays = 400;
  Future<Map<String, Object?>> _load() async {
    final row = await (database.select(database.preferences)
          ..where((r) => r.key.equals(_key)))
        .getSingleOrNull();
    if (row == null) return {};
    final Object? decoded = jsonDecode(row.value);
    if (decoded is Map<String, Object?>) return decoded;
    throw const FormatException('Invalid traffic record');
  }

  @override
  Stream<DailyTraffic> watchToday() => Stream.multi((controller) {
        var records = <TrafficDay>[];
        Timer? timer;
        void emit() {
          final now = _now();
          final today = DateTime(now.year, now.month, now.day);
          controller.add(
              records.where((record) => record.day == today).firstOrNull ??
                  const DailyTraffic());
        }

        void scheduleMidnight() {
          final now = _now();
          timer = Timer(
              DateTime(now.year, now.month, now.day + 1).difference(now), () {
            emit();
            scheduleMidnight();
          });
        }

        final subscription = watchHistory().listen((value) {
          records = value;
          emit();
        }, onError: controller.addError);
        scheduleMidnight();
        controller.onCancel = () {
          timer?.cancel();
          return subscription.cancel();
        };
      });

  @override
  Stream<List<TrafficDay>> watchHistory() => (database
          .select(database.preferences)
        ..where((row) => row.key.equals(_key) | row.key.like('$_dayPrefix%')))
      .watch()
      .map(_history);

  List<TrafficDay> _history(List<Preference> rows) {
    final days = <String, TrafficDay>{};
    // The old daily checkpoint remains readable before the first new write.
    // New per-day rows take precedence; migration never doubles old totals.
    for (final row in [
      ...rows.where((row) => row.key == _key),
      ...rows.where((row) => row.key != _key)
    ]) {
      final Object? value = jsonDecode(row.value);
      if (value
          case {'day': String day, 'upload': int up, 'download': int down}) {
        final date = DateTime.tryParse(day);
        if (date == null ||
            date.toIso8601String().substring(0, 10) != day ||
            up < 0 ||
            down < 0) {
          throw const FormatException('流量记录格式无效');
        }
        days[day] = TrafficDay(day: date, upload: up, download: down);
      } else {
        throw const FormatException('流量记录格式无效');
      }
    }
    return days.values.toList()..sort((a, b) => a.day.compareTo(b.day));
  }

  @override
  Stream<TrafficArchive> watchArchive(
          [TrafficPeriod period = TrafficPeriod.month]) =>
      database
          .customSelect('SELECT 1', readsFrom: {
            database.preferences,
            database.trafficBuckets,
            database.trafficSources
          })
          .watch()
          .asyncMap((_) => database.transaction(() async {
                final now = _now();
                final start = trafficDayKey(trafficPeriodStart(period, now));
                final end = trafficDayKey(now);
                final rows = await (database.select(database.preferences)
                      ..where((row) =>
                          row.key.equals(_key) |
                          (row.key.isBiggerOrEqualValue('$_dayPrefix$start') &
                              row.key
                                  .isSmallerOrEqualValue('$_dayPrefix$end'))))
                    .get();
                final buckets = await (database.select(database.trafficBuckets)
                      ..where((r) =>
                          r.day.isBiggerOrEqualValue(start) &
                          r.day.isSmallerOrEqualValue(end))
                      ..orderBy([
                        (r) => OrderingTerm.asc(r.day),
                        (r) => OrderingTerm.asc(r.slot)
                      ]))
                    .get();
                final sources = await (database.select(database.trafficSources)
                      ..where((r) =>
                          r.day.isBiggerOrEqualValue(start) &
                          r.day.isSmallerOrEqualValue(end))
                      ..orderBy([(r) => OrderingTerm.asc(r.day)]))
                    .get();
                return TrafficArchive(days: _history(rows), buckets: [
                  for (final b in buckets)
                    TrafficBucket(
                        day: b.day,
                        slot: b.slot,
                        upload: b.upload,
                        download: b.download)
                ], usage: [
                  for (final s in sources)
                    TrafficUsage(
                        day: s.day,
                        target: TrafficAttribution(
                            id: s.targetId, name: s.name, kind: s.kind),
                        upload: s.upload,
                        download: s.download)
                ]);
              }));

  Future<void> _saveDay(String day, int upload, int download) => database
      .into(database.preferences)
      .insertOnConflictUpdate(PreferencesCompanion.insert(
          key: '$_dayPrefix$day',
          value:
              jsonEncode({'day': day, 'upload': upload, 'download': download})))
      .then((_) {});
  Future<void> _migrateLegacy() async {
    final previous = await _load();
    if (previous.isEmpty) return;
    final encoded = jsonEncode(previous);
    final day = _history([Preference(key: _key, value: encoded)]).single;
    final key = '$_dayPrefix${trafficDayKey(day.day)}';
    final stored = await (database.select(database.preferences)
          ..where((r) => r.key.equals(key)))
        .getSingleOrNull();
    if (stored == null) {
      await _saveDay(trafficDayKey(day.day), day.upload, day.download);
    }
    if (previous
        case {
          'session': String session,
          'lastUp': int up,
          'lastDown': int down
        }) {
      if (up < 0 || down < 0) throw const FormatException('流量计数无效');
      await database.into(database.trafficCheckpoints).insert(
          TrafficCheckpointsCompanion.insert(
              sessionId: session, upload: up, download: down),
          mode: InsertMode.insertOrIgnore);
    }
    await (database.delete(database.preferences)
          ..where((r) => r.key.equals(_key)))
        .go();
  }

  @override
  Future<void> record(String sessionId, int uploadTotal, int downloadTotal,
          {TrafficAttribution attribution = TrafficAttribution.unassigned}) =>
      database.transaction(() async {
        const maximumCounter = 9007199254740991;
        if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(sessionId) ||
            uploadTotal < 0 ||
            downloadTotal < 0 ||
            uploadTotal > maximumCounter ||
            downloadTotal > maximumCounter ||
            !{'node', 'chain', 'direct', 'unknown'}
                .contains(attribution.kind) ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(attribution.id) ||
            attribution.name.trim().isEmpty ||
            attribution.name.runes.length > 128 ||
            RegExp(r'[\x00-\x1F\x7F]').hasMatch(attribution.name)) {
          throw const FormatException('流量计数无效');
        }
        await _migrateLegacy();
        final now = _now();
        final day = trafficDayKey(now);
        final previous = await (database.select(database.trafficCheckpoints)
              ..where((r) => r.sessionId.equals(sessionId)))
            .getSingleOrNull();
        final priorUp = previous?.upload ?? 0,
            priorDown = previous?.download ?? 0;
        // An older observation must not turn a later interval into a known zero.
        if (uploadTotal < priorUp || downloadTotal < priorDown) return;
        final deltaUp = (uploadTotal - priorUp).clamp(0, uploadTotal);
        final deltaDown = (downloadTotal - priorDown).clamp(0, downloadTotal);
        final stored = await (database.select(database.preferences)
              ..where((r) => r.key.equals('$_dayPrefix$day')))
            .getSingleOrNull();
        final totals =
            stored == null ? const DailyTraffic() : _history([stored]).single;
        await _saveDay(
            day, totals.upload + deltaUp, totals.download + deltaDown);
        await database.into(database.trafficCheckpoints).insertOnConflictUpdate(
            TrafficCheckpointsCompanion.insert(
                sessionId: sessionId,
                upload: uploadTotal < priorUp ? priorUp : uploadTotal,
                download:
                    downloadTotal < priorDown ? priorDown : downloadTotal));
        final slot = (now.hour * 60 + now.minute) ~/ trafficBucketMinutes;
        final bucket = await (database.select(database.trafficBuckets)
              ..where((r) => r.day.equals(day) & r.slot.equals(slot)))
            .getSingleOrNull();
        await database.into(database.trafficBuckets).insertOnConflictUpdate(
            TrafficBucketsCompanion.insert(
                day: day,
                slot: slot,
                upload: (bucket?.upload ?? 0) + deltaUp,
                download: (bucket?.download ?? 0) + deltaDown));
        final source = await (database.select(database.trafficSources)
              ..where((r) =>
                  r.day.equals(day) &
                  r.kind.equals(attribution.kind) &
                  r.targetId.equals(attribution.id)))
            .getSingleOrNull();
        await database.into(database.trafficSources).insertOnConflictUpdate(
            TrafficSourcesCompanion.insert(
                day: day,
                targetId: attribution.id,
                kind: attribution.kind,
                name: attribution.name,
                upload: (source?.upload ?? 0) + deltaUp,
                download: (source?.download ?? 0) + deltaDown));
        // Keep high-resolution rows bounded while retaining inexpensive daily totals.
        final oldest = trafficDayKey(
            DateTime(now.year, now.month, now.day - _bucketRetentionDays));
        await (database.delete(database.trafficBuckets)
              ..where((r) => r.day.isSmallerThanValue(oldest)))
            .go();
      });
}
