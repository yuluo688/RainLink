import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:rainlink/app/dependencies.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

const _uuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';

Future<int> _fixturePort({bool udp = false}) async {
  if (udp) {
    final socket =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    socket.close();
    return port;
  }
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Windows manually saves VMess and imports pinned TUIC, then connects from overview',
      (tester) async {
    const hostPath = String.fromEnvironment('RAINLINK_HOST_PATH');
    final corePath = p.join(p.dirname(hostPath), 'sing-box.exe');
    final keyPair =
        await Process.run(corePath, ['generate', 'tls-keypair', 'localhost']);
    expect(keyPair.exitCode, 0);
    final pem = keyPair.stdout.toString();
    final key =
        RegExp(r'-----BEGIN PRIVATE KEY-----[\s\S]*?-----END PRIVATE KEY-----')
            .firstMatch(pem)
            ?.group(0);
    final certificate = RegExp(
            r'-----BEGIN CERTIFICATE-----([\s\S]*?)-----END CERTIFICATE-----')
        .firstMatch(pem);
    if (key == null || certificate == null) throw StateError('本机测试证书生成失败');
    final pin = sha256
        .convert(
            base64.decode(certificate.group(1)!.replaceAll(RegExp(r'\s'), '')))
        .toString();
    final vmessPort = await _fixturePort();
    final tuicPort = await _fixturePort(udp: true);
    final upstream = await Process.start(corePath, ['run', '-c', 'stdin']);
    upstream.stdin.write(jsonEncode({
      'log': {'level': 'error'},
      'inbounds': [
        {
          'type': 'vmess',
          'listen': '127.0.0.1',
          'listen_port': vmessPort,
          'users': [
            {'uuid': _uuid, 'alterId': 64}
          ]
        },
        {
          'type': 'tuic',
          'listen': '127.0.0.1',
          'listen_port': tuicPort,
          'users': [
            {'uuid': _uuid, 'password': 'fixture-tuic'}
          ],
          'tls': {
            'enabled': true,
            'certificate': [certificate.group(0)],
            'key': [key]
          }
        }
      ],
      'outbounds': [
        {'type': 'direct', 'tag': 'direct'}
      ],
      'route': {
        'rules': [
          {
            'ip_cidr': ['127.0.0.0/8'],
            'action': 'route',
            'outbound': 'direct'
          },
          {'action': 'reject'}
        ]
      }
    }));
    await upstream.stdin.close();
    final errors = <int>[];
    final stderr = upstream.stderr.listen((bytes) {
      if (errors.length < 8192) errors.addAll(bytes);
    });
    final stdout = upstream.stdout.listen((_) {});
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final originEvents = origin.listen((request) async {
      transfers++;
      request.response.write('RainLink actual protocol payload');
      await request.response.close();
    });
    final source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sourceEvents = source.listen((request) async {
      request.response.headers.set(
          'profile-title', 'base64:${base64.encode(utf8.encode('本机协议验收'))}');
      request.response.write(jsonEncode({
        'proxies': [
          {
            'name': '本机 TUIC 验收',
            'type': 'tuic',
            'server': '127.0.0.1',
            'port': tuicPort,
            'uuid': _uuid,
            'password': 'fixture-tuic',
            'sni': 'localhost',
            'fingerprint': pin,
            'congestion-controller': 'bbr',
            'heartbeat-interval': 1500
          }
        ]
      }));
      await request.response.close();
    });
    final database = AppDatabase(NativeDatabase.memory());
    final router = createRouter(initialLocation: '/nodes');
    final output = Directory('../docs/verification/protocols');
    await output.create(recursive: true);
    ProviderContainer? container;
    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final activeContainer = container;
      final session = activeContainer.read(sessionControllerProvider.notifier);
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 120 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue,
            reason: activeContainer.read(sessionControllerProvider).error);
      }

      Future<void> enter(String key, String text) async {
        final finder = find.byKey(ValueKey(key));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, text);
        await tester.pump();
      }

      Future<void> transfer(ProxyNode node) async {
        router.go('/overview');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('connect-button')));
        await waitFor(
            () => activeContainer.read(sessionControllerProvider).connected);
        final active = activeContainer.read(sessionControllerProvider).active;
        expect(active?.target.id, node.id);
        expect(active?.proxyPort, greaterThan(0));
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 8);
        client.findProxy = (_) => 'PROXY 127.0.0.1:${active!.proxyPort}';
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/verify'))
              .timeout(const Duration(seconds: 8));
          final response =
              await request.close().timeout(const Duration(seconds: 8));
          expect(await utf8.decoder.bind(response).join(),
              'RainLink actual protocol payload');
        } finally {
          client.close(force: true);
        }
        await session.disconnect();
        await tester.pumpAndSettle();
      }

      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<NodeProtocol>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VMess').last);
      await tester.pumpAndSettle();
      await enter('node-name', '本机 VMess 验收');
      await enter('node-server', '127.0.0.1');
      await enter('node-port', '$vmessPort');
      await enter('node-password', _uuid);
      await tester.ensureVisible(find.text('高级选项'));
      await tester.tap(find.text('高级选项'));
      await tester.pumpAndSettle();
      await enter('node-option-alterId', '64');
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await waitFor(
          () => find.byKey(const ValueKey('save-node')).evaluate().isEmpty);
      await tester.pumpAndSettle();
      final nodes = activeContainer.read(nodeRepositoryProvider);
      final vmess = (await nodes.watchNodes().first).single;
      expect(vmess.options.alterId, 64);
      expect(
          activeContainer.read(sessionControllerProvider).connected, isFalse);
      await nodes.select(vmess.id);
      await tester.pumpAndSettle();
      await transfer(vmess);
      router.go('/groups');
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加订阅'));
      await tester.pumpAndSettle();
      await enter(
          'subscription-url', 'http://127.0.0.1:${source.port}/protocols');
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await waitFor(
          () => find.byKey(const ValueKey('save-node')).evaluate().isEmpty);
      await tester.pumpAndSettle();
      final groups = activeContainer.read(groupRepositoryProvider);
      final group = (await groups.watchGroups().first).single;
      expect(group.name, '本机协议验收');
      await tester.tap(find.byKey(ValueKey('group-${group.id}')));
      await tester.pumpAndSettle();
      final tuic = (await nodes.watchNodes().first)
          .singleWhere((n) => n.protocol == NodeProtocol.tuic);
      expect(tuic.options.certificateSha256, pin);
      expect(tuic.options.insecure, isFalse);
      expect(tuic.options.heartbeatMillis, 1500);
      expect(await nodes.watchSelectedId().first, tuic.id);
      await transfer(tuic);
      expect(transfers, 2);
      for (final row in await database.select(database.nodes).get()) {
        expect(row.credential, isNot(contains(_uuid)));
        expect(row.credential, isNot(contains('fixture-tuic')));
        expect(row.options, isNot(contains(_uuid)));
      }
      await File('${output.path}/windows-evidence.json')
          .writeAsString(const JsonEncoder.withIndent('  ').convert({
        'at': DateTime.now().toIso8601String(),
        'scenario': 'localhost VMess and TUIC v5 fixtures with bundled core',
        'vmessManualDialog': true,
        'vmessAlterId': 64,
        'tuicSubscriptionImported': true,
        'tuicCertificatePinned': true,
        'realHttpPayloads': transfers,
        'selectedOnlyOnSave': true,
        'connectedFromOverview': true,
        'systemProxyChanged': false,
        'testDatabase': 'in-memory',
        'internetTargets': 'rejected by fixture routes'
      }));
      expect(tester.takeException(), isNull);
    } finally {
      if (container != null) {
        final gateway = container.read(coreGatewayProvider);
        await gateway.disconnect();
        if (gateway is SessionGateway) await gateway.close();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      await database.close();
      await source.close(force: true);
      await sourceEvents.cancel();
      await origin.close(force: true);
      await originEvents.cancel();
      upstream.kill();
      await upstream.exitCode;
      await stderr.cancel();
      await stdout.cancel();
    }
  });
}
