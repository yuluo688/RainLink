import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/design_system/widgets/desktop_window_chrome.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import 'package:window_manager/window_manager.dart';

import 'app_test.dart' show pumpApp;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final commands = <String>[];
  var maximized = false;

  Future<void> sendEvent(String name) async {
    final completed = Completer<void>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec()
          .encodeMethodCall(MethodCall('onEvent', {'eventName': name})),
      (_) => completed.complete(),
    );
    await completed.future;
  }

  setUp(() {
    commands.clear();
    maximized = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      commands.add(call.method);
      switch (call.method) {
        case 'isMaximized':
          return maximized;
        case 'isFocused':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  testWidgets('caption shares the status row at desktop minimum width',
      (tester) async {
    await pumpApp(tester, size: const Size(960, 640));
    final controls = find.byType(DesktopWindowControls);
    expect(controls, findsOneWidget);
    expect(
        tester.getSize(find.byKey(const ValueKey('desktop-status-bar'))).height,
        desktopHeaderHeight);
    final caption = find.byKey(const ValueKey('window-status-drag-area'));
    // The remaining pixel belongs to the status bar's bottom divider.
    expect(tester.getSize(caption).height, desktopHeaderHeight - 1);
    expect(find.byTooltip('最小化'), findsOneWidget);
    expect(find.byTooltip('最大化'), findsOneWidget);
    expect(find.byTooltip('关闭窗口'), findsOneWidget);
    expect(tester.getCenter(controls).dy,
        tester.getCenter(find.text('未连接').first).dy);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'buttons dispatch commands and native events update restore state',
      (tester) async {
    await pumpApp(tester);
    commands.clear();
    await tester.tap(find.byTooltip('最小化'));
    await tester.pump();
    await tester.tap(find.byTooltip('最大化'));
    await tester.pump();
    expect(commands, ['minimize', 'isMaximized', 'maximize']);

    maximized = true;
    await sendEvent('maximize');
    await tester.pump();
    expect(find.byTooltip('还原窗口'), findsOneWidget);
    await tester.tap(find.byTooltip('还原窗口'));
    await tester.pump();
    expect(commands.last, 'unmaximize');

    maximized = false;
    await sendEvent('unmaximize');
    await tester.pump();
    expect(find.byTooltip('最大化'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭窗口'));
    await tester.pump();
    expect(commands.last, 'close');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('status caption double-click maximizes and restores',
      (tester) async {
    await pumpApp(tester);
    final area = find.byKey(const ValueKey('window-status-drag-area'));
    commands.clear();
    await tester.tap(area);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(area);
    await tester.pumpAndSettle();
    expect(commands, ['isMaximized', 'maximize']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('native command failure is reported and visible', (tester) async {
    await pumpApp(tester);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      throw PlatformException(code: 'window_unavailable');
    });
    await tester.tap(find.byTooltip('最小化'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isA<PlatformException>());
    expect(find.text('无法最小化窗口，请重试。'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('mobile does not create desktop controls or call window channels',
      (tester) async {
    await pumpApp(tester, size: const Size(393, 852));
    expect(find.byType(DesktopWindowControls), findsNothing);
    expect(commands, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('narrow desktop keeps its sidebar and window status bar',
      (tester) async {
    await pumpApp(tester, size: const Size(640, 640));
    expect(find.byType(DesktopWindowControls), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-status-bar')), findsOneWidget);
    expect(find.byKey(const ValueKey('nav-nodes')), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip('关闭窗口'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  test('late native state completes safely after controller disposal',
      () async {
    final pending = Completer<bool>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      return call.method == 'isMaximized' ? pending.future : true;
    });
    final controller = DesktopWindowController();
    final initialization = controller.initialize();
    expect(windowManager.listeners, contains(controller));
    controller.dispose();
    pending.complete(false);
    await initialization;
    expect(windowManager.listeners, isNot(contains(controller)));
  });
}
