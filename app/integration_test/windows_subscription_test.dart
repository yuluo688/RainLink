import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const capture = bool.fromEnvironment('RAINLINK_CAPTURE_UI');
  Future<void> screenshot(String name) async {
    if (!capture) return;
    final result = await Process.run('python', [
      '../tools/capture_window.py',
      '--pid',
      '$pid',
      '--output',
      '../docs/verification/windows-subscription-$name.png'
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
  }

  Future<int> freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  testWidgets(
      'URL import to automatic group, real encrypted transfer, safe refresh and failure retention',
      (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final ssPort = await freePort();
    final vlessPort = await freePort();
    const password = 'rainlink-local-fixture';
    const uuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';
    const hostPath = String.fromEnvironment('RAINLINK_HOST_PATH');
    final corePath = p.join(p.dirname(hostPath), 'sing-box.exe');
    final upstream = await Process.start(corePath, ['run', '-c', 'stdin']);
    // Never persist fixture credentials to disk or pass them in argv.
    upstream.stdin.write(jsonEncode({
      'log': {'level': 'error'},
      'inbounds': [
        {
          'type': 'shadowsocks',
          'listen': '127.0.0.1',
          'listen_port': ssPort,
          'method': 'aes-128-gcm',
          'password': password
        },
        {
          'type': 'vless',
          'listen': '127.0.0.1',
          'listen_port': vlessPort,
          'users': [
            {'uuid': uuid}
          ]
        },
      ],
      'outbounds': [
        {'type': 'direct'}
      ],
    }));
    await upstream.stdin.close();
    final coreErrors = <int>[];
    final stderr = upstream.stderr.listen((data) {
      if (coreErrors.length < 8192) coreErrors.addAll(data);
    });
    final stdout = upstream.stdout.listen((_) {});
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final originEvents = origin.listen((request) async {
      request.response.write('RainLink subscription encrypted payload');
      await request.response.close();
    });
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var failSource = false;
    var renamed = false;
    final subscriptionEvents = source.listen((request) async {
      if (failSource) {
        request.response.statusCode = 503;
      } else {
        request.response.headers.set(
            'profile-title', 'base64:${base64.encode(utf8.encode('本机验证订阅'))}');
        request.response.headers.set('subscription-userinfo',
            'upload=1073741824; download=12884901888; total=107374182400; expire=1893456000');
        request.response.headers.set('profile-update-interval', '12');
        request.response.write(jsonEncode({
          'proxies': [
            {
              'name': renamed ? '日本 · SS 更新' : '日本 · Shadowsocks',
              'type': 'ss',
              'server': '127.0.0.1',
              'port': ssPort,
              'cipher': 'aes-128-gcm',
              'password': password
            },
            {
              'name': '美国 · VLESS',
              'type': 'vless',
              'server': '127.0.0.1',
              'port': vlessPort,
              'uuid': uuid
            },
          ]
        }));
      }
      await request.response.close();
    });
    await initializeDesktopWindow();
    await tester.pumpWidget(ProviderScope(
        overrides:
            createAppOverrides(database: database, initialTheme: AppTheme.dark),
        child: const RainlinkApp()));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
    final gateway = container.read(coreGatewayProvider);
    try {
      var ready = false;
      for (var i = 0; i < 60; i++) {
        try {
          final socket = await Socket.connect('127.0.0.1', ssPort,
              timeout: const Duration(milliseconds: 100));
          socket.destroy();
          ready = true;
          break;
        } on SocketException {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }
      expect(ready, isTrue,
          reason: utf8.decode(coreErrors, allowMalformed: true));
      await tester.tap(find.byKey(const ValueKey('nav-groups')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加订阅'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('subscription-url')),
          'http://127.0.0.1:${source.port}/subscription?token=fixture');
      await tester.pumpAndSettle();
      await screenshot('import');
      await tester.tap(find.byKey(const ValueKey('save-node')));
      for (var i = 0;
          i < 150 &&
              find
                  .byKey(const ValueKey('subscription-url'))
                  .evaluate()
                  .isNotEmpty;
          i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      final repository = container.read(groupRepositoryProvider);
      final nodeRepository = container.read(nodeRepositoryProvider);
      final group = (await repository.watchGroups().first).single;
      expect(group.name, '本机验证订阅');
      expect(group.used, 13958643712);
      expect(group.total, 107374182400);
      expect(find.text('日本 · Shadowsocks'), findsNothing);
      final raw = await database.select(database.nodeGroups).getSingle();
      expect(raw.urlCipher, isNot(contains('token=fixture')));
      final imported = await nodeRepository.watchNodes().first;
      expect(imported, hasLength(2));
      for (final n in imported) {
        expect(n.credential, isNot(contains(password)));
        expect(n.credential, isNot(contains(uuid)));
      }
      final ss =
          imported.singleWhere((n) => n.protocol == NodeProtocol.shadowsocks);
      await tester.tap(find.byKey(ValueKey('group-${group.id}')));
      await tester.pumpAndSettle();
      expect(await nodeRepository.watchSelectedId().first, ss.id);
      await tester.pumpAndSettle();
      await screenshot('groups');
      await tester.tap(find.byTooltip('分组操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分组详情'));
      await tester.pumpAndSettle();
      await screenshot('details');
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      final controller = container.read(sessionControllerProvider.notifier);
      Future<void> transfer(ProxyNode node) async {
        await controller.connect(node, ProxyMode.global);
        expect(container.read(sessionControllerProvider).connected, isTrue,
            reason: container.read(sessionControllerProvider).error);
        final snapshot = await (gateway as SessionGateway).observe();
        expect(snapshot.active?.target.id, node.id);
        // Private snapshot port is read only in this integration fixture.
        // Production UI has no arbitrary core API access.
        final sessionPort = await _mixedPort();
        final client = HttpClient()
          ..findProxy = (_) => 'PROXY 127.0.0.1:$sessionPort';
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/verify'));
          final response = await request.close();
          expect(await utf8.decoder.bind(response).join(),
              'RainLink subscription encrypted payload');
        } finally {
          client.close(force: true);
        }
      }

      await transfer(ss);
      final active = container.read(sessionControllerProvider).active;
      renamed = true;
      await repository.refresh(group.id, SubscriptionCancellation());
      final updated = (await nodeRepository.watchNodes().first)
          .singleWhere((n) => n.protocol == NodeProtocol.shadowsocks);
      expect(updated.id, ss.id);
      expect(updated.revision, ss.revision + 1);
      expect(container.read(sessionControllerProvider).active?.target.revision,
          active?.target.revision);
      expect(await nodeRepository.watchSelectedId().first, ss.id);
      failSource = true;
      await expectLater(
          repository.refresh(group.id, SubscriptionCancellation()),
          throwsA(isA<NodeException>()));
      expect(await nodeRepository.watchNodes().first, hasLength(2));
      expect((await repository.watchGroups().first).single.updateError,
          contains('503'));
      await controller.disconnect();
      final vless = (await nodeRepository.watchNodes().first)
          .singleWhere((n) => n.protocol == NodeProtocol.vless);
      await transfer(vless);
      await controller.disconnect();
      await tester.pumpAndSettle();
      await screenshot('failed-update');
      expect(tester.takeException(), isNull);
    } finally {
      await gateway.disconnect();
      if (gateway is SessionGateway) await gateway.close();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await database.close();
      await source.close(force: true);
      await subscriptionEvents.cancel();
      await origin.close(force: true);
      await originEvents.cancel();
      upstream.kill();
      await upstream.exitCode;
      await stderr.cancel();
      await stdout.cancel();
    }
  });
}

Future<int> _mixedPort() async {
  // The test observes its own process-owned listener, without changing system proxy.
  final processes = await Process.run('powershell', [
    '-NoProfile',
    '-Command',
    r'''Get-CimInstance Win32_Process | Where-Object { $_.Name -in @('rainlink-host.exe','sing-box.exe') } | Select-Object Name,ProcessId,ParentProcessId | ConvertTo-Json -Compress'''
  ]);
  if (processes.exitCode != 0) throw StateError('无法读取测试宿主进程');
  final processData = jsonDecode(processes.stdout.toString());
  final all = processData is List ? processData : [processData];
  // Restrict probes to this app's exact host child and its core, even if another
  // RainLink or another proxy client is running on the user's machine.
  final hosts = all
      .whereType<Map<String, Object?>>()
      .where((item) =>
          item['Name'] == 'rainlink-host.exe' && item['ParentProcessId'] == pid)
      .map((item) => item['ProcessId'])
      .toSet();
  final ids = all
      .whereType<Map<String, Object?>>()
      .where((item) =>
          item['Name'] == 'sing-box.exe' &&
          hosts.contains(item['ParentProcessId']))
      .map((item) => item['ProcessId'])
      .toSet();
  final result = await Process.run('netstat', ['-ano', '-p', 'tcp']);
  if (result.exitCode != 0) throw StateError('无法读取测试核心端口');
  final candidates = <int>[];
  for (final line in const LineSplitter().convert(result.stdout.toString())) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length != 5 ||
        !ids.contains(int.tryParse(parts.last)) ||
        !parts[1].startsWith('127.0.0.1:') ||
        parts[2] != '0.0.0.0:0') {
      continue;
    }
    final port = int.tryParse(parts[1].split(':').last);
    if (port != null) candidates.add(port);
  }
  // Both private mixed and API listeners exist. Identify mixed with a SOCKS greeting.
  for (final port in candidates) {
    try {
      final socket = await Socket.connect('127.0.0.1', port,
          timeout: const Duration(seconds: 1));
      socket.add([5, 1, 0]);
      try {
        final first =
            await socket.first.timeout(const Duration(milliseconds: 300));
        if (first.length >= 2 && first[0] == 5 && first[1] == 0) return port;
      } finally {
        socket.destroy();
      }
    } on IOException {
      continue;
    } on TimeoutException {
      continue;
    }
  }
  throw StateError('未找到测试核心的混合端口');
}
