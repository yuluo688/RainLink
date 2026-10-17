import 'package:drift/drift.dart';

import '../../domain/core/core_telemetry.dart';
import '../database/app_database.dart';

class DriftCoreLogRepository implements CoreLogRepository {
  DriftCoreLogRepository(this.database, {DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final AppDatabase database;
  final DateTime Function() _now;

  @override
  Stream<List<CoreLogEntry>> watch() => (database.select(database.coreLogs)
        ..orderBy([
          (row) => OrderingTerm.asc(row.at),
          (row) => OrderingTerm.asc(row.sequence),
          (row) => OrderingTerm.asc(row.id)
        ]))
      .watch()
      .map((rows) => rows
          .map((row) => CoreLogEntry(
              id: row.id,
              at: DateTime.fromMillisecondsSinceEpoch(row.at),
              sequence: row.sequence,
              level: CoreLogLevel.values.byName(row.level),
              source: row.source,
              message: row.message))
          .toList());

  @override
  Future<void> append(List<CoreLogEntry> entries) =>
      database.transaction(() async {
        if (entries.any((entry) =>
            entry.id.isEmpty ||
            entry.id.length > 160 ||
            entry.message.length > 2100 ||
            entry.source.length > 32)) {
          throw const FormatException('日志记录格式无效');
        }
        final cutoff = _now()
            .subtract(const Duration(days: CoreLogRepository.retentionDays));
        await database.batch((batch) {
          batch.insertAll(
              database.coreLogs,
              [
                for (final entry in entries)
                  if (!entry.at.isBefore(cutoff))
                    CoreLogsCompanion.insert(
                        id: entry.id,
                        at: entry.at.millisecondsSinceEpoch,
                        sequence: Value(entry.sequence),
                        level: entry.level.name,
                        source: entry.source,
                        message: entry.message)
              ],
              mode: InsertMode.insertOrIgnore);
        });
        await _prune();
      });

  @override
  Future<void> prune() => database.transaction(_prune);

  Future<void> _prune() async {
    final cutoff =
        _now().subtract(const Duration(days: CoreLogRepository.retentionDays));
    await (database.delete(database.coreLogs)
          ..where((row) =>
              row.at.isSmallerThanValue(cutoff.millisecondsSinceEpoch)))
        .go();
    final overflow = await (database.select(database.coreLogs)
          ..orderBy([
            (row) => OrderingTerm.desc(row.at),
            (row) => OrderingTerm.desc(row.sequence),
            (row) => OrderingTerm.desc(row.id)
          ])
          ..limit(1, offset: CoreLogRepository.maxEntries))
        .getSingleOrNull();
    if (overflow != null) {
      await (database.delete(database.coreLogs)
            ..where((row) =>
                row.at.isSmallerThanValue(overflow.at) |
                (row.at.equals(overflow.at) &
                    (row.sequence.isSmallerThanValue(overflow.sequence) |
                        (row.sequence.equals(overflow.sequence) &
                            row.id.isSmallerOrEqualValue(overflow.id))))))
          .go();
    }
  }

  @override
  Future<void> clear() => database.delete(database.coreLogs).go();
}
