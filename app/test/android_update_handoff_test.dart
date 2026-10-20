import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'package:rainlink/features/settings/presentation/widgets/update_settings_panel.dart';

import 'android_update_installer_test.dart' show androidUpdateFixture;
import 'support/ui_fixture.dart';
import 'support/update_fixture.dart';

class _Core extends UnavailableCoreGateway {
  _Core() : super('test core');
  bool failStop = false;
  final events = <String>[];
  @override
  Future<void> disconnect() async {
    events.add('disconnect');
    if (failStop) {
      throw const CoreGatewayException(
        'restore_failed',
        'test restore failure',
      );
    }
  }
}

class _Prepared extends FixturePreparedUpdate {
  _Prepared(this.events);
  final List<String> events;
  final gate = Completer<void>();
  @override
  Future<void> commit() async {
    commits++;
    events.add('commit');
    await gate.future;
  }
}

class _Installer implements UpdateInstaller {
  _Installer(this.value);
  final PreparedUpdate value;
  @override
  Future<PreparedUpdate> prepare(
    DownloadedUpdate update,
    UpdateCancellation cancellation,
  ) async => value;
}

Future<ProviderContainer> _pumpHandoff(
  WidgetTester tester,
  _Core core,
  _Prepared prepared,
) async {
  final router = createRouter(initialLocation: '/settings');
  addTearDown(router.dispose);
  final source = FixtureReleaseSource()..release = androidUpdateFixture();
  final downloader = FixtureUpdateDownloader();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...visualOverrides(connected: false),
        updateInstallationModeProvider.overrideWithValue(
          UpdateInstallationMode.androidInstaller,
        ),
        appReleaseSourceProvider.overrideWithValue(source),
        updatePreferencesProvider.overrideWithValue(FixtureUpdatePreferences()),
        updateDownloaderProvider.overrideWithValue(downloader),
        updateInstallerProvider.overrideWithValue(_Installer(prepared)),
        sessionControllerProvider.overrideWith(
          (ref) => SessionController(
            core,
            onMode: (_) {},
            updateHold: () => ref.read(connectionUpdateHoldProvider),
          ),
        ),
      ],
      child: RainlinkApp(router: router),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
}

void main() {
  testWidgets(
    'Android handoff restores first, blocks reconnect, then releases controls after cancellation',
    (tester) async {
      final core = _Core();
      final prepared = _Prepared(core.events);
      final container = await _pumpHandoff(tester, core, prepared);
      final updates = container.read(appUpdateControllerProvider.notifier);
      await updates.check();
      await updates.download();
      await tester.tap(find.byKey(const ValueKey('settings-updates')));
      await tester.pumpAndSettle();
      final installing = updates.install();
      await tester.pumpAndSettle();
      expect(core.events, ['disconnect', 'commit']);
      expect(container.read(connectionUpdateHoldProvider), isTrue);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(UpdateSettingsPanel), findsOneWidget);
      final session = container.read(sessionControllerProvider.notifier);
      await session.connect(visualNodes.first, ProxyMode.rule);
      expect(session.state.error, contains('应用更新'));
      expect(session.state.phase, ConnectionPhase.idle);
      prepared.gate.completeError(const UpdateCancelled());
      await installing;
      await tester.pumpAndSettle();
      expect(container.read(connectionUpdateHoldProvider), isFalse);
      expect(updates.state.phase, AppUpdatePhase.downloaded);
      expect(updates.state.error, '更新操作已取消');
      expect(prepared.aborts, 1);
      expect(updates.state.package, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'confirmation cancellation is inert and failed network restore prevents system installation',
    (tester) async {
      final core = _Core()..failStop = true;
      final prepared = _Prepared(core.events);
      final container = await _pumpHandoff(tester, core, prepared);
      final updates = container.read(appUpdateControllerProvider.notifier);
      await updates.check();
      await updates.download();
      await tester.tap(find.text('更新').hitTestable());
      await tester.pumpAndSettle();
      final install = find.byKey(const ValueKey('install-update'));
      await tester.ensureVisible(install);
      await tester.tap(install);
      await tester.pumpAndSettle();
      expect(find.text('安装应用更新？'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '取消').last);
      await tester.pumpAndSettle();
      expect(core.events, isEmpty);
      expect(prepared.commits, 0);
      expect(prepared.aborts, 0);
      expect(updates.state.phase, AppUpdatePhase.downloaded);
      await tester.tap(install);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '继续安装'));
      await tester.pumpAndSettle();
      expect(core.events, ['disconnect']);
      expect(prepared.commits, 0);
      expect(prepared.aborts, 1);
      expect(updates.state.phase, AppUpdatePhase.downloaded);
      expect(updates.state.package, isNotNull);
      expect(updates.state.error, contains('连接尚未完全断开'));
      expect(container.read(connectionUpdateHoldProvider), isFalse);
      expect(
        container.read(sessionControllerProvider).phase,
        ConnectionPhase.failed,
      );
      expect(tester.widget<FilledButton>(install).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'Android completion leaves an explicit reopen state and discards the old download',
    () async {
      final downloader = FixtureUpdateDownloader();
      final installer = FixtureUpdateInstaller();
      final shutdown = UpdateShutdownCoordinator();
      final source = FixtureReleaseSource()..release = androidUpdateFixture();
      final preferences = FixtureUpdatePreferences();
      final controller = AppUpdateController(
        source: source,
        preferences: preferences,
        downloader: downloader,
        installer: installer,
        shutdown: shutdown,
        installationMode: UpdateInstallationMode.androidInstaller,
      );
      shutdown.attach((value) => value.commit());
      await controller.check();
      await controller.download();
      await controller.install();
      expect(controller.state.phase, AppUpdatePhase.restartRequired);
      expect(controller.state.working, isFalse);
      expect(controller.state.package, isNull);
      expect(downloader.discarded, hasLength(1));
      await controller.check();
      await controller.download();
      await controller.savePreferences(
        const UpdatePreferences(includePreview: true),
      );
      controller.cancel();
      expect(controller.state.phase, AppUpdatePhase.restartRequired);
      expect(source.requests, 1);
      expect(preferences.value.includePreview, isFalse);
      controller.dispose();
    },
  );
}
