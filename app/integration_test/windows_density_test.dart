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
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native density saves, rolls back disk failure and keeps live core',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-density-');
    final file = File('${directory.path}/settings.sqlite');
    final database = AppDatabase(NativeDatabase(file));
    final router = createRouter(initialLocation: '/overview');
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final requests = origin.listen((request) async {
      transfers++;
      request.response.write('density-origin');
      await request.response.close();
    });
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
        await database.close();
      }
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: database, initialTheme: AppTheme.dark),
          child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      final current =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      container = current;
      final nodes = current.read(nodeRepositoryProvider);
      final node = await nodes.save(const NodeDraft(
          name: '密度验收节点',
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
      final active = current.read(sessionControllerProvider).active!;
      Future<void> transfer() async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 2);
        client.findProxy = (_) => 'PROXY 127.0.0.1:${active.proxyPort}';
        try {
          final request = await client
              .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/density'));
          final response =
              await request.close().timeout(const Duration(seconds: 3));
          expect(await utf8.decoder.bind(response).join(), 'density-origin');
        } finally {
          client.close(force: true);
        }
        expect(current.read(sessionControllerProvider).active?.sessionId,
            active.sessionId);
      }

      Future<double> rowHeight() async {
        router.go('/nodes');
        await tester.pumpAndSettle();
        return tester.getSize(find.byKey(ValueKey('node-${node.id}'))).height;
      }

      Future<void> selectDensity(AppDensity density) async {
        router.go('/settings');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-appearance')));
        await tester.pumpAndSettle();
        final selector = find.byKey(const ValueKey('interface-density'));
        await tester.ensureVisible(selector);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text(density.label).last);
        await waitFor(() => find.text('正在保存…').evaluate().isEmpty);
        await tester.pumpAndSettle();
      }

      await transfer();
      final compactHeight = await rowHeight();
      expect(compactHeight, 56);
      await selectDensity(AppDensity.standard);
      expect(current.read(deviceSettingsControllerProvider).appearance.density,
          AppDensity.standard);
      final standardHeight = await rowHeight();
      expect(standardHeight, 64);
      await transfer();
      await database.customStatement(
          "CREATE TRIGGER reject_appearance BEFORE UPDATE ON preferences WHEN NEW.key = 'appearance.preferences' BEGIN SELECT RAISE(ABORT, 'fixture disk full'); END;");
      await selectDensity(AppDensity.compact);
      expect(find.text('保存外观设置失败，请重试。'), findsOneWidget);
      final failedSelector = find.descendant(
          of: find.byKey(const ValueKey('interface-density')),
          matching: find.byType(DropdownButton<AppDensity>));
      expect(tester.widget<DropdownButton<AppDensity>>(failedSelector).value,
          AppDensity.standard);
      expect(current.read(deviceSettingsControllerProvider).appearance.density,
          AppDensity.standard);
      expect(
          (await DriftPreferencesRepository(database).loadDeviceSettings())
              .appearance
              .density,
          AppDensity.standard);
      await database.customStatement('DROP TRIGGER reject_appearance');
      await selectDensity(AppDensity.compact);
      expect(await rowHeight(), 56);
      await selectDensity(AppDensity.standard);
      await transfer();
      expect(current.read(sessionControllerProvider).systemProxy, isFalse);
      expect(current.read(sessionControllerProvider).tun, isFalse);
      await release();
      final reopened = AppDatabase(NativeDatabase(file));
      try {
        final saved =
            await DriftPreferencesRepository(reopened).loadDeviceSettings();
        expect(saved.appearance.density, AppDensity.standard);
      } finally {
        await reopened.close();
      }
      final output = Directory('../docs/verification/density');
      await output.create(recursive: true);
      await File('${output.path}/windows-evidence.json')
          .writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'at': DateTime.now().toIso8601String(),
            'nativeWindows': true,
            'temporaryDatabase': true,
            'compactRowHeight': compactHeight,
            'standardRowHeight': standardHeight,
            'nativeSqliteFailureKeptConfirmedDensity': true,
            'visibleSelectorKeptConfirmedDensity': true,
            'switchBackAndRetryWorked': true,
            'sameActualCoreSession': true,
            'actualOriginTransfers': transfers,
            'systemProxyEnabled': false,
            'tunEnabled': false,
            'densitySurvivedReopen': true,
          })}\n');
      expect(tester.takeException(), isNull);
    } finally {
      await release();
      await requests.cancel();
      await origin.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
