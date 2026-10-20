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
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/core/desktop_core_gateway.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import 'package:rainlink/platform/window/desktop_session_guard.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'real Linux autostart, panel, notification and host-loss recovery',
    (tester) async {
      expect(Platform.isLinux, isTrue);
      expect(const String.fromEnvironment('RAINLINK_TEST_DESKTOP'), 'isolated');
      final config = Platform.environment['XDG_CONFIG_HOME'];
      expect(config, startsWith('/tmp/rainlink-desktop-integration-'));
      final entry = File('$config/autostart/dev.rainlink.rainlink.desktop');
      expect(await entry.exists(), isFalse);
      final output = Directory(
        const String.fromEnvironment(
          'RAINLINK_VISUAL_OUTPUT',
          defaultValue: '/qa/output/desktop-integration-stage',
        ),
      );
      await output.create(recursive: true);
      await initializeDesktopWindow();
      final database = AppDatabase(NativeDatabase.memory());
      final router = createRouter(initialLocation: '/settings');
      final events = <DesktopAction>[];
      DesktopIntegration? integration;
      StreamSubscription<DesktopAction>? subscription;
      DesktopCoreGateway? core;
      final results = <String, Object?>{};

      Future<ProcessResult> command(
        String executable,
        List<String> arguments,
      ) async {
        final result = await Process.run(
          executable,
          arguments,
        ).timeout(const Duration(seconds: 10));
        expect(result.exitCode, 0, reason: '$executable: ${result.stderr}');
        return result;
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        await command('import', [
          '-window',
          'root',
          '${output.path}/$name.png',
        ]);
      }

      Future<void> waitFor(
        Future<bool> Function() predicate,
        String reason,
      ) async {
        for (var retry = 0; retry < 80; retry++) {
          if (await predicate()) return;
          await tester.pump(const Duration(milliseconds: 100));
        }
        fail(reason);
      }

      Future<void> activate() async {
        await command('gdbus', [
          'call',
          '--session',
          '--dest',
          'org.kde.StatusNotifierItem-$pid-1',
          '--object-path',
          '/StatusNotifierItem',
          '--method',
          'org.kde.StatusNotifierItem.Activate',
          '0',
          '0',
        ]);
      }

      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: createAppOverrides(
              database: database,
              initialTheme: AppTheme.dark,
            ),
            child: DesktopSessionGuard(child: RainlinkApp(router: router)),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RainlinkApp)),
        );
        integration = container.read(desktopIntegrationProvider);
        expect(integration, isNotNull);
        final desktop = integration!;
        subscription = desktop.actions.listen(events.add);
        core = container.read(coreGatewayProvider) as DesktopCoreGateway;
        final host = await container.read(coreStatusProvider.future);
        expect(host.capabilities.tun, isFalse);
        await waitFor(
          () async => (await desktop.inspect()).trayVisible,
          'The real panel did not register the item',
        );
        final initial = await desktop.inspect();
        expect(initial.trayAvailable, isTrue);
        expect(initial.notificationsAvailable, isTrue);
        expect(initial.notificationsRequireTray, isFalse);
        results['initialServicesAvailable'] = true;
        final windowSearch = await command('xdotool', [
          'search',
          '--pid',
          '$pid',
          '--name',
          '^RainLink'
              r'$',
        ]);
        final windowId = '${windowSearch.stdout}'.trim().split('\n').last;
        Future<bool> windowVisible() async {
          final window = await command('xwininfo', ['-id', windowId]);
          return '${window.stdout}'.contains('Map State: IsViewable');
        }

        final launch = find.descendant(
          of: find.byKey(const ValueKey('launch-at-login')),
          matching: find.byType(RainlinkSwitch),
        );
        await tester.ensureVisible(launch);
        await tester.tap(launch);
        await tester.pumpAndSettle();
        expect((await desktop.inspect()).launchAtLogin, isTrue);
        expect(await entry.exists(), isTrue);
        await command('desktop-file-validate', [entry.path]);
        await tester.tap(launch);
        await tester.pumpAndSettle();
        expect((await desktop.inspect()).launchAtLogin, isFalse);
        expect(await entry.exists(), isFalse);
        results['uiAutostartEnableDisableAndReadback'] = true;
        await windowManager.setSize(const Size(1440, 900));
        // GTK's center hint applies when mapping the window. Move this already
        // visible QA window explicitly so the resized capture fits the display.
        await windowManager.setPosition(const Offset(80, 50));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();
        expect(await windowManager.getSize(), const Size(1440, 900));
        final scroll =
            find.ancestor(of: launch, matching: find.byType(Scrollable)).first;
        tester.state<ScrollableState>(scroll).position.jumpTo(0);
        await capture('general-dark-panel');
        expect(Theme.of(tester.element(launch)).brightness, Brightness.dark);
        await container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.light);
        await capture('general-light-panel');
        expect(Theme.of(tester.element(launch)).brightness, Brightness.light);
        await container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.dark);

        await desktop.hideWindow();
        await waitFor(
          () async => !await windowVisible(),
          'The native window did not hide',
        );
        await activate();
        await tester.pumpAndSettle();
        await waitFor(windowVisible, 'The native window did not restore');
        expect(events, contains(DesktopAction.show));
        results['realPanelActivationRestoresWindow'] = true;

        await desktop.notifyConnection('本机隔离验证：连接状态通知');
        await desktop.notifySubscriptionExpiry(expiringSoon: 2, expired: 1);
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final displayed = await command('dunstctl', ['count', 'displayed']);
        expect(
          int.parse('${displayed.stdout}'.trim()),
          greaterThanOrEqualTo(1),
        );
        await capture('system-notifications');
        await command('dunstctl', ['close-all']);
        await desktop.notifySubscriptionExpiry(expiringSoon: 2, expired: 1);
        await command('dunstctl', ['action']);
        await waitFor(
          () async => events.contains(DesktopAction.showGroups),
          'Notification default action was not delivered',
        );
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/groups');
        results['realNotificationDisplayedAndActionOpensGroups'] = true;
        await command('dunstctl', ['close-all']);

        // Removing the real panel must restore a hidden window automatically.
        await desktop.hideWindow();
        await command('xfce4-panel', ['--quit']);
        await waitFor(
          () async => !(await desktop.inspect()).trayAvailable,
          'Panel disappearance was not observed',
        );
        await waitFor(
          windowVisible,
          'Panel loss left the native window hidden',
        );
        expect((await desktop.inspect()).trayVisible, isFalse);
        results['panelLossRestoresWindow'] = true;
        router.go('/settings');
        await tester.pumpAndSettle();
        await capture('general-no-panel');
        // A desktop panel can restart while the app remains open.
        final restartedPanel = await Process.start('xfce4-panel', [
          '--disable-wm-check',
        ]);
        unawaited(restartedPanel.stdout.drain<void>());
        unawaited(restartedPanel.stderr.drain<void>());
        await waitFor(
          () async => (await desktop.inspect()).trayVisible,
          'The icon did not return after restarting the real panel',
        );
        results['panelRestartRegistersAgain'] = true;
        await command('xfce4-panel', ['--quit']);
        await waitFor(
          () async => !(await desktop.inspect()).trayAvailable,
          'The restarted panel did not stop',
        );
        final settings = container.read(
          deviceSettingsControllerProvider.notifier,
        );
        final current =
            container.read(deviceSettingsControllerProvider).general;
        await settings.saveGeneral(
          current.copyWith(
            showTray: false,
            closeBehavior: WindowCloseBehavior.exit,
            connectionNotifications: true,
            subscriptionExpiryNotifications: true,
          ),
        );
        expect(await desktop.canNotifySubscriptionExpiry(), isTrue);
        await desktop.notifySubscriptionExpiry(expiringSoon: 1, expired: 0);
        final withoutTray = await command('dunstctl', ['count', 'displayed']);
        expect(
          int.parse('${withoutTray.stdout}'.trim()),
          greaterThanOrEqualTo(1),
        );
        results['notificationsWithoutTray'] = true;
        await command('dunstctl', ['close-all']);
        await settings.saveGeneral(const GeneralPreferences(showTray: false));
        results['publicTunRemainsFalse'] = host.capabilities.tun == false;
        results['applicationActions'] =
            events.map((event) => event.name).toList();
        await File('${output.path}/native-integration.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(results)}\n',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await subscription?.cancel();
        await integration?.setLaunchAtLogin(false);
        await integration?.setTrayVisible(false);
        await core?.close();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        router.dispose();
        await database.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
