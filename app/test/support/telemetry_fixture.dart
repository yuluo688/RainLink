// Isolated telemetry fixtures; no production import is permitted.
import 'dart:async';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/export/data_export.dart';

final telemetryFixtureAt = DateTime(2026, 10, 16, 10, 42, 29, 158);

List<CoreConnection> telemetryFixtureConnections() => [
      for (var i = 0; i < 6; i++)
        CoreConnection(
            id: 'fixture-$i',
            destination: [
              'api.github.com:443',
              'registry.npmjs.org:443',
              'developer.apple.com:443',
              '192.168.1.1:80',
              'docs.rs:443',
              'api.example.test:443'
            ][i],
            network: 'tcp',
            process: ['代码编辑器', '终端', '浏览器'][i % 3],
            rule: i == 3
                ? 'ip_is_private=true => direct'
                : 'clash_mode=rule => proxy',
            outbound: i == 3 ? 'direct' : 'proxy',
            direct: i == 3,
            upload: (i + 1) * 1024,
            download: (i + 1) * 1024 * 1024,
            startedAt: telemetryFixtureAt.subtract(Duration(seconds: 20 + i))),
    ];

List<CoreLogEntry> telemetryFixtureLogs() => [
      for (var i = 0; i < 8; i++)
        CoreLogEntry(
            id: 'fixture:${i + 1}',
            sequence: i + 1,
            at: telemetryFixtureAt.subtract(Duration(seconds: 11 - i)),
            level: i == 4
                ? CoreLogLevel.warning
                : i == 6
                    ? CoreLogLevel.error
                    : CoreLogLevel.info,
            source: 'core',
            message: [
              '网络核心已连接',
              'DNS 解析器就绪 · 使用系统解析',
              '核心监听已启动',
              'TCP · 连接至 api.github.com:443',
              '出口检测超时，保留当前连接',
              'TCP · 连接至 docs.rs:443',
              '网络请求失败 · 目标响应超时',
              '代理模式已切换为规则'
            ][i]),
    ];

class FixtureTelemetryGateway implements CoreTelemetryGateway {
  var entries = telemetryFixtureConnections();
  var logEntries = telemetryFixtureLogs();
  final closed = <String?>[];
  int reads = 0;
  int logClears = 0;
  int logCursor = 8;
  Future<ConnectionsSnapshot> Function(String)? onConnections;
  Future<CoreLogBatch> Function(String, int)? onLogs;
  Exception? closeFailure;

  @override
  Future<ConnectionsSnapshot> connections({required String sessionId}) {
    reads++;
    final handler = onConnections;
    if (handler != null) return handler(sessionId);
    return Future.value(ConnectionsSnapshot(
        sessionId: sessionId,
        at: telemetryFixtureAt,
        uploadTotal: 4200,
        downloadTotal: 20000000,
        entries: List.of(entries)));
  }

  @override
  Future<void> closeConnections(
      {required String sessionId, String? connectionId}) async {
    if (closeFailure case final failure?) throw failure;
    closed.add(connectionId);
    entries.removeWhere(
        (entry) => connectionId == null || entry.id == connectionId);
  }

  @override
  Future<CoreLogBatch> logs({String stream = '', int after = 0}) async {
    final handler = onLogs;
    if (handler != null) return handler(stream, after);
    return CoreLogBatch(
        stream: 'fixture',
        cursor: logCursor,
        more: false,
        dropped: false,
        entries: logEntries
            .where((entry) => stream != 'fixture' || entry.sequence > after)
            .toList());
  }

  @override
  Future<CoreLogBatch> clearLogs() async {
    logClears++;
    logEntries.clear();
    return CoreLogBatch(
        stream: 'fixture',
        cursor: logCursor,
        more: false,
        dropped: false,
        entries: const []);
  }
}

class FixtureDataExporter implements DataExportService {
  String? name;
  String? content;
  @override
  Future<String?> save(
      {required String suggestedName, required String content}) async {
    name = suggestedName;
    this.content = content;
    return 'fixture/exports/$suggestedName';
  }
}

class FixtureLogRepository implements CoreLogRepository {
  List<CoreLogEntry> entries = [];
  final _changes = StreamController<List<CoreLogEntry>>.broadcast();
  @override
  Stream<List<CoreLogEntry>> watch() => Stream.multi((controller) {
        controller.add(List.of(entries));
        final subscription = _changes.stream
            .listen(controller.add, onError: controller.addError);
        controller.onCancel = subscription.cancel;
      });
  @override
  Future<void> append(List<CoreLogEntry> values) async {
    final byId = {
      for (final entry in [...entries, ...values]) entry.id: entry
    };
    entries = byId.values.toList();
    _changes.add(List.of(entries));
  }

  @override
  Future<void> prune() async {}
  @override
  Future<void> clear() async {
    entries = [];
    _changes.add([]);
  }

  Future<void> dispose() => _changes.close();
}
