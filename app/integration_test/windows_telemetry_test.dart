import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Windows telemetry UI closes real requests, collects logs and saves CSV',
      (tester) async {
    await initializeDesktopWindow();
    final database = AppDatabase(NativeDatabase.memory());
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final responses = <HttpResponse>[];
    final serving = origin.listen((request) async {
      responses.add(request.response);
      request.response.write('RainLink held stream\n');
      await request.response.flush();
      // Keep this request open until the core is told to close its connection.
    });
    final router = createRouter(initialLocation: '/connections');
    final client = HttpClient();
    ProviderContainer? container;
    try {
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final session = container.read(sessionControllerProvider.notifier);
      final node = await container.read(nodeRepositoryProvider).save(
          const NodeDraft(
              name: '本机遥测验收',
              protocol: NodeProtocol.http,
              server: '127.0.0.1',
              port: 9));
      await session.connect(node, ProxyMode.direct);
      expect(container.read(sessionControllerProvider).connected, isTrue,
          reason: container.read(sessionControllerProvider).error);
      final gateway = container.read(coreGatewayProvider);
      final observation = await (gateway as SessionGateway).observe();
      final port = observation.active?.proxyPort;
      expect(port, isNotNull);
      client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
      final url = Uri.parse('http://127.0.0.1:${origin.port}/held');
      final request = await client.getUrl(url);
      final response = await request.close();
      expect(response.statusCode, 200);
      final requestClosed = Completer<void>();
      response.listen((_) {}, onDone: () {
        if (!requestClosed.isCompleted) requestClosed.complete();
      }, onError: (Object _) {
        if (!requestClosed.isCompleted) requestClosed.complete();
      });
      await container.read(connectionsControllerProvider.notifier).refresh();
      await tester.pumpAndSettle();
      final target = '127.0.0.1:${origin.port}';
      await tester.enterText(find.byType(TextField), target);
      await tester.pumpAndSettle();
      final targetRow = find.byWidgetPredicate(
          (widget) => widget is Text && widget.data == target);
      expect(targetRow, findsOneWidget);
      await tester.tap(find.text('暂停刷新'));
      await tester.pumpAndSettle();
      final output = Directory('../docs/verification/telemetry');
      await output.create(recursive: true);
      final csvPath =
          '${output.absolute.path}/connections-real-${DateTime.now().millisecondsSinceEpoch}.csv';
      final helper = await Process.start('python', [
        '../tools/complete_export_dialog.py',
        '--pid',
        '$pid',
        '--path',
        csvPath
      ]);
      final helperOutput = helper.stderr.transform(utf8.decoder).join();
      await tester.tap(find.text('导出'));
      for (var i = 0; i < 100 && !await File(csvPath).exists(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(await helper.exitCode.timeout(const Duration(seconds: 25)), 0,
          reason: await helperOutput);
      expect(await File(csvPath).exists(), isTrue);
      final csv = await File(csvPath).readAsString();
      expect(csv, contains(target));
      expect(csv, contains('直连'));
      await tester.pumpAndSettle();
      final capture = await Process.run('python', [
        '../tools/capture_window.py',
        '--pid',
        '$pid',
        '--output',
        '${output.path}/connections-real.png'
      ]);
      expect(capture.exitCode, 0, reason: capture.stderr.toString());
      await tester.tap(find.byTooltip('关闭 $target'));
      await tester.pumpAndSettle();
      await requestClosed.future.timeout(const Duration(seconds: 3));
      expect(targetRow, findsNothing);
      final telemetry = gateway as CoreTelemetryGateway;
      final active = container.read(sessionControllerProvider).active;
      final connections =
          await telemetry.connections(sessionId: active?.sessionId ?? '');
      expect(connections.entries.where((entry) => entry.destination == target),
          isEmpty);
      await container.read(coreLogCollectorProvider.notifier).collect();
      final saved =
          await container.read(coreLogRepositoryProvider)?.watch().first;
      expect(saved?.where((entry) => entry.source == 'core'), isNotEmpty);
      router.go('/logs');
      await tester.pumpAndSettle();
      expect(find.text('暂无日志'), findsNothing);
      final logCapture = await Process.run('python', [
        '../tools/capture_window.py',
        '--pid',
        '$pid',
        '--output',
        '${output.path}/logs-real.png'
      ]);
      expect(logCapture.exitCode, 0, reason: logCapture.stderr.toString());
      await session.disconnect();
      expect(container.read(sessionControllerProvider).phase,
          ConnectionPhase.idle);
      await File('${output.path}/windows-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'scenario':
            'isolated localhost HTTP stream through the bundled sing-box',
        'systemProxyChanged': false,
        'heldRequestClosedByUi': true,
        'coreLogEntries':
            saved?.where((entry) => entry.source == 'core').length,
        'nativeSaveDialogAndFileVerified': true,
        'csvPath': csvPath,
        'at': DateTime.now().toIso8601String(),
      }));
    } finally {
      client.close(force: true);
      if (container != null) {
        container.read(coreLogCollectorProvider.notifier).pause();
        final gateway = container.read(coreGatewayProvider);
        await gateway.disconnect();
        if (gateway is SessionGateway) await gateway.close();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      for (final response in responses) {
        await response.close();
      }
      await serving.cancel();
      await origin.close(force: true);
      await database.close();
    }
  });
}
