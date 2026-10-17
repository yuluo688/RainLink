import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/desktop_integration_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/design_system/theme/rainlink_density.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/export/data_export.dart';
import 'package:rainlink/platform/export/file_data_export_service.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/domain/preferences/general_preferences.dart';
import 'package:rainlink/domain/platform/desktop_integration.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'support/memory_preferences.dart';
import 'support/fake_desktop_integration.dart';

class _Diagnostics implements RuntimeSettingsGateway {
  Completer<DnsTestResult>? pending;
  Completer<void>? validating;
  Exception? failure;
  int cancellations = 0;
  @override
  Future<void> validateRuntime(CoreRuntimeSettings settings) async {
    await validating?.future;
    if (failure case final value?) throw value;
  }

  @override
  Future<void> cancelValidation() async {
    cancellations++;
  }

  @override
  Future<DnsTestResult> testDns(CoreRuntimeSettings settings) =>
      pending?.future ??
      Future.value(
          const DnsTestResult(addresses: ['203.0.113.88'], latency: 7));
  @override
  Future<void> cancelDnsTest() async {
    cancellations++;
  }
}

class _Export implements DataExportService {
  String content = '';
  String name = '';
  @override
  Future<String?> save(
      {required String suggestedName, required String content}) async {
    this.content = content;
    name = suggestedName;
    return 'fixture-export/$suggestedName';
  }
}

