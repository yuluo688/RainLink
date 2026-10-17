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
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/routing/route_rules.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

Future<ServerSocket> startFixtureProxy(
    String name, List<Socket> sockets) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    sockets.add(socket);
    var buffered = '';
    var replied = false;
    var connected = false;
    socket.listen((bytes) async {
      if (replied) return;
      buffered += latin1.decode(bytes);
      if (buffered.length > 8192) {
        socket.destroy();
        return;
      }
      if (!buffered.contains('\r\n\r\n')) return;
      if (!connected) {
        if (!buffered.startsWith('CONNECT ')) {
          socket.destroy();
          return;
        }
        connected = true;
        buffered = buffered.substring(buffered.indexOf('\r\n\r\n') + 4);
        socket.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await socket.flush();
        if (!buffered.contains('\r\n\r\n')) return;
      }
      replied = true;
      socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: ${name.length}\r\nConnection: close\r\n\r\n$name');
      await socket.flush();
      await socket.close();
    }, onError: (Object error) {
      socket.destroy();
    });
  });
  return server;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Windows edits and freezes real group rules across live mode changes',
      (tester) async {
    await initializeDesktopWindow();
    final database = AppDatabase(NativeDatabase.memory());
    final sockets = <Socket>[];
    final first = await startFixtureProxy('primary-proxy', sockets);
    final second = await startFixtureProxy('group-proxy', sockets);
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    origin.listen((request) async {
      request.response.write('direct-origin');
      await request.response.close();
    });
    final router = createRouter(initialLocation: '/rules');
    ProviderContainer? container;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final nodes = container.read(nodeRepositoryProvider);
      final primary = await nodes.save(NodeDraft(
          name: '默认测试节点',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: first.port));
      final groupNode = await nodes.save(NodeDraft(
          name: '组内记忆节点',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: second.port));
      final groups = container.read(groupRepositoryProvider);
      final group = await groups.createManual('规则验收分组');
      await groups.moveUngrouped(groupNode.id, group);
      await nodes.select(groupNode.id);
      await nodes.select(primary.id);
      final repository = container.read(routeRepositoryProvider);
      await repository.save(RouteRuleSet(revision: 0, rules: const [
        RouteRule(
            id: 'fallback',
            kind: RouteRuleKind.match,
            value: '',
            target: RouteTarget(RouteTargetKind.proxy))
      ]));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('add-rule')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('域名后缀 · DOMAIN-SUFFIX'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('IP 网段 · IP-CIDR').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('rule-value')), '127.0.0.27/8');
      await tester.tap(find.byKey(const ValueKey('rule-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分组 · 规则验收分组').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-rule')));
      await tester.pumpAndSettle();
      final saved = await repository.load();
      expect(saved.revision, 2);
      expect(saved.rules.first.value, '127.0.0.0/8');
      final session = container.read(sessionControllerProvider.notifier);
      await session.connect(primary, ProxyMode.rule);
      expect(container.read(sessionControllerProvider).connected, isTrue,
          reason: container.read(sessionControllerProvider).error);
      final active = container.read(sessionControllerProvider).active;
      expect(active?.routeBindings['group:$group']?.id, groupNode.id);
      client.findProxy = (_) => 'PROXY 127.0.0.1:${active?.proxyPort}';
      Future<String> request() async {
        final req =
            await client.getUrl(Uri.parse('http://127.0.0.1:${origin.port}/'));
        final response = await req.close().timeout(const Duration(seconds: 4));
        return response
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 4));
      }

      expect(await request(), 'group-proxy');
      await session.setMode(ProxyMode.global);
      expect(await request(), 'primary-proxy');
      await session.setMode(ProxyMode.direct);
      expect(await request(), 'direct-origin');
      await session.setMode(ProxyMode.rule);
      // Editing while connected changes the saved draft, not the active core.
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rule-target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('直连').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-rule')));
      await tester.pumpAndSettle();
      expect(find.text('规则或出站已变更，断开重连后应用。'), findsOneWidget);
      expect(await request(), 'group-proxy');
      final output = Directory('../docs/verification/routing');
      await output.create(recursive: true);
      final capture = await Process.run('python', [
        '../tools/capture_window.py',
        '--pid',
        '$pid',
        '--output',
        '${output.path}/rules-real.png'
      ]);
      expect(capture.exitCode, 0, reason: capture.stderr.toString());
      await session.disconnect();
      await session.connect(primary, ProxyMode.rule);
      client.findProxy = (_) =>
          'PROXY 127.0.0.1:${container?.read(sessionControllerProvider).active?.proxyPort}';
      client.close(force: true);
      final nextClient = HttpClient()
        ..findProxy = (_) =>
            'PROXY 127.0.0.1:${container?.read(sessionControllerProvider).active?.proxyPort}';
      try {
        final req = await nextClient
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/'));
        expect(await (await req.close()).transform(utf8.decoder).join(),
            'direct-origin');
      } finally {
        nextClient.close(force: true);
      }
      await session.disconnect();
      await File('${output.path}/windows-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'at': DateTime.now().toIso8601String(),
        'scenario': 'localhost fixtures with real bundled core',
        'uiRuleAddAndEdit': true,
        'cidrNormalized': true,
        'groupMemoryObserved': true,
        'ruleMode': 'group-proxy',
        'globalMode': 'primary-proxy',
        'directMode': 'direct-origin',
        'editKeptActiveSnapshot': true,
        'reconnectAppliedNewRules': true,
        'systemProxyChanged': false,
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
      await first.close();
      await second.close();
      await origin.close(force: true);
      await database.close();
    }
  });
}
