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
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_probe_controller.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'local choices and isolated probes preserve a real active Windows session',
      (tester) async {
    final sockets = <Socket>{};
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final originEvents = origin.listen((request) async {
      transfers++;
      request.response.write('node-management-actual-payload');
      await request.response.close();
    });
    final upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    var authenticated = false;
    var hold = false, held = false, heldClosed = false;
    Future<void> handle(Socket local, {required bool reject}) async {
      sockets.add(local);
      final input = StreamIterator(local);
      Socket? remote;
      var wasHeld = false;
      try {
        final bytes = <int>[];
        var headerEnd = -1;
        while (headerEnd < 0 && await input.moveNext()) {
          bytes.addAll(input.current);
          if (bytes.length > 8192) return;
          headerEnd = latin1.decode(bytes).indexOf('\r\n\r\n');
        }
        if (headerEnd < 0) return;
        if (reject && hold) {
          wasHeld = held = true;
          while (await input.moveNext()) {
            // Deliberately withhold CONNECT until the client cancels.
          }
          return;
        }
        final header = latin1.decode(bytes.sublist(0, headerEnd));
        final lines = header.split('\r\n');
        final firstLine = lines.first.split(' ');
        final target = firstLine.length == 3
            ? Uri.tryParse('http://${firstLine[1]}')
            : null;
        final expected =
            'Basic ${base64.encode(utf8.encode('fixture-user:fixture-password'))}';
        final validAuthentication = lines.any((line) =>
            line.toLowerCase().startsWith('proxy-authorization:') &&
            line.substring(line.indexOf(':') + 1).trim() == expected);
        if (reject ||
            !validAuthentication ||
            firstLine.first != 'CONNECT' ||
            target?.host != '127.0.0.1' ||
            target?.port != origin.port) {
          local.write(
              'HTTP/1.1 407 Proxy Authentication Required\r\nContent-Length: 0\r\nConnection: close\r\n\r\n');
          await local.flush();
          return;
        }
        authenticated = true;
        remote = await Socket.connect('127.0.0.1', origin.port,
            timeout: const Duration(seconds: 2));
        sockets.add(remote);
        local.write('HTTP/1.1 200 Connection Established\r\n\r\n');
        await local.flush();
        remote.listen(local.add,
            onDone: local.destroy, onError: (Object _) => local.destroy());
        remote.add(bytes.sublist(headerEnd + 4));
        while (await input.moveNext()) {
          remote.add(input.current);
        }
      } on IOException {
        // Closing the isolated core may reset its local fixture socket.
      } finally {
        if (wasHeld) heldClosed = true;
        await input.cancel();
        local.destroy();
        remote?.destroy();
      }
    }

    final upstreamEvents =
        upstream.listen((s) => unawaited(handle(s, reject: false)));
    final bad = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final badEvents = bad.listen((s) => unawaited(handle(s, reject: true)));
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sourceEvents = source.listen((request) async {
      request.response.headers.set(
          'profile-title', 'base64:${base64.encode(utf8.encode('本机节点验收'))}');
      request.response.write(jsonEncode({
        'proxies': [
          {
            'name': '日本 · 验收节点',
            'type': 'http',
            'server': '127.0.0.1',
            'port': upstream.port,
            'username': 'fixture-user',
            'password': 'fixture-password',
          }
        ]
      }));
      await request.response.close();
    });
    final db = AppDatabase(NativeDatabase.memory());
    final router = createRouter(initialLocation: '/overview');
    ProviderContainer? container;
    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides:
              createAppOverrides(database: db, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final activeContainer = container;
      final nodes = activeContainer.read(nodeRepositoryProvider);
      await activeContainer.read(groupRepositoryProvider).importUrl(
          'http://127.0.0.1:${source.port}/sub', SubscriptionCancellation());
      final managed = (await nodes.watchNodes().first).single;
      final rejected = await nodes.save(NodeDraft(
          name: '拒绝认证的节点',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: bad.port));
      await nodes.select(managed.id);
      await tester.pumpAndSettle();
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 150 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue);
      }

      final session = activeContainer.read(sessionControllerProvider.notifier);
      await tester.tap(find.text('全局'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      await waitFor(
          () => activeContainer.read(sessionControllerProvider).connected);
      final initial = activeContainer.read(sessionControllerProvider).active;
      expect(initial, isNotNull);
      Future<void> transfer() async {
        final active = activeContainer.read(sessionControllerProvider).active;
        expect(active?.sessionId, initial?.sessionId);
        expect(active?.proxyPort, initial?.proxyPort);
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        client.findProxy = (_) => 'PROXY 127.0.0.1:${active?.proxyPort}';
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/verify'));
          final response =
              await request.close().timeout(const Duration(seconds: 4));
          expect(await utf8.decoder.bind(response).join(),
              'node-management-actual-payload');
        } finally {
          client.close(force: true);
        }
      }

      await transfer();
      router.go('/nodes');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('node-favorite-${managed.id}')));
      await tester.pumpAndSettle();
      Future<void> menu(String nodeId, String text) async {
        await tester.tap(find.byKey(ValueKey('node-menu-$nodeId')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      Future<void> filter(String text) async {
        await tester.tap(find.byKey(const ValueKey('node-group-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.ancestor(
            of: find.text(text),
            matching: find.byType(CheckedPopupMenuItem<String>)));
        await tester.pumpAndSettle();
      }

      await menu(managed.id, '本地别名');
      await tester.enterText(find.byKey(const ValueKey('node-alias')), '工作线路');
      await tester.tap(find.byKey(const ValueKey('save-node-alias')));
      await tester.pumpAndSettle();
      await menu(managed.id, '隐藏节点');
      await tester.tap(find.widgetWithText(FilledButton, '隐藏'));
      await tester.pumpAndSettle();
      expect(activeContainer.read(selectedNodeIdProvider).valueOrNull, isNull);
      await transfer();
      await filter('已隐藏');
      await menu(managed.id, '恢复显示');
      await filter('全部节点');
      await tester.tap(find.byKey(ValueKey('node-${managed.id}')));
      await tester.pumpAndSettle();
      final local = activeContainer
          .read(nodesProvider)
          .requireValue
          .singleWhere((n) => n.id == managed.id);
      expect(local.favorite, isTrue);
      expect(local.name, '工作线路');
      expect(local.sourceName, managed.name);
      expect(local.revision, managed.revision);
      await tester.tap(find.byKey(const ValueKey('probe-visible-nodes')));
      await waitFor(() => !activeContainer.read(nodeProbeProvider).running);
      final probeState = activeContainer.read(nodeProbeProvider);
      expect(probeState.completed, 2);
      expect(probeState.results[rejected.id]?.passed, isFalse);
      expect(find.text('失败'), findsWidgets);
      await transfer();
      hold = true;
      await menu(rejected.id, '测试延迟');
      await waitFor(() => held);
      await tester.tap(find.byKey(const ValueKey('probe-visible-nodes')));
      await waitFor(() => !activeContainer.read(nodeProbeProvider).running);
      await waitFor(() => heldClosed);
      await transfer();
      expect(authenticated, isTrue);
      final row = await (db.select(db.nodes)
            ..where((n) => n.id.equals(managed.id)))
          .getSingle();
      expect(row.credential, isNot(contains('fixture-password')));
      expect(row.name, managed.name);
      expect((await db.select(db.nodeOverrides).getSingle()).alias, '工作线路');
      final output =
          File('../docs/verification/node-management/windows-evidence.json');
      await output.parent.create(recursive: true);
      await output.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'at': DateTime.now().toIso8601String(),
        'scenario': 'local HTTP fixtures with actual Windows host/core',
        'favoritesAliasHideRestore': true,
        'activeSessionPreserved': true,
        'realHttpPayloads': transfers,
        'authenticatedUpstream': authenticated,
        'isolatedBatchReceipts': probeState.completed,
        'rejectedNodeReportedFailure': true,
        'inFlightCancelClosedUpstream': heldClosed,
        'testDatabase': 'in-memory',
        'publicTargets': 'rejected by local proxy fixtures',
        'systemProxyRequested': false,
      }));
      await session.disconnect();
      expect(tester.takeException(), isNull);
    } finally {
      if (container != null) {
        final gateway = container.read(coreGatewayProvider);
        try {
          await gateway.disconnect();
        } finally {
          if (gateway is SessionGateway) await gateway.close();
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      await db.close();
      for (final socket in sockets) {
        socket.destroy();
      }
      await source.close(force: true);
      await sourceEvents.cancel();
      await bad.close();
      await badEvents.cancel();
      await upstream.close();
      await upstreamEvents.cancel();
      await origin.close(force: true);
      await originEvents.cancel();
    }
  });
}
