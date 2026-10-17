import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/domain/connection/connection_models.dart';

import 'app_test.dart' show pumpApp;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel,
        (call) async {
      return switch (call.method) {
        'isMaximized' => false,
        'isFocused' => true,
        _ => null,
      };
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  for (final platform in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
    TargetPlatform.android,
    TargetPlatform.iOS,
  ]) {
    final mobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    testWidgets('$platform retains its layout family regardless of width',
        (tester) async {
      // Deliberately use a narrow desktop and a wide mobile screen.
      await pumpApp(tester,
          size: mobile ? const Size(1024, 768) : const Size(640, 640));
      expect(
          find.byType(NavigationBar), mobile ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('desktop-status-bar')),
          mobile ? findsNothing : findsOneWidget);
      if (mobile) {
        await tester.tap(find.widgetWithText(NavigationDestination, '节点'));
      } else {
        await tester.tap(find.byKey(const ValueKey('nav-nodes')));
      }
      await tester.pumpAndSettle();
      expect(find.text('还没有节点'), findsOneWidget);
      expect(find.text('协议'), mobile ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform keeps node search while rotating', (tester) async {
      await pumpApp(tester, size: const Size(393, 852));
      await tester.tap(find.widgetWithText(NavigationDestination, '节点'));
      await tester.pumpAndSettle();
      final search = find.byKey(const ValueKey('node-search'));
      await tester.enterText(search, '东京 vless');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(search).controller;
      tester.view.physicalSize = const Size(852, 393);
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(tester.widget<TextField>(search).controller, same(controller));
      expect(controller?.text, '东京 vless');
      expect(find.text('没有匹配的节点'), findsOneWidget);
      expect(find.byKey(const ValueKey('desktop-status-bar')), findsNothing);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('mobile navigation uses the shared connection state',
      (tester) async {
    await pumpApp(tester, size: const Size(393, 852));
    await tester.ensureVisible(find.text('全局'));
    await tester.tap(find.text('全局'));
    await tester.pumpAndSettle();
    final container =
        ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
    expect(container.read(proxyModeProvider), ProxyMode.global);
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-about')));
    await tester.pumpAndSettle();
    expect(find.text('开发预览'), findsOneWidget);
    await tester.tap(find.widgetWithText(NavigationDestination, '首页'));
    await tester.pumpAndSettle();
    expect(container.read(proxyModeProvider), ProxyMode.global);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('mobile heading keeps auxiliary navigation without a brand bar',
      (tester) async {
    await pumpApp(tester, size: const Size(393, 852));
    expect(find.byType(AppBar), findsNothing);
    expect(find.widgetWithText(NavigationDestination, '首页'), findsOneWidget);
    await tester.tap(find.byTooltip('打开设置'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-general')), findsOneWidget);
    for (final title in ['规则', '连接', '日志']) {
      final menu = find.byTooltip('打开导航');
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, title));
      await tester.pumpAndSettle();
      expect(find.text(title == '规则' ? '分流规则' : title), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.widgetWithText(NavigationDestination, '设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-network')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-back')), findsOneWidget);
    expect(find.byTooltip('打开导航'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
