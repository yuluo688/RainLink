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
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/preferences/drift_preferences_repository.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/core/desktop_core_gateway.dart';
import 'package:rainlink/platform/window/desktop_session_guard.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native tray, startup receipt, hidden window and automatic connection',
      (tester) async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-desktop-native-');
    final db =
        AppDatabase(NativeDatabase(File('${directory.path}/desktop.sqlite')));
    final seedGateway = DesktopCoreGateway();
    final repository = DriftNodeRepository(db, seedGateway);
    final node = await repository.save(const NodeDraft(
        name: '桌面系统验收',
        protocol: NodeProtocol.http,
        server: '127.0.0.1',
        port: 9));
    await repository.select(node.id);
    await seedGateway.close();
    seedGateway.dispose();
    final preferences = DriftPreferencesRepository(db);
    await preferences.saveGeneral(const GeneralPreferences(
        autoConnect: true, closeBehavior: WindowCloseBehavior.tray));
    await preferences
        .saveConnection(const ConnectionPreferences(mode: ProxyMode.direct));
    final initial = await preferences.loadDeviceSettings();
    final router = createRouter(initialLocation: '/settings');
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var transfers = 0;
    final originEvents = origin.listen((request) async {
      transfers++;
      request.response.write('desktop-native-origin');
      await request.response.close();
    });
    ProviderContainer? container;
    DesktopIntegration? desktop;
    var startupChanged = false;
    bool? originalStartup;
    Future<void> waitFor(bool Function() ready) async {
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      expect(ready(), isTrue);
    }

    try {
      await initializeDesktopWindow();
      await tester.pumpWidget(ProviderScope(
          overrides: createAppOverrides(
              database: db,
              initialTheme: AppTheme.dark,
              initialSettings: initial),
          child: DesktopSessionGuard(child: RainlinkApp(router: router))));
      await tester.pumpAndSettle();
      container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      final state = container;
      desktop = state.read(desktopIntegrationProvider);
      expect(desktop, isNotNull);
      final system = desktop!;
      await waitFor(() => state.read(sessionControllerProvider).connected);
      final before = state.read(sessionControllerProvider);
      expect(before.active?.mode, ProxyMode.direct);
      expect(before.systemProxy, isFalse);
      expect((await system.inspect()).trayVisible, isTrue);
      final sessionId = before.active?.sessionId;
      final port = before.active?.proxyPort;
      expect(port, greaterThan(0));

      await windowManager.close();
      final hideDeadline = DateTime.now().add(const Duration(seconds: 5));
      while (await windowManager.isVisible() &&
          DateTime.now().isBefore(hideDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(await windowManager.isVisible(), isFalse);
      expect(
          state.read(sessionControllerProvider).active?.sessionId, sessionId);
      final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
      try {
        final request = await client
            .getUrl(Uri.parse('http://127.0.0.1:${origin.port}/hidden'));
        final response = await request.close();
        expect(await utf8.decodeStream(response), 'desktop-native-origin');
      } finally {
        client.close(force: true);
      }
      await system.showWindow();
      expect(await windowManager.isVisible(), isTrue);

      // Inspect existing registration first. Do not overwrite another copy.
      originalStartup = (await system.inspect()).launchAtLogin;
      final check = await Process.run('python', [
        '-c',
        'import winreg\ntry:\n with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r"Software\\Microsoft\\Windows\\CurrentVersion\\Run") as k:\n  winreg.QueryValueEx(k,"RainLink")\n print("present")\nexcept FileNotFoundError:\n print("absent")'
      ]);
      expect(check.exitCode, 0);
      final startupTested =
          '${check.stdout}'.trim() == 'absent' || originalStartup == true;
      if (startupTested) {
        startupChanged = true;
        await system.setLaunchAtLogin(true);
        expect((await system.inspect()).launchAtLogin, isTrue);
        await system.setLaunchAtLogin(originalStartup);
        expect((await system.inspect()).launchAtLogin, originalStartup);
        startupChanged = false;
      }

      // Disabling a tray while hidden must restore the window before deleting it.
      await system.hideWindow();
      await state
          .read(deviceSettingsControllerProvider.notifier)
          .saveGeneral(const GeneralPreferences(showTray: false));
      expect(await windowManager.isVisible(), isTrue);
      expect((await system.inspect()).trayVisible, isFalse);
      await expectLater(system.hideWindow(), throwsException);
      expect(await windowManager.isVisible(), isTrue);
      expect(
          state.read(sessionControllerProvider).active?.sessionId, sessionId);
      await state
          .read(deviceSettingsControllerProvider.notifier)
          .saveGeneral(const GeneralPreferences());
      expect((await system.inspect()).trayVisible, isTrue);
      await system.notifyConnection('连接状态已更新');

      final actions = <DesktopAction>[];
      final actionEvents = system.actions.listen(actions.add);
      await system.hideWindow();
      expect(await windowManager.isVisible(), isFalse);
      final native = await Process.run('python', [
        '../tools/verify_desktop_window.py',
        '--pid',
        '$pid',
        '--restore-from-tray',
        '--assert-tray'
      ]);
      expect(native.exitCode, 0, reason: '${native.stderr}');
      await tester.pumpAndSettle();
      expect(actions, contains(DesktopAction.show));
      expect(await windowManager.isVisible(), isTrue);
      await actionEvents.cancel();

      await state.read(sessionControllerProvider.notifier).disconnect();
      expect(state.read(sessionControllerProvider).phase, ConnectionPhase.idle);
      final output =
          File('../docs/verification/settings/desktop-native-evidence.json');
      await output.parent.create(recursive: true);
      await output.writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'at': DateTime.now().toIso8601String(),
            'nativeWindows': true,
            'temporaryDatabase': true,
            'autoConnectAppliedSavedTarget':
                before.active?.target.id == node.id,
            'savedMode': before.active?.mode.name,
            'systemProxyEnabled': false,
            'nativeTrayCreated': true,
            'shellTrayRegistrationVerified': true,
            'windowCloseKeptSession': true,
            'transferWhileHidden': transfers,
            'nativeTrayRestoredWindow': true,
            'disableTrayRestoredWindow': true,
            'hiddenWithoutTrayRejected': true,
            'connectionNotificationSubmitted': true,
            'notificationDisplayVerified': false,
            'startupRegistryWriteAndReadback': startupTested,
            'startupRegistrationRestored': true,
          })}\n');
    } finally {
      if (startupChanged && desktop != null && originalStartup != null) {
        await desktop.setLaunchAtLogin(originalStartup);
      }
      if (container case final state?) {
        await state.read(sessionControllerProvider.notifier).disconnect();
        final gateway = state.read(coreGatewayProvider);
        if (gateway is SessionGateway) await gateway.close();
      }
      await desktop?.close();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await originEvents.cancel();
      await origin.close(force: true);
      router.dispose();
      await db.close();
      await directory.delete(recursive: true);
    }
  });
}
