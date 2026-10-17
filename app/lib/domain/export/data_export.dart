import '../core/core_telemetry.dart';
import '../connection/traffic_history.dart';

abstract interface class DataExportService {
  /// Returns the actual file path/content URI, or null when the user cancels.
  Future<String?> save(
      {required String suggestedName, required String content});
}

/// Quote every field and neutralize spreadsheet formulas from untrusted domains.
String csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^\s*[=+\-@]').hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

String _csv(List<List<Object?>> rows) =>
    '\uFEFF${rows.map((row) => row.map(csvCell).join(',')).join('\r\n')}\r\n';

String connectionsCsv(
        ConnectionsSnapshot snapshot, List<CoreConnection> entries) =>
    _csv([
      ['采样时间', '目标地址', '协议', '进程', '匹配规则', '出站', '上传字节', '下载字节', '开始时间'],
      for (final entry in entries)
        [
          snapshot.at.toIso8601String(),
          entry.destination,
          entry.network,
          entry.process.isEmpty ? '未知' : entry.process,
          entry.rule,
          entry.direct ? '直连' : entry.outbound,
          entry.upload,
          entry.download,
          entry.startedAt.toIso8601String()
        ],
    ]);

String logsCsv(List<CoreLogEntry> entries) => _csv([
      ['时间', '级别', '来源', '事件'],
      for (final entry in entries)
        [
          entry.at.toIso8601String(),
          entry.level.label,
          entry.source,
          entry.message
        ],
    ]);

/// Separate row categories prevent daily totals and detailed buckets from being
/// accidentally interpreted as additional traffic. All byte values are exact.
String trafficCsv(TrafficPeriodView view) => _csv([
      ['日期', '记录类型', '时段', '归属类型', '目标', '上传字节', '下载字节', '总字节'],
      for (final day in view.report.days)
        [
          trafficDayKey(day.day),
          '日汇总',
          '',
          '',
          '',
          day.upload,
          day.download,
          day.total
        ],
      for (final bucket in view.buckets)
        [
          bucket.day,
          '时段明细',
          bucket.label,
          '',
          '',
          bucket.upload,
          bucket.download,
          bucket.total
        ],
      for (final item in view.ranking)
        [
          '${trafficDayKey(view.report.days.first.day)}~${trafficDayKey(view.report.days.last.day)}',
          '周期归属',
          '',
          item.target.kind,
          item.target.name,
          item.upload,
          item.download,
          item.total
        ],
    ]);
