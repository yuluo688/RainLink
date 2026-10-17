import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/updates/app_update_controller.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/updates/app_update.dart';
import 'package:rainlink/features/settings/presentation/widgets/update_settings_panel.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';

import 'support/update_fixture.dart';

Future<ProviderContainer> pumpUpdate(WidgetTester tester,
    {FixtureReleaseSource? source,
    FixtureUpdatePreferences? preferences,
    FixtureUpdateDownloader? downloader,
    FixtureUpdateInstaller? installer}) async {
  await tester.pumpWidget(ProviderScope(
      overrides: [
        appReleaseSourceProvider.overrideWithValue(source),
        updatePreferencesProvider.overrideWithValue(preferences),
        updateDownloaderProvider.overrideWithValue(downloader),
        updateInstallerProvider.overrideWithValue(installer),
      ],
      child: MaterialApp(
          theme: buildRainlinkTheme(Brightness.dark),
          home: const Scaffold(
              body: SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: UpdateSettingsPanel())))));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(
      tester.element(find.byType(UpdateSettingsPanel)));
}

void main() {
  testWidgets(
      'empty release, error retry and cancelled late response stay distinct',
      (tester) async {
    final source = FixtureReleaseSource();
    final container = await pumpUpdate(tester,
        source: source, preferences: FixtureUpdatePreferences());
    await tester.tap(find.byKey(const ValueKey('check-update')));
    await tester.pumpAndSettle();
    expect(find.text('尚无可用发布版本'), findsOneWidget);
    expect(find.text('当前版本无需更新'), findsNothing);
    source.failure = Exception('private upstream response');
    await tester.tap(find.byKey(const ValueKey('check-update')));
    await tester.pumpAndSettle();
    expect(find.text('更新操作未完成'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    source.failure = null;
    source.pending = Completer<AppRelease?>();
    await tester.tap(find.byKey(const ValueKey('check-update')));
    await tester.pump();
    expect(find.text('正在检查更新…'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-update')));
    source.pending?.complete(fixtureUpdateRelease());
    await tester.pumpAndSettle();
    expect(container.read(appUpdateControllerProvider).release, isNull);
    expect(find.byKey(const ValueKey('download-update')), findsNothing);
  });

  testWidgets(
      'download progress can cancel and install confirmation can refuse',
      (tester) async {
    final release = fixtureUpdateRelease();
    final source = FixtureReleaseSource()..release = release;
    final downloader = FixtureUpdateDownloader()
      ..pending = Completer<DownloadedUpdate>();
    final installer = FixtureUpdateInstaller();
    final container = await pumpUpdate(tester,
        source: source,
        preferences: FixtureUpdatePreferences(),
        downloader: downloader,
        installer: installer);
    await tester.tap(find.byKey(const ValueKey('check-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('download-update')));
    await tester.pump();
    downloader.progress?.call(20 * 1024 * 1024, 40 * 1024 * 1024);
    await tester.pump();
    expect(find.text('20.0 / 40.0 MB'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cancel-update')));
    downloader.pending?.complete(
        DownloadedUpdate(release: release, path: 'fixture/cancelled.zip'));
    await tester.pumpAndSettle();
    expect(downloader.discarded, hasLength(1));
    expect(find.byKey(const ValueKey('install-update')), findsNothing);

    downloader.pending = null;
    await tester.tap(find.byKey(const ValueKey('download-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('install-update')));
    await tester.pumpAndSettle();
    expect(find.text('安装更新并重启？'), findsOneWidget);
    await tester.tap(find.text('取消').last);
    await tester.pumpAndSettle();
    expect(installer.prepared.commits, 0);
    final detach = container
        .read(updateShutdownProvider)
        .attach((_) async => throw const UpdateException('网络尚未恢复'));
    await tester.tap(find.byKey(const ValueKey('install-update')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '安装并重启').last);
    await tester.pumpAndSettle();
    detach();
    expect(installer.prepared.aborts, 1);
    expect(installer.prepared.commits, 0);
    expect(find.text('网络尚未恢复'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-update')), findsOneWidget);
  });

  testWidgets(
      'preferences keep confirmed values and unsupported platforms do not act',
      (tester) async {
    final source = FixtureReleaseSource();
    final preferences = FixtureUpdatePreferences()..reject = true;
    final container =
        await pumpUpdate(tester, source: source, preferences: preferences);
    await tester
        .ensureVisible(find.byKey(const ValueKey('startup-update-check')));
    final startupSwitch = find.descendant(
        of: find.byKey(const ValueKey('startup-update-check')),
        matching: find.byType(RainlinkSwitch));
    await tester.tap(startupSwitch);
    await tester.pumpAndSettle();
    expect(
        container.read(appUpdateControllerProvider).preferences.checkOnStartup,
        isFalse);
    expect(find.text('更新偏好未能保存，已保留原设置'), findsOneWidget);
    preferences.reject = false;
    await tester.tap(startupSwitch);
    await tester.pumpAndSettle();
    expect(preferences.value.checkOnStartup, isTrue);
    await tester.pumpWidget(const SizedBox());
    await pumpUpdate(tester);
    expect(find.text('此平台的应用更新尚未接入'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const ValueKey('check-update')))
            .onPressed,
        isNull);
    expect(find.text('尚未配置'), findsOneWidget);
  });
}
