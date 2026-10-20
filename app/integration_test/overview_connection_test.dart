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
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/design_system/widgets/page_frame.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/features/overview/presentation/overview_page.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import 'support/local_proxy_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'overview shows a real proxied request and opens its close control',
    (tester) async {
      await initializeDesktopWindow();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(960, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final output = Directory(
        const String.fromEnvironment(
          'RAINLINK_VISUAL_OUTPUT',
          defaultValue: '../build/qa/overview-connection',
        ),
      );
      await output.create(recursive: true);
      final database = AppDatabase(NativeDatabase.memory());
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final responses = <HttpResponse>[];
      final serving = origin.listen((request) async {
        request.response.bufferOutput = false;
        if (request.uri.path == '/receipt') {
          request.response.write('RainLink overview connection receipt\n');
          await request.response.close();
          return;
        }
        responses.add(request.response);
        request.response.write('RainLink held overview stream\n');
        await request.response.flush();
        // Keep the real core connection observable until the UI closes it.
      });
      final hits = <String>[];
      final sockets = <Socket>{};
      final proxy = await LocalProxyFixture.start('overview-qa', hits, sockets);
      final client = HttpClient();
      final router = createRouter();
      final captureKey = GlobalKey();
      ProviderContainer? container;
      SessionGateway? gateway;
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: ProviderScope(
              overrides: [
                ...createAppOverrides(
                  database: database,
                  initialTheme: AppTheme.dark,
                ),
                desktopIntegrationProvider.overrideWithValue(null),
              ],
              child: RainlinkApp(router: router),
            ),
          ),
        );
        await tester.pumpAndSettle();
        container = ProviderScope.containerOf(
          tester.element(find.byType(RainlinkApp)),
        );
        final initialStatus = await container.read(coreStatusProvider.future);
        expect(
          initialStatus.capabilities.connect,
          isTrue,
          reason: initialStatus.message,
        );
        gateway = container.read(coreGatewayProvider) as SessionGateway;
        final node = await container
            .read(nodeRepositoryProvider)
            .save(
              NodeDraft(
                name: '本机概览验收',
                protocol: NodeProtocol.http,
                server: '127.0.0.1',
                port: proxy.server.port,
              ),
            );
        await container.read(nodeRepositoryProvider).select(node.id);
        container.read(proxyModeProvider.notifier).state = ProxyMode.global;
        for (
          var retry = 0;
          retry < 50 && container.read(selectedNodeProvider)?.id != node.id;
          retry++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(container.read(selectedNodeProvider)?.id, node.id);
        expect(container.read(sessionControllerProvider).systemProxy, isFalse);
        expect(container.read(sessionControllerProvider).tun, isFalse);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('connect-button')),
              )
              .onPressed,
          isNotNull,
        );
        await tester.tap(find.byKey(const ValueKey('connect-button')));
        for (
          var retry = 0;
          retry < 150 && !container.read(sessionControllerProvider).connected;
          retry++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final active = container.read(sessionControllerProvider).active;
        expect(
          container.read(sessionControllerProvider).connected,
          isTrue,
          reason: container.read(sessionControllerProvider).error,
        );
        expect(active, isNotNull);
        client.findProxy = (_) => 'PROXY 127.0.0.1:${active?.proxyPort}';
        final receiptRequest = await client
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/receipt'))
            .timeout(const Duration(seconds: 5));
        receiptRequest.persistentConnection = false;
        receiptRequest.headers.set('x-rainlink-qa', 'overview-receipt');
        final receiptResponse = await receiptRequest.close().timeout(
          const Duration(seconds: 5),
        );
        expect(receiptResponse.statusCode, HttpStatus.ok);
        final receipt = await receiptResponse
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 5));
        expect(receipt, 'RainLink overview connection receipt\n');
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/overview'))
            .timeout(const Duration(seconds: 5));
        request.headers.set('x-rainlink-qa', 'overview-held');
        final response = await request.close().timeout(
          const Duration(seconds: 5),
        );
        expect(response.statusCode, HttpStatus.ok);
        final closed = Completer<void>();
        response.listen(
          (_) {},
          onDone: () {
            if (!closed.isCompleted) closed.complete();
          },
          onError: (Object _) {
            if (!closed.isCompleted) closed.complete();
          },
        );
        expect(proxy.requestPaths['overview-receipt'], [
          'overview-qa>127.0.0.1:${origin.port}',
        ]);
        expect(proxy.requestPaths['overview-held'], [
          'overview-qa>127.0.0.1:${origin.port}',
        ]);
        await container.read(connectionsControllerProvider.notifier).refresh();
        await tester.pumpAndSettle();
        final observed = container.read(connectionsControllerProvider).recent;
        expect(observed?.destination, '127.0.0.1:${origin.port}');
        expect(observed?.direct, isFalse);
        expect(
          find.descendant(
            of: find.byType(OverviewPage),
            matching: find.byType(Scrollable),
          ),
          findsNothing,
        );
        final detail = find.byKey(const ValueKey('overview-recent-detail'));
        expect(
          tester.widget<Text>(detail).data,
          contains('127.0.0.1:${origin.port} · 代理'),
        );
        final viewport = tester.getRect(find.byType(PageFrame));
        expect(viewport.contains(tester.getRect(detail).bottomRight), isTrue);
        await _capture(captureKey, output, 'overview-960-real.png', tester);

        await tester.tap(
          find.byKey(const ValueKey('overview-all-connections')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭 127.0.0.1:${origin.port}'));
        await tester.pumpAndSettle();
        await closed.future.timeout(const Duration(seconds: 5));
        final afterClose = await (gateway as CoreTelemetryGateway).connections(
          sessionId: active?.sessionId ?? '',
        );
        expect(
          afterClose.entries.where((entry) => entry.id == observed?.id),
          isEmpty,
        );

        router.go('/overview');
        await tester.pumpAndSettle();
        // Closing a request does not erase the recent observation of this session.
        expect(
          tester.widget<Text>(detail).data,
          contains('127.0.0.1:${origin.port} · 代理'),
        );
        await tester.tap(find.byKey(const ValueKey('connect-button')));
        for (
          var retry = 0;
          retry < 100 &&
              container.read(sessionControllerProvider).phase !=
                  ConnectionPhase.idle;
          retry++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(
          container.read(sessionControllerProvider).phase,
          ConnectionPhase.idle,
        );
        expect(container.read(connectionsControllerProvider).recent, isNull);
        expect(tester.widget<Text>(detail).data, '连接后查看实际网络请求');
        await _capture(
          captureKey,
          output,
          'overview-960-disconnected-real.png',
          tester,
        );
        final status = await container.read(coreStatusProvider.future);
        await File('${output.path}/overview-real-evidence.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'platform': Platform.operatingSystem,
            'coreVersion': status.coreVersion,
            'viewport': {'width': 960, 'height': 640},
            'systemProxyChanged': false,
            'tunChanged': false,
            'inMemoryDatabase': true,
            'proxyOnlyForLoopback': true,
            'receipt': receipt,
            'observed': {
              'destination': observed?.destination,
              'outbound': observed?.outbound,
              'direct': observed?.direct,
              'startedAt': observed?.startedAt.toIso8601String(),
            },
            'requestClosedFromConnectionsUi': true,
            'recentClearedAfterDisconnect': true,
            'at': DateTime.now().toIso8601String(),
          }),
        );
        expect(tester.takeException(), isNull);
      } finally {
        client.close(force: true);
        if (gateway != null) {
          await gateway.disconnect();
          await gateway.close();
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await proxy.server.close();
        for (final response in responses) {
          await response.close();
        }
        await serving.cancel();
        await origin.close(force: true);
        await database.close();
      }
    },
  );
}

Future<void> _capture(
  GlobalKey key,
  Directory output,
  String name,
  WidgetTester tester,
) => tester.runAsync(() async {
  final boundary = key.currentContext?.findRenderObject();
  expect(boundary, isA<RenderRepaintBoundary>());
  final rendered = await (boundary as RenderRepaintBoundary).toImage(
    pixelRatio: 1,
  );
  try {
    final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Screenshot encoding failed');
    await File('${output.path}/$name').writeAsBytes(data.buffer.asUint8List());
  } finally {
    rendered.dispose();
  }
});
