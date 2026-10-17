import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_telemetry.dart';

class ConnectionPage {
  const ConnectionPage(
      {required this.snapshot,
      required this.snapshotId,
      required this.total,
      required this.next});
  final ConnectionsSnapshot snapshot;
  final String snapshotId;
  final int total;
  final int next;
}

/// Reject malformed telemetry at the platform boundary instead of fabricating data.
abstract final class CoreTelemetryProtocol {
  static Never _invalid() =>
      throw const CoreGatewayException('invalid_response', '核心遥测响应格式无效');

  static String _text(Map<String, Object?> data, String key, int limit) {
    final value = data[key];
    if (value is! String || value.length > limit) _invalid();
    return value;
  }

  static int _number(Map<String, Object?> data, String key, {int minimum = 0}) {
    final value = data[key];
    if (value is! int || value < minimum || value > 9007199254740991) {
      _invalid();
    }
    return value;
  }

  static DateTime _time(Map<String, Object?> data, String key) {
    final value = _number(data, key);
    if (value > 8640000000000000) _invalid();
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  static List<Map<String, Object?>> _entries(Map<String, Object?> data) {
    final value = data['entries'];
    if (value is! List<Object?> || value.length > 100) _invalid();
    return value.map((entry) {
      if (entry is! Map<String, Object?>) _invalid();
      return entry;
    }).toList();
  }

  static ConnectionPage connections(Map<String, Object?> data) {
    final entries = _entries(data).map((entry) {
      final direct = entry['direct'];
      if (direct is! bool) _invalid();
      return CoreConnection(
        id: _text(entry, 'id', 128),
        destination: _text(entry, 'destination', 600),
        network: _text(entry, 'network', 32),
        process: _text(entry, 'process', 200),
        rule: _text(entry, 'rule', 400),
        outbound: _text(entry, 'outbound', 200),
        direct: direct,
        upload: _number(entry, 'upload'),
        download: _number(entry, 'download'),
        startedAt: _time(entry, 'startedAt'),
      );
    }).toList();
    if (entries.any((entry) => entry.id.isEmpty) ||
        entries.map((entry) => entry.id).toSet().length != entries.length) {
      _invalid();
    }
    final total = _number(data, 'total');
    if (total < entries.length) _invalid();
    return ConnectionPage(
      snapshot: ConnectionsSnapshot(
        sessionId: _text(data, 'sessionId', 128),
        at: _time(data, 'sampledAt'),
        uploadTotal: _number(data, 'uploadTotal'),
        downloadTotal: _number(data, 'downloadTotal'),
        entries: List.unmodifiable(entries),
      ),
      snapshotId: _text(data, 'snapshotId', 128),
      total: total,
      next: _number(data, 'next', minimum: -1),
    );
  }

  /// Both transports collect one stable snapshot; moving core counters or rows
  /// from another sample must not be merged into the current list.
  static Future<ConnectionsSnapshot> readConnections({
    required String sessionId,
    required Future<Map<String, Object?>> Function(Map<String, Object?>)
        loadPage,
  }) async {
    var page =
        connections(await loadPage({'sessionId': sessionId, 'cursor': 0}));
    final first = page;
    if (first.snapshot.sessionId != sessionId || sessionId.isEmpty) {
      throw const CoreGatewayException('session_changed', '连接会话已改变，请刷新');
    }
    if (first.snapshotId.isEmpty || first.total > 100000) _invalid();
    final entries = [...page.snapshot.entries];
    while (page.next >= 0) {
      final next = page.next;
      if (next != entries.length || next == 0 || next >= first.total) {
        _invalid();
      }
      page = connections(await loadPage({
        'sessionId': sessionId,
        'snapshotId': first.snapshotId,
        'cursor': next,
      }));
      if (page.snapshotId != first.snapshotId ||
          page.total != first.total ||
          page.snapshot.sessionId != sessionId ||
          page.snapshot.at != first.snapshot.at ||
          page.snapshot.uploadTotal != first.snapshot.uploadTotal ||
          page.snapshot.downloadTotal != first.snapshot.downloadTotal ||
          page.snapshot.entries.isEmpty) {
        _invalid();
      }
      entries.addAll(page.snapshot.entries);
    }
    if (entries.length != first.total ||
        entries.map((entry) => entry.id).toSet().length != entries.length) {
      _invalid();
    }
    return ConnectionsSnapshot(
      sessionId: sessionId,
      at: first.snapshot.at,
      uploadTotal: first.snapshot.uploadTotal,
      downloadTotal: first.snapshot.downloadTotal,
      entries: List.unmodifiable(entries),
    );
  }

  static CoreLogBatch logs(Map<String, Object?> data) {
    final more = data['more'];
    final dropped = data['dropped'];
    if (more is! bool || dropped is! bool) _invalid();
    final entries = _entries(data).map((entry) {
      final level = _text(entry, 'level', 16);
      final parsed =
          CoreLogLevel.values.where((item) => item.name == level).firstOrNull;
      if (parsed == null) _invalid();
      return CoreLogEntry(
          id: _text(entry, 'id', 160),
          at: _time(entry, 'at'),
          level: parsed,
          source: _text(entry, 'source', 32),
          message: _text(entry, 'message', 2100),
          sequence: _number(entry, 'seq', minimum: 1));
    }).toList();
    if (more && entries.isEmpty) _invalid();
    final stream = _text(data, 'stream', 128);
    final cursor = _number(data, 'cursor');
    if (stream.isEmpty ||
        entries.any((entry) => entry.id != '$stream:${entry.sequence}')) {
      _invalid();
    }
    for (var i = 0; i < entries.length; i++) {
      if (entries[i].sequence > cursor ||
          (i > 0 && entries[i].sequence <= entries[i - 1].sequence)) {
        _invalid();
      }
    }
    return CoreLogBatch(
        stream: stream,
        cursor: cursor,
        more: more,
        dropped: dropped,
        entries: List.unmodifiable(entries));
  }
}
