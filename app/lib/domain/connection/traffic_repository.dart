class DailyTraffic {
  const DailyTraffic({this.upload = 0, this.download = 0});
  final int upload;
  final int download;
  int get total => upload + download;
}

class TrafficDay extends DailyTraffic {
  const TrafficDay({required this.day, super.upload, super.download});
  final DateTime day;
}

enum TrafficPeriod { today, week, month }

class TrafficReport extends DailyTraffic {
  const TrafficReport(
      {required this.days, required super.upload, required super.download});
  final List<TrafficDay> days;

  factory TrafficReport.fromDays(
      List<TrafficDay> records, TrafficPeriod period, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (period) {
      TrafficPeriod.today => today,
      TrafficPeriod.week =>
        DateTime(now.year, now.month, now.day - now.weekday + 1),
      TrafficPeriod.month => DateTime(now.year, now.month),
    };
    final days = <TrafficDay>[];
    var up = 0;
    var down = 0;
    // Calendar arithmetic avoids 23/25-hour daylight-saving days.
    for (var day = start;
        !day.isAfter(today);
        day = DateTime(day.year, day.month, day.day + 1)) {
      final match = records.where((record) => record.day == day).firstOrNull;
      final item = match ?? TrafficDay(day: day);
      days.add(item);
      up += item.upload;
      down += item.download;
    }
    return TrafficReport(
        days: List.unmodifiable(days), upload: up, download: down);
  }
}

abstract interface class TrafficRepository {
  Stream<DailyTraffic> watchToday();
  Stream<List<TrafficDay>> watchHistory();
  Future<void> record(String sessionId, int uploadTotal, int downloadTotal,
      {TrafficAttribution attribution = TrafficAttribution.unassigned});
}

/// Attribution is conservative: unknown traffic is never assigned to a node.
class TrafficAttribution {
  const TrafficAttribution(
      {required this.id, required this.name, required this.kind});
  static const unassigned =
      TrafficAttribution(id: 'unassigned', name: '未归属流量', kind: 'unknown');
  static const direct =
      TrafficAttribution(id: 'direct', name: '直连', kind: 'direct');
  final String id;
  final String name;
  final String kind;
}
