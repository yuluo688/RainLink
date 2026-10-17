import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/design_system/widgets/page_frame.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';

import 'support/ui_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  setUp(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
            'isMaximized' => false,
            'isFocused' => true,
            _ => null,
          }));
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  for (final size in [
    const Size(1440, 900),
    const Size(960, 640),
    const Size(892, 632)
  ]) {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      testWidgets('populated overview and traffic fit $size in $theme',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(ProviderScope(
            overrides: visualOverrides(theme: theme),
            child: const RainlinkApp()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final connection = tester
            .getRect(find.byKey(const ValueKey('overview-connection-card')));
        final outlet =
            tester.getRect(find.byKey(const ValueKey('overview-outlet-card')));
        final latency =
            tester.getRect(find.byKey(const ValueKey('overview-latency-card')));
        final health =
            tester.getRect(find.byKey(const ValueKey('overview-health-card')));
        expect(connection.left, outlet.left);
        expect(connection.right, outlet.right);
        expect(latency.top, health.top);
        expect(latency.bottom, health.bottom);
        expect(outlet.top, greaterThan(connection.bottom));
        expect(find.text('203.0.113.24'), findsOneWidget);
        expect(find.text('日本'), findsOneWidget);
        expect(find.text('未探测'), findsAtLeastNWidgets(1));
        expect(
            find.descendant(
                of: find.byType(PageFrame), matching: find.byType(Scrollable)),
            findsNothing);
        await tester.tap(find.byKey(const ValueKey('nav-traffic')));
        await tester.pumpAndSettle();
        expect(find.text('暂无流量记录'), findsNothing);
        expect(find.text('流量趋势'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('本月'));
        await tester.pumpAndSettle();
        expect(find.text('每日用量'), findsOneWidget);
        expect(tester.takeException(), isNull);
        for (final page in ['nodes', 'groups', 'settings']) {
          await tester.tap(find.byKey(ValueKey('nav-$page')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: page);
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  }

  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    testWidgets('populated mobile lists and traffic fit $size', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
          overrides: visualOverrides(), child: const RainlinkApp()));
      await tester.pumpAndSettle();
      for (final label in ['节点', '分组', '流量']) {
        await tester.tap(find.widgetWithText(NavigationDestination, label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: label);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('mobile overview fits including system safe areas: $platform',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      final safe = platform == TargetPlatform.iOS
          ? const FakeViewPadding(top: 54, bottom: 34)
          : const FakeViewPadding(top: 24, bottom: 24);
      tester.view.padding = safe;
      tester.view.viewPadding = safe;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
          overrides: visualOverrides(), child: const RainlinkApp()));
      await tester.pumpAndSettle();
      final summary =
          tester.getRect(find.byKey(const ValueKey('mobile-traffic-summary')));
      expect(summary.bottom,
          lessThan(tester.getRect(find.byType(NavigationBar)).top));
      final scroll = find.descendant(
          of: find.byType(PageFrame), matching: find.byType(Scrollable));
      expect(
          tester.state<ScrollableState>(scroll.first).position.maxScrollExtent,
          0);
      expect(find.text('203.0.113.24'), findsOneWidget);
      expect(find.text('日本'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('long IPv6 and large text remain readable on narrow mobile',
      (tester) async {
    const ip = '2001:db8:ffff:ffff:ffff:ffff:ffff:ffff';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...visualOverrides(ip: ip),
      initialDeviceSettingsProvider.overrideWithValue(const DeviceSettings(
          appearance: AppearancePreferences(textSize: AppTextSize.extraLarge))),
    ], child: const RainlinkApp()));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('overview-outlet-ip')));
    await tester.pumpAndSettle();
    expect(find.text(ip), findsOneWidget);
    final ipBounds =
        tester.getRect(find.byKey(const ValueKey('overview-outlet-ip')));
    expect(ipBounds.left, greaterThanOrEqualTo(20));
    expect(ipBounds.right, lessThanOrEqualTo(300));
    expect(ipBounds.height, greaterThan(40));
    await tester
        .ensureVisible(find.byKey(const ValueKey('mobile-traffic-summary')));
    await tester.pumpAndSettle();
    expect(find.text('今日流量'), findsOneWidget);
    expect(find.text('MB/s'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
