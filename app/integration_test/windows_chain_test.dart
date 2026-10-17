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
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/routing/routing_pending.dart';
import 'package:rainlink/data/chains/chain_records.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import 'support/local_proxy_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Windows saves a visual chain, connects from overview and applies reverse order after reconnect',
      (tester) async {
    await initializeDesktopWindow();
    final database = AppDatabase(NativeDatabase.memory());
    final hits = <String>[];
    final sockets = <Socket>{};
    final first = await LocalProxyFixture.start('A', hits, sockets);
    final second = await LocalProxyFixture.start('B', hits, sockets);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var subscriptionRequests = 0;
    origin.listen((request) async {
      if (request.uri.path == '/subscription') {
        subscriptionRequests++;
        request.response.write('http://edge.example.test:8080#Pipeline');
      } else {
        request.response.write('two-hop-payload');
      }
      await request.response.close();
    });
    final router = createRouter(initialLocation: '/chain');
    ProviderContainer? container;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final output = Directory('../docs/verification/chains');
    await output.create(recursive: true);
    try {
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final nodes = container.read(nodeRepositoryProvider);
      final a = await nodes.save(NodeDraft(
          name: '本地入口 HTTP',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: first.server.port));
      final b = await nodes.save(NodeDraft(
          name: '本地出口 HTTP',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: second.server.port));
      await tester.pumpAndSettle();
      Future<void> add(String id) async {
        await tester.ensureVisible(find.byKey(const ValueKey('chain-add-hop')));
        await tester.tap(find.byKey(const ValueKey('chain-add-hop')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('chain-pick-$id')));
        await tester.pumpAndSettle();
      }

      await add(a.id);
      await add(b.id);
      final name = find.byType(TextFormField).first;
      await tester.ensureVisible(name);
      await tester.enterText(name, '本地双跳验收');
      await tester.ensureVisible(find.byKey(const ValueKey('chain-save')));
      await tester.tap(find.byKey(const ValueKey('chain-save')));
      await tester.pumpAndSettle();
      final saved = (await loadChains(database)).single;
      expect(saved.hopIds, [a.id, b.id]);
      expect(container.read(sessionControllerProvider).connected, isFalse);
      expect(await nodes.watchSelectedId().first, isNull);
      router.go('/overview');
      await tester.pumpAndSettle();
      container.read(proxyModeProvider.notifier).state = ProxyMode.global;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      await tester.pumpAndSettle();
      var view = container.read(sessionControllerProvider);
      expect(view.connected, isTrue, reason: view.error);
      expect(view.active?.target.kind, 'chain');
      expect(view.active?.routeBindings['proxy/hop/0']?.id, a.id);
      Future<void> request() async {
        final live = container!.read(sessionControllerProvider).active;
        client.findProxy = (_) => 'PROXY 127.0.0.1:${live?.proxyPort}';
        final req =
            await client.getUrl(Uri.parse('http://127.0.0.1:${origin.port}/'));
        req.headers.set(HttpHeaders.connectionHeader, 'close');
        final res = await req.close().timeout(const Duration(seconds: 4));
        expect(
            await res
                .transform(utf8.decoder)
                .join()
                .timeout(const Duration(seconds: 4)),
            'two-hop-payload');
      }

      try {
        await request();
      } on Exception {
        final telemetry =
            container.read(coreGatewayProvider) as CoreTelemetryGateway;
        final logs = await telemetry.logs();
        await File('${output.path}/fixture-debug.json')
            .writeAsString(jsonEncode({
          'ports': [
            first.server.port,
            second.server.port,
            origin.port,
            view.active?.proxyPort
          ],
          'mode': view.active?.mode.name,
          'hits': hits,
          'logs': logs.entries.map((entry) => entry.message).toList()
        }));
        rethrow;
      }
      expect(hits, contains('A>127.0.0.1:${second.server.port}'));
      expect(hits.lastWhere((hit) => hit.endsWith(':${origin.port}')),
          'B>127.0.0.1:${origin.port}');
      final originTunnels = second.accepted
          .where((target) => target.endsWith(':${origin.port}'))
          .length;
      final document = await container.read(subscriptionFetcherProvider).fetch(
          Uri.parse('http://127.0.0.1:${origin.port}/subscription'),
          SubscriptionCancellation());
      expect(document.nodes.single.name, 'Pipeline');
      expect(subscriptionRequests, 1);
      expect(
          second.accepted
              .where((target) => target.endsWith(':${origin.port}'))
              .length,
          originTunnels + 1,
          reason:
              'The production subscription adapter must use the live chain');
      final session = container.read(sessionControllerProvider.notifier);
      final originalSession = view.active?.sessionId;
      // Use the actual isolated host and cancel while the live session remains.
      final editor = container.read(chainEditorProvider.notifier);
      editor.load(saved);
      final testing = editor.test([a, b]);
      await editor.cancel();
      await testing;
      expect(container.read(chainEditorProvider).testing, isFalse);
      await session.refresh();
      expect(container.read(sessionControllerProvider).active?.sessionId,
          originalSession);
      final repository = container.read(chainRepositoryProvider);
      final reversed = await repository
          .save(ChainSnapshot(saved.copyWith(hopIds: [b.id, a.id]), [b, a]));
      await tester.pumpAndSettle();
      expect(container.read(routingPendingProvider), isTrue);
      await request();
      expect(hits.lastWhere((hit) => hit.endsWith(':${origin.port}')),
          'B>127.0.0.1:${origin.port}');
      await session.disconnect();
      await session.connectChain(reversed, ProxyMode.global);
      await tester.pumpAndSettle();
      await request();
      view = container.read(sessionControllerProvider);
      expect(view.active?.routeBindings['proxy/hop/0']?.id, b.id);
      expect(hits, contains('B>127.0.0.1:${first.server.port}'));
      expect(hits.lastWhere((hit) => hit.endsWith(':${origin.port}')),
          'A>127.0.0.1:${origin.port}');
      final capture = await Process.run('python', [
        '../tools/capture_window.py',
        '--pid',
        '$pid',
        '--output',
        '${output.path}/overview-real.png'
      ]);
      expect(capture.exitCode, 0, reason: capture.stderr.toString());
      await session.disconnect();
      await File('${output.path}/windows-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'at': DateTime.now().toIso8601String(),
        'scenario': 'localhost HTTP CONNECT fixtures with real bundled core',
        'uiSaveSelectedOnly': true,
        'connectedFromOverview': true,
        'forwardOrder': 'A -> B -> origin',
        'reverseAfterReconnect': 'B -> A -> origin',
        'liveSessionSurvivedTestCancellation': true,
        'editKeptActivePath': true,
        'subscriptionFetchedThroughActiveChain': true,
        'systemProxyChanged': false,
        'publicProbe': 'fixtures intentionally reject Internet targets'
      }));
    } finally {
      client.close(force: true);
      if (container != null) {
        final gateway = container.read(coreGatewayProvider);
        await gateway.disconnect();
        if (gateway is SessionGateway) await gateway.close();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      for (final socket in sockets) {
        socket.destroy();
      }
      await first.server.close();
      await second.server.close();
      await origin.close(force: true);
      await database.close();
    }
  });
}
