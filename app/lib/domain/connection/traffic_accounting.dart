import 'traffic_repository.dart';

const maximumTrafficCounter = 9007199254740991;

class TrafficCounter extends DailyTraffic {
  const TrafficCounter({required this.target, super.upload, super.download});
  final TrafficAttribution target;
}

/// Two independent partitions of the same core counters. Neither destinations
/// nor full process paths are needed for persistent usage statistics.
class TrafficAccountingSnapshot extends DailyTraffic {
  const TrafficAccountingSnapshot({
    required this.sessionId,
    required this.epoch,
    required this.sampledAt,
    required super.upload,
    required super.download,
    required this.targets,
    required this.applications,
    this.limited = false,
  });
  final String sessionId;
  final String epoch;
  final DateTime sampledAt;
  final bool limited;
  final List<TrafficCounter> targets;
  final List<TrafficCounter> applications;

  void validate() {
    final identifier = RegExp(r'^[a-zA-Z0-9_-]{1,128}$');
    final controls = RegExp(r'[\x00-\x1F\x7F-\x9F]');
    bool counter(int value) => value >= 0 && value <= maximumTrafficCounter;
    if (!identifier.hasMatch(sessionId) ||
        !identifier.hasMatch(epoch) ||
        sampledAt.millisecondsSinceEpoch <= 0 ||
        !counter(upload) ||
        !counter(download) ||
        targets.length > 35 ||
        applications.length > 128) {
      throw const FormatException('流量计数无效');
    }
    void partition(List<TrafficCounter> rows, bool application) {
      var up = 0, down = 0;
      final seen = <String>{};
      for (final row in rows) {
        final target = row.target;
        if (!counter(row.upload) ||
            !counter(row.download) ||
            !identifier.hasMatch(target.id) ||
            !(application
                ? target.kind == 'application'
                : {
                  'node',
                  'chain',
                  'direct',
                  'unknown',
                }.contains(target.kind)) ||
            !seen.add('${target.kind}:${target.id}') ||
            target.name.trim().isEmpty ||
            target.name.runes.length > 128 ||
            controls.hasMatch(target.name) ||
            application && target.name.contains(RegExp(r'[/\\]'))) {
          throw const FormatException('流量归属无效');
        }
        up += row.upload;
        down += row.download;
      }
      if (up != upload || down != download) {
        throw const FormatException('流量归属与总计不一致');
      }
    }

    partition(targets, false);
    partition(applications, true);
  }
}

abstract interface class TrafficAccountingRepository
    implements TrafficRepository {
  Future<void> recordAccounting(TrafficAccountingSnapshot snapshot);
}
