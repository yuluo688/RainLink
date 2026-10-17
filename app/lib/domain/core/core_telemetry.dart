/// Observations from the running core. Missing process attribution stays unknown.
class CoreConnection {
  const CoreConnection({
    required this.id,
    required this.destination,
    required this.network,
    required this.process,
    required this.rule,
    required this.outbound,
    required this.direct,
    required this.upload,
    required this.download,
    required this.startedAt,
  });
  final String id;
  final String destination;
  final String network;
  final String process;
  final String rule;
  final String outbound;
  final bool direct;
  final int upload;
  final int download;
  final DateTime startedAt;

  bool matches(String query) {
    final text = '$destination $process $rule $outbound $network'.toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

class ConnectionsSnapshot {
  const ConnectionsSnapshot({
    this.sessionId = '',
    required this.at,
    this.uploadTotal = 0,
    this.downloadTotal = 0,
    this.entries = const [],
  });
  final String sessionId;
  final DateTime at;
  final int uploadTotal;
  final int downloadTotal;
  final List<CoreConnection> entries;
  int get proxyCount => entries.where((entry) => !entry.direct).length;
  int get directCount => entries.where((entry) => entry.direct).length;
}

enum CoreLogLevel {
  debug('调试'),
  info('信息'),
  warning('警告'),
  error('错误');

  const CoreLogLevel(this.label);
  final String label;
}

class CoreLogEntry {
  const CoreLogEntry(
      {required this.id,
      required this.at,
      required this.level,
      required this.source,
      required this.message,
      this.sequence = 0});
  final String id;
  final DateTime at;
  final CoreLogLevel level;
  final String source;
  final String message;
  final int sequence;

  bool matches(String query) {
    final text = '$message $source ${level.label}'.toLowerCase();
    return query
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .every(text.contains);
  }
}

class CoreLogBatch {
  const CoreLogBatch(
      {required this.stream,
      required this.cursor,
      required this.more,
      required this.dropped,
      required this.entries});
  final String stream;
  final int cursor;
  final bool more;
  final bool dropped;
  final List<CoreLogEntry> entries;
}

/// Optional platform capability, separate from the connection lifecycle interface.
abstract interface class CoreTelemetryGateway {
  Future<ConnectionsSnapshot> connections({required String sessionId});
  Future<void> closeConnections(
      {required String sessionId, String? connectionId});
  Future<CoreLogBatch> logs({String stream = '', int after = 0});
  Future<CoreLogBatch> clearLogs();
}

abstract interface class CoreLogRepository {
  static const retentionDays = 7;
  static const maxEntries = 5000;
  Stream<List<CoreLogEntry>> watch();
  Future<void> append(List<CoreLogEntry> entries);
  Future<void> prune();
  Future<void> clear();
}
