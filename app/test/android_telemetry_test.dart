import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/platform/core/android_core_gateway.dart';

Map<String, Object?> connectionPage({int cursor = 0}) => {
      'sessionId': 'session',
      'snapshotId': 'snapshot',
      'sampledAt': 1792140000158,
      'uploadTotal': 100,
      'downloadTotal': 200,
      'total': 3,
      'next': cursor == 0 ? 2 : -1,
      'entries': [
        for (var i = cursor; i < (cursor == 0 ? 2 : 3); i++)
          <String, Object?>{
            'id': 'stream-$i',
            'destination': 'example.test:443',
            'network': 'tcp',
            'process': '',
            'rule': 'clash_mode=global => proxy',
            'outbound': '当前节点',
            'direct': false,
            'upload': 20,
            'download': 40,
            'startedAt': 1792140000158,
          },
      ],
    };

Map<String, Object?> logBatch({bool empty = false}) => {
      'stream': 'native-logs',
      'cursor': 1,
      'more': false,
      'dropped': false,
      'entries': [
        if (!empty)
          <String, Object?>{
            'id': 'native-logs:1',
            'seq': 1,
            'at': 1792140000158,
            'level': 'info',
            'source': 'core',
            'message': '真实核心日志 [认证已隐藏]',
          },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rainlink/telemetry-test');
  late AndroidCoreGateway gateway;
  final calls = <MethodCall>[];
  late Future<String> Function(MethodCall) respond;
  final invalidResponse = throwsA(isA<CoreGatewayException>()
      .having((error) => error.code, 'code', 'invalid_response'));

  setUp(() {
    calls.clear();
    gateway = AndroidCoreGateway(channel: channel);
    respond = (call) async {
      final args = jsonDecode(call.arguments as String) as Map<String, Object?>;
      return jsonEncode(connectionPage(cursor: args['cursor'] as int? ?? 0));
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
  });
  tearDown(() {
    gateway.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android joins stable connection pages without inventing processes',
      () async {
    expect(gateway, isA<CoreTelemetryGateway>());
    final result = await gateway.connections(sessionId: 'session');
    expect(result.entries.map((entry) => entry.id),
        ['stream-0', 'stream-1', 'stream-2']);
    expect(result.entries.every((entry) => entry.process.isEmpty), isTrue);
    expect(result.uploadTotal, 100);
    expect(result.downloadTotal, 200);
    expect(calls.every((call) => call.method == 'connections'), isTrue);
    expect(jsonDecode(calls.last.arguments as String), {
      'sessionId': 'session',
      'snapshotId': 'snapshot',
      'cursor': 2,
    });
  });

  for (final field in <String, Object?>{
    'sessionId': 'other-session',
    'snapshotId': 'other-snapshot',
    'sampledAt': 1792140000159,
    'total': 4,
    'uploadTotal': 101,
    'downloadTotal': 201,
    'next': 2,
    'entries': <Object?>[],
  }.entries) {
    test('Android rejects moving page field ${field.key}', () async {
      respond = (call) async {
        final args =
            jsonDecode(call.arguments as String) as Map<String, Object?>;
        final cursor = args['cursor'] as int;
        return jsonEncode({
          ...connectionPage(cursor: cursor),
          if (cursor != 0) field.key: field.value,
        });
      };
      await expectLater(
          gateway.connections(sessionId: 'session'), invalidResponse);
    });
  }

  test('Android rejects stale first page and bounds snapshot size', () async {
    await expectLater(
        gateway.connections(sessionId: 'old'),
        throwsA(isA<CoreGatewayException>()
            .having((error) => error.code, 'code', 'session_changed')));
    respond = (_) async => jsonEncode({...connectionPage(), 'total': 100001});
    await expectLater(
        gateway.connections(sessionId: 'session'), invalidResponse);
  });

  test('Android rejects repeated IDs across connection pages', () async {
    respond = (call) async {
      final args = jsonDecode(call.arguments as String) as Map<String, Object?>;
      final cursor = args['cursor'] as int;
      final page = connectionPage(cursor: cursor);
      if (cursor != 0) {
        ((page['entries'] as List).single as Map<String, Object?>)['id'] =
            'stream-0';
      }
      return jsonEncode(page);
    };
    await expectLater(
        gateway.connections(sessionId: 'session'), invalidResponse);
  });

  test('Android scopes close commands and propagates unconfirmed failure',
      () async {
    respond = (_) async => '{}';
    await gateway.closeConnections(sessionId: 'session', connectionId: 'id');
    expect(calls.last.method, 'closeConnections');
    expect(jsonDecode(calls.last.arguments as String),
        {'sessionId': 'session', 'connectionId': 'id', 'all': false});
    await gateway.closeConnections(sessionId: 'session');
    expect(jsonDecode(calls.last.arguments as String),
        {'sessionId': 'session', 'connectionId': '', 'all': true});
    respond = (_) async =>
        throw PlatformException(code: 'native_failed', message: '核心未确认关闭连接');
    await expectLater(
        gateway.closeConnections(sessionId: 'session'),
        throwsA(isA<CoreGatewayException>()
            .having((error) => error.message, 'message', contains('未确认'))));
  });

  test('Android logs and clearing work without a connected UI session',
      () async {
    respond =
        (call) async => jsonEncode(logBatch(empty: call.method == 'clearLogs'));
    final batch = await gateway.logs(stream: 'native-logs', after: 0);
    expect(batch.entries.single.message, contains('核心日志'));
    expect(jsonDecode(calls.last.arguments as String),
        {'stream': 'native-logs', 'after': 0});
    final checkpoint = await gateway.clearLogs();
    expect(checkpoint.stream, batch.stream);
    expect(checkpoint.cursor, batch.cursor);
    expect(checkpoint.entries, isEmpty);
    expect(calls.last.method, 'clearLogs');
    expect(calls.any((call) => call.method == 'connect'), isFalse);
  });

  test('Android rejects malformed log checkpoints', () async {
    respond = (_) async => jsonEncode({...logBatch(), 'cursor': -1});
    await expectLater(gateway.logs(), invalidResponse);
    respond = (_) async => jsonEncode({...logBatch(empty: true), 'stream': ''});
    await expectLater(gateway.clearLogs(), invalidResponse);
  });

  test('disposing the UI stops telemetry requests without stopping the service',
      () async {
    gateway.dispose();
    await expectLater(gateway.logs(), throwsA(isA<CoreGatewayException>()));
    await expectLater(gateway.connections(sessionId: 'session'),
        throwsA(isA<CoreGatewayException>()));
    expect(calls, isEmpty);
  });
}
