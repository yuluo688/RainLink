import 'traffic_repository.dart';

const trafficBucketMinutes = 15;

String trafficDayKey(DateTime at) => at.toIso8601String().substring(0, 10);

DateTime trafficPeriodStart(TrafficPeriod period, DateTime now) =>
    switch (period) {
      TrafficPeriod.today => DateTime(now.year, now.month, now.day),
      TrafficPeriod.week =>
        DateTime(now.year, now.month, now.day - now.weekday + 1),
      TrafficPeriod.month => DateTime(now.year, now.month),
    };

class TrafficBucket extends DailyTraffic {
  const TrafficBucket(
      {required this.day, required this.slot, super.upload, super.download});
  final String day;
  final int slot;
  String get label =>
      '${(slot * trafficBucketMinutes ~/ 60).toString().padLeft(2, '0')}:${(slot * trafficBucketMinutes % 60).toString().padLeft(2, '0')}';
}

class TrafficUsage extends DailyTraffic {
  const TrafficUsage(
      {required this.day, required this.target, super.upload, super.download});
  final String day;
  final TrafficAttribution target;
}

class TrafficArchive {
  const TrafficArchive(
      {this.days = const [], this.buckets = const [], this.usage = const []});
  final List<TrafficDay> days;
  final List<TrafficBucket> buckets;
  final List<TrafficUsage> usage;

  TrafficPeriodView forPeriod(TrafficPeriod period, DateTime now) {
    final report = TrafficReport.fromDays(days, period, now);
    final start = trafficDayKey(report.days.first.day);
    final end = trafficDayKey(report.days.last.day);
    bool within(String day) =>
        day.compareTo(start) >= 0 && day.compareTo(end) <= 0;
    final ranked = <String, TrafficUsage>{};
    for (final item in usage.where((item) => within(item.day))) {
      final key = '${item.target.kind}:${item.target.id}';
      final prior = ranked[key];
      ranked[key] = TrafficUsage(
          day: end,
          target: item.target,
          upload: (prior?.upload ?? 0) + item.upload,
          download: (prior?.download ?? 0) + item.download);
    }
    // Historic daily counters have no reliable target information. Preserve them
    // as unknown rather than assigning them to today's selected node.
    final knownUp = ranked.values.fold(0, (sum, item) => sum + item.upload);
    final knownDown = ranked.values.fold(0, (sum, item) => sum + item.download);
    if (knownUp < report.upload || knownDown < report.download) {
      const key = 'unknown:unassigned';
      final old = ranked[key];
      ranked[key] = TrafficUsage(
          day: end,
          target: TrafficAttribution.unassigned,
          upload: (old?.upload ?? 0) +
              (report.upload - knownUp).clamp(0, report.upload),
          download: (old?.download ?? 0) +
              (report.download - knownDown).clamp(0, report.download));
    }
    final ranking = ranked.values.where((item) => item.total > 0).toList()
      ..sort((a, b) {
        final total = b.total.compareTo(a.total);
        return total != 0 ? total : a.target.id.compareTo(b.target.id);
      });
    return TrafficPeriodView(
        report: report,
        buckets: List.unmodifiable(buckets.where((item) => within(item.day))),
        ranking: List.unmodifiable(ranking),
        observedDays: Set.unmodifiable(
            days.map((day) => trafficDayKey(day.day)).where(within)));
  }
}

class TrafficPeriodView {
  const TrafficPeriodView(
      {required this.report,
      required this.buckets,
      required this.ranking,
      this.observedDays = const {}});
  final TrafficReport report;
  final List<TrafficBucket> buckets;
  final List<TrafficUsage> ranking;
  final Set<String> observedDays;
}

abstract interface class TrafficArchiveRepository implements TrafficRepository {
  Stream<TrafficArchive> watchArchive(
      [TrafficPeriod period = TrafficPeriod.month]);
}
