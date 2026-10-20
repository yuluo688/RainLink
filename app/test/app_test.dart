import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/design_system/theme/rainlink_colors.dart';
import 'package:rainlink/design_system/widgets/page_frame.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/features/overview/presentation/overview_page.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

import 'support/memory_preferences.dart';

Future<void> pumpApp(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
  PreferencesRepository? preferences,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesRepositoryProvider.overrideWithValue(
          preferences ?? MemoryPreferences(),
        ),
        coreGatewayProvider.overrideWithValue(
          const UnavailableCoreGateway('网络核心尚未接入'),
        ),
      ],
      child: const RainlinkApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void testAppWidgets(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.macOS,
}) {
  testWidgets(
    description,
    callback,
    variant: TargetPlatformVariant.only(platform),
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testAppWidgets(
      'system bar contrast follows mobile theme changes on ${platform.name}',
      (tester) async {
        await pumpApp(tester, size: const Size(393, 852));
        SystemUiOverlayStyle bars() =>
            tester
                .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
                  find.byKey(const ValueKey('mobile-system-bars')),
                )
                .value;
        expect(bars().statusBarIconBrightness, Brightness.light);
        expect(bars().systemNavigationBarIconBrightness, Brightness.light);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(RainlinkApp)),
        );
        await container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.light);
        await tester.pumpAndSettle();
        expect(bars().statusBarIconBrightness, Brightness.dark);
        expect(bars().statusBarBrightness, Brightness.light);
        expect(bars().systemNavigationBarIconBrightness, Brightness.dark);
        expect(
          bars().systemNavigationBarColor,
          RainlinkColors.light.background,
        );
        await container
            .read(themeControllerProvider.notifier)
            .setTheme(AppTheme.dark);
        await tester.pumpAndSettle();
        expect(bars().statusBarIconBrightness, Brightness.light);
        expect(bars().statusBarBrightness, Brightness.dark);
        expect(bars().systemNavigationBarIconBrightness, Brightness.light);
        expect(tester.takeException(), isNull);
      },
      platform: platform,
    );
  }

  testAppWidgets('theme write exceptions show failure and allow retry', (
    tester,
  ) async {
    final preferences =
        MemoryPreferences()
          ..writeFailure = const FileSystemException('Disk unavailable');
    await pumpApp(tester, preferences: preferences);
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-appearance')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('theme-light')));
    await tester.pumpAndSettle();
    expect(find.text('保存外观设置失败，请重试。'), findsOneWidget);
    expect(find.text('外观设置已保存'), findsNothing);
    expect(preferences.theme, AppTheme.dark);
    preferences.writeFailure = null;
    await tester.tap(find.byKey(const ValueKey('theme-light')));
    await tester.pumpAndSettle();
    expect(preferences.theme, AppTheme.light);
    expect(tester.takeException(), isNull);
  });

  testAppWidgets('programming errors are not converted to storage failures', (
    tester,
  ) async {
    final failure = StateError('Invalid repository state');
    final preferences = MemoryPreferences()..writeFailure = failure;
    await pumpApp(tester, preferences: preferences);
    await tester.tap(find.byKey(const ValueKey('nav-settings')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-appearance')));
    await tester.pumpAndSettle();
    final errors = <Object>[];
    await runZonedGuarded(() async {
      await tester.tap(find.byKey(const ValueKey('theme-light')));
      await tester.pumpAndSettle();
    }, (error, _) => errors.add(error));
    expect(errors, [same(failure)]);
    expect(find.text('保存外观设置失败，请重试。'), findsNothing);
    preferences.writeFailure = null;
    await tester.tap(find.byKey(const ValueKey('theme-light')));
    await tester.pumpAndSettle();
    expect(preferences.theme, AppTheme.light);
  });

  testAppWidgets('mode and host updates leave the overview frame intact', (
    tester,
  ) async {
    await pumpApp(tester);
    final frame = tester.widget<PageFrame>(find.byType(PageFrame));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(RainlinkApp)),
    );
    await tester.tap(find.text('全局'));
    await tester.pumpAndSettle();
    expect(container.read(proxyModeProvider), ProxyMode.global);
    expect(tester.widget<PageFrame>(find.byType(PageFrame)), same(frame));
    await container.refresh(coreStatusProvider.future);
    await tester.pumpAndSettle();
    expect(tester.widget<PageFrame>(find.byType(PageFrame)), same(frame));
    expect(tester.takeException(), isNull);
  });

  testAppWidgets('initial state cannot connect or change system capture', (
    tester,
  ) async {
    await pumpApp(tester);
    expect(find.text('尚未选择连接目标'), findsOneWidget);
    final connect = tester.widget<FilledButton>(
      find.byKey(const ValueKey('connect-button')),
    );
    expect(connect.onPressed, isNull);
    expect(find.byType(RainlinkSwitch), findsNWidgets(2));
    for (final widget in tester.widgetList<RainlinkSwitch>(
      find.byType(RainlinkSwitch),
    )) {
      expect(widget.onChanged, isNull);
      expect(widget.value, isFalse);
    }
    expect(find.textContaining('203.0.113'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testAppWidgets('all desktop routes and proxy chain are reachable', (
    tester,
  ) async {
    await pumpApp(tester);
    const destinations = {
      'nodes': '还没有节点',
      'groups': '还没有分组',
      'rules': '分流规则',
      'connections': '尚未连接',
      'traffic': '暂无流量记录',
      'logs': '暂无日志',
      'settings': '界面语言',
      'overview': '尚未选择连接目标',
    };
    for (final destination in destinations.entries) {
      await tester.tap(find.byKey(ValueKey('nav-${destination.key}')));
      await tester.pumpAndSettle();
      expect(find.text(destination.value), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.byKey(const ValueKey('nav-nodes')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('代理链'));
    await tester.pumpAndSettle();
    expect(find.text('还没有可用的链路节点'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('back-to-nodes')));
    await tester.pumpAndSettle();
    expect(find.text('还没有节点'), findsOneWidget);
  });

  testAppWidgets('keyboard shortcut changes route', (tester) async {
    await pumpApp(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('还没有节点'), findsOneWidget);
  });

  testAppWidgets(
    'rapid navigation keeps desktop chrome fixed and settles once',
    (tester) async {
      await pumpApp(tester, size: const Size(947.2, 632.8));
      final nav = find.byKey(const ValueKey('nav-nodes'));
      final statusBar = find.byKey(const ValueKey('desktop-status-bar'));
      final navElement = tester.element(nav);
      final statusElement = tester.element(statusBar);
      final navRect = tester.getRect(nav);
      final statusRect = tester.getRect(statusBar);
      for (final destination in ['nodes', 'settings', 'groups', 'overview']) {
        await tester.tap(find.byKey(ValueKey('nav-$destination')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        expect(tester.element(nav), same(navElement));
        expect(tester.element(statusBar), same(statusElement));
        expect(tester.getRect(nav), navRect);
        expect(tester.getRect(statusBar), statusRect);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(PageFrame), findsOneWidget);
      expect(find.text('尚未选择连接目标'), findsOneWidget);
      expect(find.text('还没有节点'), findsNothing);
      expect(find.text('还没有分组'), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  for (final size in [const Size(947.2, 632.8), const Size(393, 852)]) {
    testAppWidgets(
      'reduced motion switches pages immediately at $size',
      (tester) async {
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
        );
        await pumpApp(tester, size: size);
        if (size.width < 720) {
          await tester.tap(find.widgetWithText(NavigationDestination, '节点'));
        } else {
          await tester.tap(find.byKey(const ValueKey('nav-nodes')));
        }
        await tester.pump();
        await tester.pump();
        final route = ModalRoute.of(tester.element(find.text('还没有节点')));
        expect(route?.animation?.isCompleted, isTrue);
        expect(find.byType(PageFrame), findsOneWidget);
        expect(find.text('尚未选择连接目标'), findsNothing);
        expect(tester.takeException(), isNull);
      },
      platform:
          size.width < 720 ? TargetPlatform.android : TargetPlatform.macOS,
    );
  }

  for (final size in [
    const Size(947.2, 632.8),
    const Size(393, 852),
    const Size(320, 640),
  ]) {
    testAppWidgets(
      'node search and clear fit $size without fabricating rows',
      (tester) async {
        await pumpApp(tester, size: size);
        if (size.width < 720) {
          await tester.tap(find.widgetWithText(NavigationDestination, '节点'));
        } else {
          await tester.tap(find.byKey(const ValueKey('nav-nodes')));
        }
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('node-search'));
        await tester.ensureVisible(search);
        await tester.enterText(search, '东京 vless');
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的节点'), findsOneWidget);
        await tester.tap(find.byTooltip('清空搜索'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(search).controller?.text, isEmpty);
        expect(find.text('还没有节点'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      platform:
          size.width < 720 ? TargetPlatform.android : TargetPlatform.macOS,
    );
  }

  for (final size in [
    const Size(1440, 900),
    const Size(1427.2, 760.8),
    const Size(1280, 720),
    const Size(947.2, 632.8),
    const Size(892, 632),
  ]) {
    testAppWidgets('complete desktop overview fits one viewport at $size', (
      tester,
    ) async {
      await pumpApp(tester, size: size);
      final overview = find.byType(OverviewPage);
      expect(
        find.descendant(of: overview, matching: find.byType(Scrollable)),
        findsNothing,
      );
      final viewport = tester.getRect(find.byType(PageFrame));
      for (final label in [
        '尚未选择连接目标',
        '选择节点',
        '开始连接',
        '系统代理',
        'TUN 模式',
        '规则',
        '全局',
        '直连',
        '当前出口',
        '国家 / 地区',
        '今日流量',
        '下载速度',
        '网络质量',
        '延迟趋势',
        '暂无延迟数据',
        '最近连接',
        '连接后查看实际网络请求',
        '查看全部',
      ]) {
        final rect = tester.getRect(
          find.descendant(of: overview, matching: find.text(label)),
        );
        expect(viewport.contains(rect.topLeft), isTrue, reason: label);
        expect(viewport.contains(rect.bottomRight), isTrue, reason: label);
      }
      final footer = tester.getRect(
        find.byKey(const ValueKey('overview-host-status')),
      );
      expect(viewport.contains(footer.bottomRight), isTrue);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('全局'));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(RainlinkApp)),
      );
      expect(container.read(proxyModeProvider), ProxyMode.global);
      await tester.tap(find.text('选择节点'));
      await tester.pumpAndSettle();
      expect(find.text('还没有节点'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testAppWidgets('slightly enlarged text fits the smallest desktop viewport', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 16 / 14;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(892, 632));
    expect(
      find.descendant(
        of: find.byType(OverviewPage),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );
    final viewport = tester.getRect(find.byType(PageFrame));
    final footer = tester.getRect(
      find.byKey(const ValueKey('overview-host-status')),
    );
    expect(viewport.contains(footer.bottomRight), isTrue);
    expect(
      viewport.contains(
        tester
            .getRect(find.byKey(const ValueKey('overview-recent-connection')))
            .bottomRight,
      ),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testAppWidgets('enlarged text keeps the complete overview reachable', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester, size: const Size(947.2, 632.8));
    expect(tester.takeException(), isNull);
    final scrollable = find.descendant(
      of: find.byType(OverviewPage),
      matching: find.byType(Scrollable),
    );
    expect(scrollable, findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('overview-host-status')),
    );
    await tester.pumpAndSettle();
    final viewport = tester.getRect(scrollable);
    final footer = tester.getRect(
      find.byKey(const ValueKey('overview-host-status')),
    );
    expect(footer.top, greaterThanOrEqualTo(viewport.top));
    expect(footer.bottom, lessThanOrEqualTo(viewport.bottom));
    await tester.ensureVisible(
      find.byKey(const ValueKey('overview-all-connections')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final size in [
    const Size(1100, 800),
    const Size(960, 640),
    const Size(393, 852),
    const Size(320, 640),
  ]) {
    testAppWidgets(
      'overview and settings fit ${size.width} logical pixels',
      (tester) async {
        await pumpApp(tester, size: size);
        expect(tester.takeException(), isNull);
        if (size.width < 720) {
          await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
        } else {
          await tester.tap(find.byKey(const ValueKey('nav-settings')));
        }
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('settings-appearance')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // The choices can be below the fold on small screens.
        await tester.ensureVisible(find.byKey(const ValueKey('theme-light')));
        await tester.tap(find.byKey(const ValueKey('theme-light')));
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(RainlinkApp));
        final container = ProviderScope.containerOf(context);
        expect(container.read(themeControllerProvider), AppTheme.light);
        final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(material.themeMode, ThemeMode.light);
        expect(
          material.theme?.extension<RainlinkColors>()?.primary,
          RainlinkColors.light.primary,
        );
        expect(tester.takeException(), isNull);
      },
      platform:
          size.width < 720 ? TargetPlatform.android : TargetPlatform.macOS,
    );
  }
}
