import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/telemetry/connections_controller.dart';
import 'package:rainlink/application/telemetry/core_log_collector.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/domain/core/core_telemetry.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';

import 'support/telemetry_fixture.dart';
import 'support/ui_fixture.dart';

void main() {
  for (final size in [const Size(960, 640), const Size(1440, 900)]) {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      for (final route in ['/connections', '/logs']) {
        testWidgets('$route at $size ${theme.name} fits with working filters',
            (tester) async {
          final fixture = FixtureTelemetryGateway();
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final router = createRouter(initialLocation: route);
          await tester.pumpWidget(ProviderScope(overrides: [
            ...visualOverrides(theme: theme),
            connectionsControllerProvider.overrideWith(
                (ref) => ConnectionsController(fixture)..setSession('fixture')),
            coreLogsProvider
                .overrideWith((ref) => Stream.value(telemetryFixtureLogs())),
          ], child: RainlinkApp(router: router)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (route == '/connections') {
            expect(find.text('api.github.com:443'), findsOneWidget);
            await tester.enterText(find.byType(TextField), 'GITHUB tcp');
            await tester.pumpAndSettle();
            expect(find.text('api.github.com:443'), findsOneWidget);
            expect(find.text('registry.npmjs.org:443'), findsNothing);
          } else {
            await tester.tap(find.text('警告').first);
            await tester.pumpAndSettle();
            expect(find.text('出口检测超时，保留当前连接'), findsOneWidget);
            expect(find.text('网络核心已连接'), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
      }
    }
  }

  testWidgets(
      'connection pause, export and close operate on the visible snapshot',
      (tester) async {
    final gateway = FixtureTelemetryGateway();
    final exporter = FixtureDataExporter();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = createRouter(initialLocation: '/connections');
    await tester.pumpWidget(ProviderScope(overrides: [
      ...visualOverrides(),
      connectionsControllerProvider.overrideWith(
          (ref) => ConnectionsController(gateway)..setSession('fixture')),
      dataExportServiceProvider.overrideWithValue(exporter),
    ], child: RainlinkApp(router: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停刷新'));
    await tester.pumpAndSettle();
    final reads = gateway.reads;
    await tester.pump(const Duration(seconds: 3));
    expect(gateway.reads, reads);
    expect(gateway.closed, isEmpty);
    await tester.enterText(find.byType(TextField), 'github');
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(exporter.content, contains('api.github.com'));
    expect(exporter.content, isNot(contains('registry.npmjs.org')));
    await tester.tap(find.byTooltip('关闭 api.github.com:443'));
    await tester.pumpAndSettle();
    expect(gateway.closed, ['fixture-0']);
    expect(find.text('api.github.com:443'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets(
      'log pause retains captured events, clear needs confirmation and export is real content',
      (tester) async {
    final repository = FixtureLogRepository();
    await repository.append(telemetryFixtureLogs());
    final gateway = FixtureTelemetryGateway();
    final exporter = FixtureDataExporter();
    final router = createRouter(initialLocation: '/logs');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...visualOverrides(),
      coreLogRepositoryProvider.overrideWithValue(repository),
      coreLogCollectorProvider
          .overrideWith((ref) => CoreLogCollector(gateway, repository)),
      dataExportServiceProvider.overrideWithValue(exporter),
    ], child: RainlinkApp(router: router)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('暂停'));
    await tester.pumpAndSettle();
    await repository.append([
      CoreLogEntry(
          id: 'fixture:9',
          sequence: 9,
          at: telemetryFixtureAt,
          level: CoreLogLevel.info,
          source: 'core',
          message: 'new captured event')
    ]);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'new captured');
    await tester.pumpAndSettle();
    expect(find.text('new captured event'), findsNothing);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    expect(find.text('new captured event'), findsOneWidget);
    await tester.tap(find.text('导出'));
    await tester.pumpAndSettle();
    expect(exporter.content, contains('new captured event'));
    expect(exporter.content, isNot(contains('网络核心已连接')));
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(gateway.logClears, 0);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '清空'));
    await tester.pumpAndSettle();
    expect(gateway.logClears, 1);
    expect(repository.entries, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    router.dispose();
    await repository.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  for (final (size, density, textSize) in [
    (const Size(393, 852), AppDensity.compact, AppTextSize.standard),
    (const Size(320, 640), AppDensity.standard, AppTextSize.extraLarge),
  ]) {
    testWidgets(
        'mobile telemetry controls and log follow work at $size $density',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      final gateway = FixtureTelemetryGateway();
      final exporter = FixtureDataExporter();
      final repository = FixtureLogRepository();
      await repository.append(telemetryFixtureLogs());
      final router = createRouter(initialLocation: '/connections');
      await tester.pumpWidget(ProviderScope(overrides: [
        ...visualOverrides(),
        initialDeviceSettingsProvider.overrideWithValue(DeviceSettings(
            appearance:
                AppearancePreferences(density: density, textSize: textSize))),
        connectionsControllerProvider.overrideWith(
            (ref) => ConnectionsController(gateway)..setSession('fixture')),
        coreLogRepositoryProvider.overrideWithValue(repository),
        coreLogCollectorProvider
            .overrideWith((ref) => CoreLogCollector(gateway, repository)),
        dataExportServiceProvider.overrideWithValue(exporter),
      ], child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
        expect(target.hitTestable(), findsOneWidget);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap(find.text('暂停刷新'));
      final reads = gateway.reads;
      await tester.pump(const Duration(seconds: 3));
      expect(gateway.reads, reads);
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'github');
      await tester.pumpAndSettle();
      await tap(find.text('导出'));
      expect(exporter.content, contains('api.github.com'));
      expect(exporter.content, isNot(contains('registry.npmjs.org')));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tap(find.byTooltip('关闭 api.github.com:443'));
      expect(gateway.closed, ['fixture-0']);
      expect(find.text('api.github.com:443'), findsNothing);
      await tap(find.text('关闭全部'));
      await tap(find.text('取消'));
      expect(gateway.closed, ['fixture-0']);

      router.go('/logs');
      await tester.pumpAndSettle();
      await tap(find.text('暂停'));
      await repository.append([
        CoreLogEntry(
            id: 'fixture:9',
            sequence: 9,
            at: telemetryFixtureAt,
            level: CoreLogLevel.info,
            source: 'core',
            message: 'new captured event')
      ]);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'new captured');
      await tester.pumpAndSettle();
      expect(find.text('new captured event'), findsNothing);
      await tap(find.text('继续'));
      expect(find.text('new captured event'), findsOneWidget);
      await tap(find.text('导出'));
      expect(exporter.content, contains('new captured event'));
      expect(exporter.content, isNot(contains('网络核心已连接')));
      // Let the real export confirmation expire before using footer controls.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '');
      await repository.append([
        for (var i = 10; i <= 90; i++)
          CoreLogEntry(
              id: 'fixture:$i',
              sequence: i,
              at: telemetryFixtureAt,
              level: CoreLogLevel.info,
              source: 'core',
              message: '滚动验收事件 $i')
      ]);
      await tester.pumpAndSettle();
      await tap(find.text('滚动至最新'));
      final list = find.byType(ListView).last;
      final scroll = tester.widget<ListView>(list).controller!;
      expect(scroll.offset, greaterThan(0));
      await tester.ensureVisible(list);
      await tester.drag(list, const Offset(0, 180));
      await tester.pumpAndSettle();
      final pausedOffset = scroll.offset;
      expect(scroll.position.extentAfter, greaterThan(40));
      await repository.append([
        CoreLogEntry(
            id: 'fixture:91',
            sequence: 91,
            at: telemetryFixtureAt,
            level: CoreLogLevel.info,
            source: 'core',
            message: '滚动验收事件 91')
      ]);
      await tester.pumpAndSettle();
      expect(scroll.offset, pausedOffset);
      await tap(find.text('滚动至最新'));
      expect(scroll.offset, greaterThan(pausedOffset));
      await tap(find.text('清空'));
      await tap(find.text('取消'));
      expect(gateway.logClears, 0);
      await tap(find.text('清空'));
      await tap(find.widgetWithText(FilledButton, '清空'));
      expect(gateway.logClears, 1);
      expect(repository.entries, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      router.dispose();
      await repository.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
