import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/design_system/widgets/rainlink_icon.dart';
import 'package:rainlink/features/nodes/presentation/widgets/node_identity.dart';

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

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    final desktop = platform == TargetPlatform.windows;
    testWidgets('$platform separates regions and preserves searchable names',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          desktop ? const Size(960, 640) : const Size(320, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final router = createRouter(initialLocation: '/nodes');
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
          overrides: visualOverrides(), child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(NodeIdentity), findsWidgets);
      final badge = find.byKey(const ValueKey('node-region-visual-jp'));
      final title = find.byKey(const ValueKey('node-name-visual-jp'));
      expect(tester.getSize(badge), const Size(28, 28));
      expect(tester.getRect(title).left - tester.getRect(badge).right, 12);
      expect(tester.widget<Text>(title).data, '东京 · 樱花');
      expect(find.text('🇯🇵东京 · 樱花'), findsNothing);
      expect(
          find.text(desktop ? '日本 · 东京' : 'VLESS · 日本 · 东京'), findsOneWidget);
      expect(
          tester.getSize(find.byKey(const ValueKey('node-visual-jp'))).height,
          56);

      final unknown = find.byKey(const ValueKey('node-region-visual-http'));
      // Card gaps can put later rows outside a narrow viewport's lazy cache.
      // Verify every node is reachable instead of counting instantiated rows.
      for (final node in visualNodes) {
        final row = find.byKey(ValueKey('node-${node.id}'));
        await tester.scrollUntilVisible(row, 56,
            scrollable: find.byType(Scrollable).last);
        expect(row, findsOneWidget);
      }
      final globe =
          find.descendant(of: unknown, matching: find.byType(RainlinkIcon));
      expect(tester.widget<RainlinkIcon>(globe).glyph, RainlinkGlyph.globe);
      expect(find.textContaining('local.example.test:8080'), findsOneWidget);

      final search = find.byKey(const ValueKey('node-search'));
      await tester.enterText(search, 'JP VLESS');
      await tester.pumpAndSettle();
      expect(find.byType(NodeIdentity), findsOneWidget);
      expect(title, findsOneWidget);
      await tester.enterText(search, '日本');
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      await tester.enterText(search, 'jp.example.test');
      await tester.pumpAndSettle();
      expect(title, findsOneWidget);
      final container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      expect(
          container.read(nodesProvider).requireValue.first.name, '🇯🇵东京 · 樱花');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(platform));
  }
}
