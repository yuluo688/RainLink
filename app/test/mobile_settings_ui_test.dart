import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/mobile_integration_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/platform/mobile_integration.dart';
import 'package:rainlink/features/settings/presentation/widgets/mobile_general_settings.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'support/fake_mobile_integration.dart';
import 'support/memory_preferences.dart';
import 'support/ui_fixture.dart';

Future<void> _pump(
    WidgetTester tester, FakeMobileIntegration mobile, MemoryPreferences repo,
    {double width = 393, double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 852);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(mobile.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        mobileIntegrationProvider.overrideWithValue(mobile),
        preferencesRepositoryProvider.overrideWithValue(repo),
        initialDeviceSettingsProvider.overrideWithValue(repo.settings),
      ],
      child: MaterialApp(
          theme: buildRainlinkTheme(Brightness.dark),
          home: MediaQuery(
              data: MediaQueryData(
                  size: Size(width, 852), textScaler: TextScaler.linear(scale)),
              child: const Scaffold(
                  body: SingleChildScrollView(
                      child: Padding(
                          padding: EdgeInsets.all(20),
                          child: MobileGeneralSettings())))))));
  await tester.pumpAndSettle();
}

Future<void> _toggle(WidgetTester tester, String key) async {
  final row = find.byKey(ValueKey(key));
  await tester.ensureVisible(row);
  // Tap the actual row's switch, preserving its minimum touch target.
  final control =
      find.descendant(of: row, matching: find.byType(RainlinkSwitch));
  await tester.tap(control);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'denied notification authorization leaves the preference off and explains how to retry',
      (tester) async {
    final mobile = FakeMobileIntegration()
      ..status = const MobileNotificationStatus(
          allowed: false, connectionAllowed: false, expiryAllowed: false);
    final repo = MemoryPreferences();
    await _pump(tester, mobile, repo);
    await _toggle(tester, 'connection-notifications');
    expect(mobile.requests, 1);
    expect(repo.settings.general.connectionNotifications, isFalse);
    expect(find.textContaining('系统未允许这类通知'), findsOneWidget);
    expect(mobile.configurations, isEmpty);
  });

  testWidgets(
      'granted notification and auto-connect switches persist and remain independent from tray settings',
      (tester) async {
    final mobile = FakeMobileIntegration();
    final repo = MemoryPreferences();
    await _pump(tester, mobile, repo);
    await _toggle(tester, 'auto-connect');
    await _toggle(tester, 'connection-notifications');
    expect(repo.settings.general.autoConnect, isTrue);
    expect(repo.settings.general.connectionNotifications, isTrue);
    expect(mobile.connection, isTrue);
    expect(mobile.requests, 0);
    expect(find.text('显示托盘图标'), findsNothing);
    await tester.ensureVisible(
        find.byKey(const ValueKey('mobile-notification-settings')));
    await tester
        .tap(find.byKey(const ValueKey('mobile-notification-settings')));
    await tester.pumpAndSettle();
    expect(mobile.openedSettings, 1);
  });

  testWidgets(
      'disabled Android channel cannot be mistaken for enabled delivery',
      (tester) async {
    final mobile = FakeMobileIntegration()
      ..status = const MobileNotificationStatus(
          allowed: true, connectionAllowed: false, expiryAllowed: true);
    final repo = MemoryPreferences();
    await _pump(tester, mobile, repo);
    await _toggle(tester, 'connection-notifications');
    expect(repo.settings.general.connectionNotifications, isFalse);
    expect(find.textContaining('系统未允许这类通知'), findsOneWidget);
    expect(mobile.requests, 0);
  });

  testWidgets(
      'mobile notification rows remain usable at 320 wide and large text',
      (tester) async {
    await _pump(tester, FakeMobileIntegration(), MemoryPreferences(),
        width: 320, scale: 1.3);
    await tester.ensureVisible(
        find.byKey(const ValueKey('subscription-expiry-notifications')));
    expect(tester.takeException(), isNull);
    final row = tester.getRect(
        find.byKey(const ValueKey('subscription-expiry-notifications')));
    expect(row.left, greaterThanOrEqualTo(20));
    expect(row.right, lessThanOrEqualTo(300));
    await _toggle(tester, 'subscription-expiry-notifications');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a mobile notification action routes through the app-owned router',
      (tester) async {
    final mobile = FakeMobileIntegration();
    addTearDown(mobile.dispose);
    final router = createRouter(initialLocation: '/overview');
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      ...visualOverrides(mobileTunnel: true),
      mobileIntegrationProvider.overrideWithValue(mobile),
    ], child: RainlinkApp(router: router)));
    await tester.pumpAndSettle();
    mobile.events.add(MobileAction.groups);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/groups');
    mobile.events.add(MobileAction.overview);
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/overview');
    await tester.pumpWidget(const SizedBox());
  });
}
