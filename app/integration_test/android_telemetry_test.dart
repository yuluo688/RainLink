import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';

/// Separate from the visual fixtures: these actions use the actual Android
/// bridge, embedded core, SQLite collector and app-private file exporter.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android telemetry UI closes a real stream and exports real CSV',
      (tester) async {
    expect(Platform.isAndroid, isTrue);
    final database = AppDatabase(NativeDatabase.memory());
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final serving = origin.listen((request) async {
      request.response.write('RainLink held stream\n');
      await request.response.flush();
      // The HTTP response stays open until the core closes this actual stream.
    });
    final router = createRouter(initialLocation: '/connections');
    final capture = GlobalKey();
    final client = HttpClient();
    ProviderContainer? container;
    try {
      await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: ProviderScope(overrides: [
            ...createAppOverrides(
                database: database, initialTheme: AppTheme.dark),
            // Exercise actual file content without operating a system UI
            // from Flutter. The native document-picker test verifies SAF.
            dataExportServiceProvider
                .overrideWithValue(const FileDataExportService()),
          ], child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      for (var i = 0;
          i < 30 && container.read(sessionControllerProvider).working;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final session = container.read(sessionControllerProvider.notifier);
      final node = await container.read(nodeRepositoryProvider).save(
          const NodeDraft(
              name: 'Android 本机遥测验收',
              protocol: NodeProtocol.http,
              server: '127.0.0.1',
              port: 9,
              authenticate: true,
              username: 'fixture-user',
              password: 'fixture-password'));
      await session.connect(node, ProxyMode.direct);
      final active = container.read(sessionControllerProvider);
      expect(active.connected, isTrue, reason: active.error);
      expect(active.tun, isTrue);
      final proxyPort = active.active?.proxyPort;
      expect(proxyPort, isNotNull);
      client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
      final target = '127.0.0.1:${origin.port}';
      final response =
          await (await client.getUrl(Uri.parse('http://$target/held'))).close();
      expect(response.statusCode, 200);
      final closed = Completer<void>();
      response.listen((_) {}, onDone: () {
        if (!closed.isCompleted) closed.complete();
      }, onError: (Object _) {
        if (!closed.isCompleted) closed.complete();
      });
      final controller = container.read(connectionsControllerProvider.notifier);
      await controller.refresh();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), target);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final targetRow = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == target);
      expect(targetRow, findsOneWidget);
      await tester.tap(find.text('暂停刷新'));
      await tester.pumpAndSettle();
      final connectionCapture =
          await _capture(tester, capture, 'connections-real.png');
      final csvStarted = DateTime.now();
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();
      final connectionsCsv =
          await _exported(tester, 'RainLink-连接-', csvStarted);
      expect(connectionsCsv, contains(target));
      expect(connectionsCsv, contains('直连'));
      final close = find.byTooltip('关闭 $target');
      expect(closed.isCompleted, isFalse,
          reason: 'The actual stream ended before the UI close action');
      await tester.ensureVisible(close);
      await tester.tap(close);
      await tester.pumpAndSettle();
      await closed.future.timeout(const Duration(seconds: 3));
      expect(targetRow, findsNothing);
      await session.disconnect();
      final collector = container.read(coreLogCollectorProvider.notifier);
      await collector.collect();
      await collector.suspend();
      final repository = container.read(coreLogRepositoryProvider);
      final saved = await repository?.watch().first;
      final count = saved?.where((entry) => entry.source == 'core').length ?? 0;
      expect(count, greaterThan(0));
      router.go('/logs');
      await tester.pumpAndSettle();
      expect(find.text('暂无日志'), findsNothing);
      final logCapture = await _capture(tester, capture, 'logs-real.png');
      final logExportStarted = DateTime.now();
      await tester.tap(find.text('导出'));
      await tester.pumpAndSettle();
      final logsCsv = await _exported(tester, 'RainLink-日志-', logExportStarted);
      expect(logsCsv, contains('core'));
      expect(node.credential, isNotEmpty);
      expect(logsCsv, isNot(contains(node.credential)));
      expect(logsCsv, isNot(contains('fixture-password')));
      await tester.tap(find.text('清空'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '清空'));
      await tester.pumpAndSettle();
      expect(await repository?.watch().first, isEmpty);
      expect(tester.takeException(), isNull);
      binding.reportData = {
        ...?binding.reportData,
        'telemetry': {
          'scope':
              'Android UI and actual libbox using a localhost direct HTTP stream through the explicit local proxy; no remote subscription',
          'systemTunnelEstablished': true,
          'heldRequestClosedByUi': true,
          'coreLogEntries': count,
          'logsReadableAfterDisconnect': true,
          'connectionsCsvVerified': true,
          'logsCsvVerified': true,
          'confirmedClearVerified': true,
          'at': DateTime.now().toIso8601String(),
        },
        'telemetryCaptures': [connectionCapture, logCapture],
      };
    } finally {
      client.close(force: true);
      if (container != null) {
        await container.read(coreLogCollectorProvider.notifier).suspend();
        await container.read(coreGatewayProvider).disconnect();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      await origin.close(force: true);
      await serving.cancel();
      await database.close();
    }
  });
}

Future<String> _exported(
    WidgetTester tester, String prefix, DateTime after) async {
  final directory = await getApplicationDocumentsDirectory();
  final output = Directory('${directory.path}/exports');
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    final files = await output.list().where((item) => item is File).toList();
    for (final file in files.cast<File>()) {
      final name = file.uri.pathSegments.last;
      if (!name.startsWith(prefix) || !name.endsWith('.csv')) continue;
      // Some Android filesystems round mtime. The export's own millisecond name
      // identifies a file created by this action without accepting an old CSV.
      final timestamp =
          int.tryParse(name.substring(prefix.length, name.length - 4));
      if (timestamp != null && timestamp >= after.millisecondsSinceEpoch) {
        final content = await file.readAsString();
        if (content.endsWith('\r\n')) return content;
      }
    }
  }
  throw StateError('The UI did not produce the expected CSV file');
}

Future<Map<String, Object?>> _capture(
        WidgetTester tester, GlobalKey key, String filename) async =>
    await tester.runAsync(() async {
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        throw StateError('Missing Android render capture boundary');
      }
      final rendered = await boundary.toImage(pixelRatio: 1);
      try {
        final png = await rendered.toByteData(format: ui.ImageByteFormat.png);
        if (png == null) throw StateError('Screenshot encoding failed');
        return <String, Object?>{
          'file': filename,
          'width': rendered.width,
          'height': rendered.height,
          'png': base64Encode(png.buffer.asUint8List()),
        };
      } finally {
        rendered.dispose();
      }
    }) ??
    (throw StateError('Android screenshot capture did not complete'));
