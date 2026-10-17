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
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'settings validate in isolation, persist, and apply on confirmed restart',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-settings-native-');
    final dbFile = File('${directory.path}/settings.sqlite');
    final db = AppDatabase(NativeDatabase(dbFile));
    final dns = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final silentDns =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    var dnsQueries = 0;
    final dnsEvents = dns.listen((event) {
      if (event != RawSocketEvent.read) return;
      final packet = dns.receive();
      if (packet == null) return;
      final query = packet.data;
      var end = 12;
      while (end < query.length && query[end] != 0) {
        end += query[end] + 1;
      }
      end += 5;
      if (end > query.length) return;
      final answer = [...query.take(end)];
      answer[2] = 0x81;
      answer[3] = 0x80;
      answer[6] = 0;
      answer[7] = 1;
      answer[8] = 0;
      answer[9] = 0;
      answer[10] = 0;
      answer[11] = 0;
      answer.addAll([0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 127, 0, 0, 1]);
      dns.send(answer, packet.address, packet.port);
      dnsQueries++;
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final originEvents = origin.listen((request) async {
      transfers++;
      request.response.write('settings-origin');
      await request.response.close();
    });
    final candidate = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final nextPort = candidate.port;
    await candidate.close();
    final router = createRouter(initialLocation: '/overview');
    ProviderContainer? container;
    var released = false;
    Future<void> release() async {
      if (released) return;
      released = true;
      try {
        if (container case final current?) {
          final gateway = current.read(coreGatewayProvider);
          try {
            await gateway.disconnect();
          } finally {
            if (gateway is SessionGateway) await gateway.close();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await db.close();
        container = null;
      }
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides:
              createAppOverrides(database: db, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      final current =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = current;
      final nodes = current.read(nodeRepositoryProvider);
      final node = await nodes.save(const NodeDraft(
          name: '设置验收 A',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 9));
      await nodes.select(node.id);
      await tester.pumpAndSettle();
      await tester.tap(find.text('直连'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue);
      }

      await waitFor(() => current.read(sessionControllerProvider).connected);
      final original = current.read(sessionControllerProvider).active!;
      router.go('/settings');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-network')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('dns-custom')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dns-resolver')),
          'udp://127.0.0.1:${dns.port}');
      await tester.enterText(
          find.byKey(const ValueKey('mixed-port')), '$nextPort');
      await tester.ensureVisible(find.byKey(const ValueKey('test-dns')));
      await tester.tap(find.byKey(const ValueKey('test-dns')));
      await waitFor(() =>
          find.textContaining('example.com → 127.0.0.1').evaluate().isNotEmpty);
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      await tester.tap(find.byKey(const ValueKey('save-network')));
      await waitFor(() =>
          current.read(deviceSettingsControllerProvider).runtime.proxyPort ==
          nextPort);
      expect(current.read(sessionControllerProvider).active?.proxyPort,
          original.proxyPort);
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      final other = await nodes.save(const NodeDraft(
          name: '待应用 B',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 10));
      await nodes.select(other.id);
      await tester.ensureVisible(find.byKey(const ValueKey('settings-core')));
      await tester.tap(find.byKey(const ValueKey('settings-core')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('restart-core')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      await tester.tap(find.byKey(const ValueKey('restart-core')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '重启核心'));
      await waitFor(() =>
          current.read(sessionControllerProvider).connected &&
          current.read(sessionControllerProvider).active?.sessionId !=
              original.sessionId);
      final restarted = current.read(sessionControllerProvider).active!;
      expect(restarted.target.id, node.id);
      expect(restarted.proxyPort, nextPort);
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      client.findProxy = (_) => 'PROXY 127.0.0.1:$nextPort';
      try {
        final response = await (await client.getUrl(Uri.parse(
                'http://rainlink.example.test:${origin.port}/fixture')))
            .close()
            .timeout(const Duration(seconds: 4));
        expect(await utf8.decoder.bind(response).join(), 'settings-origin');
      } finally {
        client.close(force: true);
      }
      expect(dnsQueries, greaterThanOrEqualTo(2));
      await tester.tap(find.byKey(const ValueKey('settings-network')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('dns-resolver')),
          'udp://127.0.0.1:${silentDns.port}');
      await tester.ensureVisible(find.byKey(const ValueKey('test-dns')));
      await tester.tap(find.byKey(const ValueKey('test-dns')));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('test-dns')));
      await waitFor(() => find.text('解析测试已取消').evaluate().isNotEmpty);
      expect(current.read(sessionControllerProvider).active?.sessionId,
          restarted.sessionId);
      expect(current.read(sessionControllerProvider).systemProxy, isFalse);
      final evidence = {
        'at': DateTime.now().toIso8601String(),
        'nativeWindows': true,
        'temporaryDatabase': true,
        'validationKeptLiveSession': true,
        'testKeptLiveSession': true,
        'saveKeptLiveSession': true,
        'restartCancelKeptSession': true,
        'confirmedRestartAppliedPort': true,
        'restartRetainedOriginalTarget': true,
        'runtimeDnsReceivedQueries': dnsQueries,
        'actualOriginTransfers': transfers,
        'dnsCancellationKeptSession': true,
        'systemProxyEnabled': false,
      };
      await release();
      final reopened = AppDatabase(NativeDatabase(dbFile));
      try {
        final settings =
            await DriftPreferencesRepository(reopened).loadDeviceSettings();
        expect(settings.runtime.proxyPort, nextPort);
        expect(settings.runtime.resolver, 'udp://127.0.0.1:${dns.port}');
        evidence['settingsSurvivedReopen'] = true;
      } finally {
        await reopened.close();
      }
      final output = Directory('../docs/verification/settings');
      await output.create(recursive: true);
      await File('${output.path}/windows-evidence.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
    } finally {
      await release();
      await dnsEvents.cancel();
      dns.close();
      silentDns.close();
      await originEvents.cancel();
      await origin.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
