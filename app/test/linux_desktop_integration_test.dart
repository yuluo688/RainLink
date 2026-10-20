import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/platform/window/linux_desktop_integration.dart';

import 'support/fake_desktop_integration.dart';
import 'support/memory_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.rainlink/desktop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const response = {
    'launchAtLogin': false,
    'trayVisible': false,
    'trayAvailable': false,
    'notificationsAvailable': true,
    'notificationsRequireTray': false,
  };

  test(
    'Linux requires capability fields and rejects contradictory replies',
    () async {
      final adapter = LinuxDesktopIntegration();
      addTearDown(adapter.dispose);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final value in [
        {'launchAtLogin': false, 'trayVisible': false},
        {...response, 'trayAvailable': null},
        {...response, 'trayVisible': true},
        {...response, 'notificationsAvailable': 'true'},
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => value);
        await expectLater(adapter.inspect(), throwsA(isA<SettingsException>()));
      }
      messenger.setMockMethodCallHandler(channel, (_) async => response);
      final status = await adapter.inspect();
      expect(status.trayAvailable, isFalse);
      expect(status.notificationsAvailable, isTrue);
      expect(await adapter.canNotifySubscriptionExpiry(), isTrue);
    },
  );

  test(
    'backend capability changes reach the application and errors stay safe',
    () async {
      final adapter = LinuxDesktopIntegration();
      addTearDown(adapter.dispose);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final next = adapter.actions.first;
      await messenger.handlePlatformMessage(
        'dev.rainlink/desktop',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('action', 'capabilitiesChanged'),
        ),
        (_) {},
      );
      expect(await next, DesktopAction.capabilitiesChanged);
      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(
              code: 'startup_conflict',
              message: 'private-path-and-secret',
            ),
      );
      await expectLater(
        adapter.setLaunchAtLogin(true),
        throwsA(
          isA<SettingsException>()
              .having(
                (error) => error.message,
                'safe conflict',
                contains('另一份 RainLink'),
              )
              .having(
                (error) => error.message,
                'no native details',
                isNot(contains('private')),
              ),
        ),
      );
    },
  );

  test('Linux notifications persist independently of the tray', () async {
    final desktop =
        FakeDesktopIntegration()
          ..onInspect =
              (() async => const DesktopIntegrationStatus(
                launchAtLogin: false,
                trayVisible: false,
                trayAvailable: false,
                notificationsAvailable: true,
                notificationsRequireTray: false,
              ));
    addTearDown(desktop.dispose);
    final repository = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(repository),
        desktopIntegrationProvider.overrideWithValue(desktop),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(deviceSettingsControllerProvider.notifier)
        .saveGeneral(
          const GeneralPreferences(
            showTray: false,
            connectionNotifications: true,
            subscriptionExpiryNotifications: true,
          ),
        );
    expect(repository.settings.general.showTray, isFalse);
    expect(repository.settings.general.connectionNotifications, isTrue);
    expect(repository.settings.general.subscriptionExpiryNotifications, isTrue);
    expect(desktop.trayChanges, [false]);
  });

  test(
    'missing desktop services reject new dependencies while allowing exit preferences',
    () async {
      final desktop =
          FakeDesktopIntegration()
            ..onInspect =
                (() async => const DesktopIntegrationStatus(
                  launchAtLogin: false,
                  trayVisible: false,
                  trayAvailable: false,
                  notificationsAvailable: false,
                  notificationsRequireTray: false,
                ));
      addTearDown(desktop.dispose);
      final repository = MemoryPreferences();
      final container = ProviderContainer(
        overrides: [
          preferencesRepositoryProvider.overrideWithValue(repository),
          desktopIntegrationProvider.overrideWithValue(desktop),
        ],
      );
      addTearDown(container.dispose);
      final settings = container.read(
        deviceSettingsControllerProvider.notifier,
      );
      for (final preferences in [
        const GeneralPreferences(closeBehavior: WindowCloseBehavior.tray),
        const GeneralPreferences(connectionNotifications: true),
        const GeneralPreferences(subscriptionExpiryNotifications: true),
      ]) {
        await expectLater(
          settings.saveGeneral(preferences),
          throwsA(isA<SettingsException>()),
        );
      }
      await settings.saveGeneral(const GeneralPreferences(autoConnect: true));
      expect(repository.settings.general.autoConnect, isTrue);
      expect(repository.settings.general.connectionNotifications, isFalse);
      expect(desktop.trayChanges, isEmpty);
    },
  );
}
