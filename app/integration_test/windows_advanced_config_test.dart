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
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/core/advanced_config.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native advanced editor checks, applies DNS and rules, and restores previous config',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-advanced-native-');
    final dbFile = File('${directory.path}/settings.sqlite');
    final database = AppDatabase(NativeDatabase(dbFile));
    final dns = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    var queries = 0;
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
      queries++;
    });
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final originEvents = origin.listen((request) async {
      transfers++;
      request.response.write('advanced-origin');
      await request.response.close();
    });
    final router = createRouter(initialLocation: '/overview');
    ProviderContainer? container;
    final capture = GlobalKey();
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
        await database.close();
      }
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(RepaintBoundary(
          key: capture,
          child: ProviderScope(
              overrides: createAppOverrides(
                  database: database, initialTheme: AppTheme.dark),
              child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      final current =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = current;
      final nodes = current.read(nodeRepositoryProvider);
      final first = await nodes.save(const NodeDraft(
          name: '高级配置验收 A',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 9));
      await nodes.select(first.id);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('connect-button')));
      Future<void> waitFor(bool Function() condition) async {
        for (var i = 0; i < 200 && !condition(); i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final feedback = find.byKey(const ValueKey('config-feedback'));
        expect(condition(), isTrue,
            reason: feedback.evaluate().isEmpty
                ? 'No config feedback'
                : tester.widget<Text>(feedback).data);
        await tester.pumpAndSettle();
      }

      await waitFor(() => current.read(sessionControllerProvider).connected);
      final original = current.read(sessionControllerProvider).active!;
      Future<bool> transfer(String host) async {
        final port = current.read(sessionControllerProvider).active!.proxyPort;
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        client.findProxy = (_) => 'PROXY 127.0.0.1:$port';
        try {
          final response = await (await client
                  .getUrl(Uri.parse('http://$host:${origin.port}/fixture')))
              .close()
              .timeout(const Duration(seconds: 3));
          return await utf8.decoder.bind(response).join() == 'advanced-origin';
        } on SocketException {
          return false;
        } on HttpException {
          return false;
        } finally {
          client.close(force: true);
        }
      }

      expect(await transfer('127.0.0.1'), isTrue);
      router.go('/settings');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('settings-core')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('open-advanced')));
      await tester.tap(find.byKey(const ValueKey('open-advanced')));
      await tester.pumpAndSettle();
      final editor = find.byKey(const ValueKey('advanced-editor'));
      final validate = find.byKey(const ValueKey('validate-advanced'));
      final apply = find.byKey(const ValueKey('apply-advanced'));
      await tester.enterText(editor, 'log: {output: fixture-secret}');
      await tester.ensureVisible(validate);
      await tester.tap(validate);
      await waitFor(() => find.textContaining('未支持的字段').evaluate().isNotEmpty);
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('config-feedback')))
              .data,
          isNot(contains('fixture-secret')));
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);
      final source =
          '# RainLink 高级配置\nlog:\n  level: info\ndns:\n  servers:\n    - type: udp\n      server: 127.0.0.1\n      server_port: ${dns.port}\n  independent_cache: true\nroute:\n  rules:\n    - domain: [allowed.advanced.test]\n      outbound: direct\n    - domain: [blocked.advanced.test]\n      action: reject';
      await tester.ensureVisible(editor);
      await tester.tap(editor);
      await tester.pumpAndSettle();
      await tester.enterText(editor, source);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).controller?.text, source);
      expect(tester.widget<TextField>(editor).readOnly, isFalse);
      expect(tester.widget<OutlinedButton>(validate).onPressed, isNotNull);
      await tester.ensureVisible(validate);
      await tester.tap(validate);
      await waitFor(() => tester.widget<FilledButton>(apply).onPressed != null);
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      final output = Directory('../docs/verification/advanced-config');
      await output.create(recursive: true);
      final exported = <String, String>{};
      for (final format in ConfigFormat.values) {
        if (format == ConfigFormat.json) {
          await tester
              .ensureVisible(find.byKey(const ValueKey('config-format-json')));
          await tester.tap(find.byKey(const ValueKey('config-format-json')));
          await tester.pumpAndSettle();
          await tester.ensureVisible(validate);
          await tester.tap(validate);
          await waitFor(
              () => tester.widget<FilledButton>(apply).onPressed != null);
        }
        final file = File(
            '${output.absolute.path}/export-${DateTime.now().microsecondsSinceEpoch}.${format.name}');
        final helper = await Process.start('python', [
          '../tools/complete_export_dialog.py',
          '--pid',
          '$pid',
          '--path',
          file.path,
        ]);
        final helperError = helper.stderr.transform(utf8.decoder).join();
        try {
          await tester.ensureVisible(find.byKey(const ValueKey('config-menu')));
          await tester.tap(find.byKey(const ValueKey('config-menu')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('导出配置'));
          for (var i = 0; i < 100 && !await file.exists(); i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(await helper.exitCode.timeout(const Duration(seconds: 25)), 0,
              reason: await helperError);
          expect(await file.exists(), isTrue);
          expect(AdvancedConfig.parse(await file.readAsString(), format),
              AdvancedConfig.parse(source, ConfigFormat.yaml));
          expect(current.read(sessionControllerProvider).active?.sessionId,
              original.sessionId);
          exported[format.name] = file.uri.pathSegments.last;
        } finally {
          helper.kill();
          await helper.exitCode.timeout(const Duration(seconds: 5));
        }
        await tester.pumpAndSettle();
      }
      await tester
          .ensureVisible(find.byKey(const ValueKey('config-format-yaml')));
      await tester.tap(find.byKey(const ValueKey('config-format-yaml')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(validate);
      await tester.tap(validate);
      await waitFor(() => tester.widget<FilledButton>(apply).onPressed != null);
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(current.read(sessionControllerProvider).active?.sessionId,
          original.sessionId);
      final other = await nodes.save(const NodeDraft(
          name: '待选节点 B',
          protocol: NodeProtocol.http,
          server: '127.0.0.1',
          port: 10));
      await nodes.select(other.id);
      await tester.pumpAndSettle();
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-advanced')));
      await waitFor(() => current
          .read(deviceSettingsControllerProvider)
          .runtime
          .advanced
          .overrides('dns', 'servers'));
      final applied = current.read(sessionControllerProvider).active!;
      expect(applied.sessionId, isNot(original.sessionId));
      expect(applied.target.id, first.id);
      expect(current.read(sessionControllerProvider).systemProxy, isFalse);
      expect(current.read(sessionControllerProvider).tun, isFalse);
      expect(await transfer('allowed.advanced.test'), isTrue,
          reason: 'queries=$queries transfers=$transfers mode=${applied.mode}');
      expect(queries, greaterThan(0));
      final beforeBlocked = transfers;
      expect(await transfer('blocked.advanced.test'), isFalse);
      expect(transfers, beforeBlocked);
      await tester.pumpAndSettle();
      tester.widget<TextField>(editor).controller?.selection =
          const TextSelection.collapsed(offset: 0);
      await tester.ensureVisible(find.byKey(const ValueKey('advanced-back')));
      await tester.pumpAndSettle();
      final boundary =
          capture.currentContext?.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(png, isNotNull);
        await File('${output.path}/editor-native.png')
            .writeAsBytes(png!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
      await tester.tap(find.byKey(const ValueKey('config-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复上一版'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(validate);
      await tester.tap(validate);
      await waitFor(() => tester.widget<FilledButton>(apply).onPressed != null);
      await tester.tap(apply);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-advanced')));
      await waitFor(() => current
          .read(deviceSettingsControllerProvider)
          .runtime
          .advanced
          .isEmpty);
      expect(
          current.read(sessionControllerProvider).active?.target.id, first.id);
      expect(await transfer('127.0.0.1'), isTrue);
      final evidence = <String, Object?>{
        'at': DateTime.now().toIso8601String(),
        'nativeWindows': true,
        'temporaryDatabase': true,
        'invalidConfigKeptSession': true,
        'validationKeptSession': true,
        'nativeSaveDialogAndReadback': exported,
        'confirmationCancelKeptSession': true,
        'applyRetainedActualTarget': true,
        'actualDnsQueries': queries,
        'actualOriginTransfers': transfers,
        'routeRejectedActualRequest': true,
        'previousConfigRestored': true,
        'systemProxyEnabled': false,
        'tunEnabled': false,
      };
      await release();
      final reopened = AppDatabase(NativeDatabase(dbFile));
      try {
        final saved =
            await DriftPreferencesRepository(reopened).loadDeviceSettings();
        expect(saved.runtime.advanced.isEmpty, isTrue);
        expect(saved.previousAdvanced?.overrides('dns', 'servers'), isTrue);
        evidence['currentAndHistorySurvivedReopen'] = true;
      } finally {
        await reopened.close();
      }
      await File('${output.path}/windows-evidence.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(evidence)}\n');
      expect(tester.takeException(), isNull);
    } finally {
      await release();
      await dnsEvents.cancel();
      dns.close();
      await originEvents.cancel();
      await origin.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