Future<ProviderContainer> _pump(WidgetTester tester,
    {required Size size,
    required MemoryPreferences repo,
    required _Diagnostics gateway,
    DataExportService? exporter,
    FakeDesktopIntegration? desktop}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final router = createRouter(initialLocation: '/settings');
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(overrides: [
    preferencesRepositoryProvider.overrideWithValue(repo),
    initialDeviceSettingsProvider.overrideWithValue(repo.settings),
    coreGatewayProvider.overrideWithValue(const UnavailableCoreGateway('测试环境')),
    runtimeSettingsGatewayProvider.overrideWithValue(gateway),
    if (exporter != null) dataExportServiceProvider.overrideWithValue(exporter),
    if (desktop != null) desktopIntegrationProvider.overrideWithValue(desktop),
  ], child: RainlinkApp(router: router)));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  setUp(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
            'isMaximized' => false,
            'isFocused' => true,
            _ => null
          }));
  tearDown(() =>
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));

  testWidgets(
      'density selector applies spacing after save and retains it on failure',
      (tester) async {
    final repo = MemoryPreferences();
    final container = await _pump(tester,
        size: const Size(960, 640), repo: repo, gateway: _Diagnostics());
    await tester.tap(find.byKey(const ValueKey('settings-appearance')));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('interface-density'));
    Future<void> select(String label) async {
      await tester.ensureVisible(selector);
      await tester.tap(selector);
      await tester.pumpAndSettle();
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle();
    }

    expect(RainlinkDensity.of(tester.element(selector)).rowHeight, 56);
    await select('标准');
    expect(repo.settings.appearance.density, AppDensity.standard);
    expect(RainlinkDensity.of(tester.element(selector)).rowHeight, 64);
    expect(MediaQuery.textScalerOf(tester.element(selector)).scale(14), 14);
    expect(
        container.read(deviceSettingsControllerProvider).runtime.proxyPort, 0);
    repo.writeFailure = const FormatException('fixture disk failure');
    await select('紧凑');
    expect(find.text('保存外观设置失败，请重试。'), findsOneWidget);
    expect(repo.settings.appearance.density, AppDensity.standard);
    expect(RainlinkDensity.of(tester.element(selector)).rowHeight, 64);
    expect(
        tester
            .widget<DropdownButton<AppDensity>>(find.descendant(
                of: selector,
                matching: find.byType(DropdownButton<AppDensity>)))
            .value,
        AppDensity.standard,
        reason: 'The visible selector must keep the saved density on failure');
    expect(
        find.descendant(of: selector, matching: find.text('标准')).hitTestable(),
        findsOneWidget);
    repo.writeFailure = null;
    await select('紧凑');
    expect(repo.settings.appearance.density, AppDensity.compact);
    expect(RainlinkDensity.of(tester.element(selector)).rowHeight, 56);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('disabling tray also disables tray close and notifications',
      (tester) async {
    final desktop = FakeDesktopIntegration()..tray = true;
    addTearDown(desktop.dispose);
    final repo = MemoryPreferences()
      ..settings = const DeviceSettings(
          general: GeneralPreferences(
              closeBehavior: WindowCloseBehavior.tray,
              connectionNotifications: true,
              subscriptionExpiryNotifications: true));
    await _pump(tester,
        size: const Size(960, 640),
        repo: repo,
        gateway: _Diagnostics(),
        desktop: desktop);
    final tray = find.descendant(
        of: find.byKey(const ValueKey('show-tray')),
        matching: find.byType(RainlinkSwitch));
    await tester.ensureVisible(tray);
    await tester.tap(tray);
    await tester.pumpAndSettle();
    expect(desktop.tray, isFalse);
    expect(repo.settings.general.showTray, isFalse);
    expect(repo.settings.general.connectionNotifications, isFalse);
    expect(repo.settings.general.subscriptionExpiryNotifications, isFalse);
    expect(repo.settings.general.closeBehavior, WindowCloseBehavior.exit);
    final notifications = find.descendant(
        of: find.byKey(const ValueKey('connection-notifications')),
        matching: find.byType(RainlinkSwitch));
    expect(tester.widget<RainlinkSwitch>(notifications).onChanged, isNull);
    final expiry = find.descendant(
        of: find.byKey(const ValueKey('subscription-expiry-notifications')),
        matching: find.byType(RainlinkSwitch));
    expect(tester.widget<RainlinkSwitch>(expiry).value, isFalse);
    expect(tester.widget<RainlinkSwitch>(expiry).onChanged, isNull);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'expiry preference confirms saving and preserves its value on failure',
      (tester) async {
    final desktop = FakeDesktopIntegration()..tray = true;
    addTearDown(desktop.dispose);
    final repo = MemoryPreferences();
    final container = await _pump(tester,
        size: const Size(960, 640),
        repo: repo,
        gateway: _Diagnostics(),
        desktop: desktop);
    final expiry = find.descendant(
        of: find.byKey(const ValueKey('subscription-expiry-notifications')),
        matching: find.byType(RainlinkSwitch));
    expect(tester.widget<RainlinkSwitch>(expiry).value, isFalse);
    await tester.ensureVisible(expiry);
    await tester.tap(expiry);
    await tester.pumpAndSettle();
    expect(repo.settings.general.subscriptionExpiryNotifications, isTrue);
    expect(tester.widget<RainlinkSwitch>(expiry).value, isTrue);
    repo.writeFailure = const SettingsException('磁盘写入失败');
    await tester.tap(expiry);
    await tester.pumpAndSettle();
    expect(find.text('磁盘写入失败'), findsOneWidget);
    expect(repo.settings.general.subscriptionExpiryNotifications, isTrue);
    expect(
        container
            .read(deviceSettingsControllerProvider)
            .general
            .subscriptionExpiryNotifications,
        isTrue);
    expect(tester.widget<RainlinkSwitch>(expiry).value, isTrue);
    repo.writeFailure = null;
    await tester.ensureVisible(expiry);
    await tester.tap(expiry);
    await tester.pumpAndSettle();
    expect(repo.settings.general.subscriptionExpiryNotifications, isFalse);
    expect(find.text('磁盘写入失败'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'expiry notification action uses the app router and detaches on dispose',
      (tester) async {
    final desktop = FakeDesktopIntegration()..tray = true;
    addTearDown(desktop.dispose);
    await _pump(tester,
        size: const Size(960, 640),
        repo: MemoryPreferences(),
        gateway: _Diagnostics(),
        desktop: desktop);
    desktop.events.add(DesktopAction.showGroups);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-general')), findsNothing);
    expect(find.text('新建分组'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    desktop.events.add(DesktopAction.showGroups);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('startup UI confirms the OS value and displays rejected writes',
      (tester) async {
    final desktop = FakeDesktopIntegration()..rejectLaunch = true;
    addTearDown(desktop.dispose);
    await _pump(tester,
        size: const Size(960, 640),
        repo: MemoryPreferences(),
        gateway: _Diagnostics(),
        desktop: desktop);
    final launch = find.descendant(
        of: find.byKey(const ValueKey('launch-at-login')),
        matching: find.byType(RainlinkSwitch));
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(tester.widget<RainlinkSwitch>(launch).value, isFalse);
    expect(find.textContaining('未通过系统回读确认'), findsOneWidget);
    desktop.rejectLaunch = false;
    await tester.ensureVisible(launch);
    await tester.tap(launch);
    await tester.pumpAndSettle();
    expect(desktop.launch, isTrue);
    expect(tester.widget<RainlinkSwitch>(launch).value, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  testWidgets(
      'network form validates input and preserves settings on core rejection',
      (tester) async {
    final repo = MemoryPreferences();
    final gateway = _Diagnostics();
    final container = await _pump(tester,
        size: const Size(960, 640), repo: repo, gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('settings-network')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('mixed-port')), '65536');
    await tester.tap(find.byKey(const ValueKey('save-network')));
    await tester.pumpAndSettle();
    expect(find.text('端口 0–65535'), findsOneWidget);
    expect(repo.settings.runtime.proxyPort, 0);
    await tester.enterText(find.byKey(const ValueKey('mixed-port')), '17890');
    gateway.failure = const SettingsException('核心拒绝，原设置保留');
    await tester.tap(find.byKey(const ValueKey('save-network')));
    await tester.pumpAndSettle();
    expect(find.text('核心拒绝，原设置保留'), findsOneWidget);
    expect(
        container.read(deviceSettingsControllerProvider).runtime.proxyPort, 0);
    gateway.failure = null;
    await tester.tap(find.byKey(const ValueKey('save-network')));
    await tester.pumpAndSettle();
    expect(repo.settings.runtime.proxyPort, 17890);
    expect(find.text('网络设置已保存，下一次连接时应用。'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('DNS test cancellation ignores late results and supports retry',
      (tester) async {
    final gateway = _Diagnostics()..pending = Completer<DnsTestResult>();
    await _pump(tester,
        size: const Size(960, 640),
        repo: MemoryPreferences(),
        gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('settings-network')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-dns')));
    await tester.pump();
    expect(find.text('取消测试'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('test-dns')));
    await tester.pumpAndSettle();
    expect(gateway.cancellations, 1);
    gateway.pending?.complete(
        const DnsTestResult(addresses: ['203.0.113.99'], latency: 9));
    await tester.pumpAndSettle();
    expect(find.textContaining('203.0.113.99'), findsNothing);
    expect(find.text('解析测试已取消'), findsOneWidget);
    gateway.pending = null;
    await tester.tap(find.byKey(const ValueKey('test-dns')));
    await tester.pumpAndSettle();
    expect(find.textContaining('203.0.113.88'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'advanced editor validates, confirms, exports and restores previous config',
      (tester) async {
    final repo = MemoryPreferences();
    final exporter = _Export();
    await _pump(tester,
        size: const Size(960, 640),
        repo: repo,
        gateway: _Diagnostics(),
        exporter: exporter);
    await tester.tap(find.byKey(const ValueKey('settings-core')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('open-advanced')));
    await tester.tap(find.byKey(const ValueKey('open-advanced')));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('advanced-editor'));
    final apply = find.byKey(const ValueKey('apply-advanced'));
    final validate = find.byKey(const ValueKey('validate-advanced'));
    final pageScroll =
        find.ancestor(of: apply, matching: find.byType(Scrollable));
    void expectCompactPageFits() => expect(
        tester.state<ScrollableState>(pageScroll.last).position.maxScrollExtent,
        lessThanOrEqualTo(1),
        reason: 'The compact desktop editor and its actions fit one page');
    bool canApply() => tester.widget<FilledButton>(apply).onPressed != null;
    await tester.enterText(editor,
        '# RainLink 高级配置\nlog:\n  level: debug\ndns:\n  servers:\n    - type: https\n      server: dns.alidns.com\nroute:\n  rules:\n    - domain: [example.com]\n      outbound: direct');
    await tester.pumpAndSettle();
    expectCompactPageFits();
    await tester.enterText(
        editor, '# fixture-comment-secret\nlog:\n  level: debug');
    expect(canApply(), isFalse);
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(canApply(), isTrue);
    tester.widget<TextField>(editor).controller!.selection =
        const TextSelection.collapsed(offset: 0);
    await tester.pump();
    expect(canApply(), isTrue);
    await tester.ensureVisible(find.byKey(const ValueKey('config-menu')));
    await tester.tap(find.byKey(const ValueKey('config-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('导出配置'));
    await tester.pumpAndSettle();
    expect(exporter.name, 'rainlink-advanced.yaml');
    expect(exporter.content, contains('debug'));
    expect(exporter.content, isNot(contains('fixture-comment-secret')));
    await tester.ensureVisible(apply);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-advanced')));
    await tester.pumpAndSettle();
    expect(repo.settings.runtime.advanced.overrides('log', 'level'), isTrue);
    expect(repo.settings.previousAdvanced?.isEmpty, isTrue);
    expectCompactPageFits();
    await tester.ensureVisible(find.byKey(const ValueKey('config-menu')));
    await tester.tap(find.byKey(const ValueKey('config-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复上一版'));
    await tester.pumpAndSettle();
    expect(canApply(), isFalse);
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-advanced')));
    await tester.pumpAndSettle();
    expect(repo.settings.runtime.advanced.isEmpty, isTrue);
    expect(repo.settings.previousAdvanced?.overrides('log', 'level'), isTrue);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'leaving advanced validation cancels diagnostics and ignores late output',
      (tester) async {
    final gateway = _Diagnostics()..validating = Completer<void>();
    await _pump(tester,
        size: const Size(960, 640),
        repo: MemoryPreferences(),
        gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('settings-core')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('open-advanced')));
    await tester.tap(find.byKey(const ValueKey('open-advanced')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('advanced-editor')), 'log: {level: debug}');
    await tester.ensureVisible(find.byKey(const ValueKey('validate-advanced')));
    await tester.tap(find.byKey(const ValueKey('validate-advanced')));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('advanced-back')));
    await tester.tap(find.byKey(const ValueKey('advanced-back')));
    await tester.pumpAndSettle();
    expect(gateway.cancellations, 1);
    gateway.validating?.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('advanced-editor')), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'editing during validation cancels the stale check and permits retry',
      (tester) async {
    final gateway = _Diagnostics()..validating = Completer<void>();
    await _pump(tester,
        size: const Size(960, 640),
        repo: MemoryPreferences(),
        gateway: gateway);
    await tester.tap(find.byKey(const ValueKey('settings-core')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('open-advanced')));
    await tester.tap(find.byKey(const ValueKey('open-advanced')));
    await tester.pumpAndSettle();
    final editor = find.byKey(const ValueKey('advanced-editor'));
    final validate = find.byKey(const ValueKey('validate-advanced'));
    final apply = find.byKey(const ValueKey('apply-advanced'));
    await tester.enterText(editor, 'log: {level: info}');
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pump();
    expect(tester.widget<TextField>(editor).readOnly, isFalse);
    await tester.enterText(editor, 'log: {level: debug}');
    await tester.pumpAndSettle();
    expect(gateway.cancellations, 1);
    gateway.validating?.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    gateway.validating = null;
    await tester.ensureVisible(validate);
    await tester.tap(validate);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final size in [const Size(393, 852), const Size(320, 640)]) {
    testWidgets('advanced mobile editor fits and returns to core at $size',
        (tester) async {
      final repo = MemoryPreferences()
        ..settings = const DeviceSettings(
            appearance:
                AppearancePreferences(textSize: AppTextSize.extraLarge));
      await _pump(tester, size: size, repo: repo, gateway: _Diagnostics());
      await tester.ensureVisible(find.byKey(const ValueKey('settings-core')));
      await tester.tap(find.byKey(const ValueKey('settings-core')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('open-advanced')));
      await tester.tap(find.byKey(const ValueKey('open-advanced')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('advanced-editor')), 'log: {level: debug}');
      await tester
          .ensureVisible(find.byKey(const ValueKey('config-format-json')));
      await tester.tap(find.byKey(const ValueKey('config-format-json')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('advanced-editor')))
              .controller
              ?.text,
          contains('"level": "debug"'));
      await tester
          .ensureVisible(find.byKey(const ValueKey('validate-advanced')));
      await tester.tap(find.byKey(const ValueKey('validate-advanced')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('apply-advanced')))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
      final back = find.byKey(const ValueKey('settings-back'));
      await tester.ensureVisible(back);
      expect(tester.getRect(back).left, lessThan(30));
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('open-advanced')), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
    testWidgets('mobile details return in the upper left and fit $size',
        (tester) async {
      final repo = MemoryPreferences()
        ..settings = const DeviceSettings(
            appearance:
                AppearancePreferences(textSize: AppTextSize.extraLarge));
      await _pump(tester, size: size, repo: repo, gateway: _Diagnostics());
      await tester.tap(find.byKey(const ValueKey('settings-network')));
      await tester.pumpAndSettle();
      final back = find.byKey(const ValueKey('settings-back'));
      expect(tester.getRect(back).left, lessThan(30));
      await tester.tap(find.byKey(const ValueKey('dns-encrypted')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dns-resolver')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('mixed-port')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(back);
      await tester.tap(back);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-network')), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-back')), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }

  testWidgets(
      'appearance preferences actually scale text and disable transitions',
      (tester) async {
    final repo = MemoryPreferences()
      ..settings = const DeviceSettings(
          appearance: AppearancePreferences(
              textSize: AppTextSize.large, reduceMotion: true));
    await _pump(tester,
        size: const Size(960, 640), repo: repo, gateway: _Diagnostics());
    await tester.tap(find.byKey(const ValueKey('settings-appearance')));
    await tester.pumpAndSettle();
    final switchFinder = find.descendant(
        of: find.byKey(const ValueKey('reduce-motion')),
        matching: find.byType(RainlinkSwitch));
    final context = tester.element(switchFinder);
    expect(MediaQuery.disableAnimationsOf(context), isTrue);
    expect(MediaQuery.textScalerOf(context).scale(14), closeTo(16.1, 0.01));
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(repo.settings.appearance.reduceMotion, isFalse);
    expect(
        MediaQuery.disableAnimationsOf(tester.element(switchFinder)), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
