import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('protocol editors fit desktop/mobile layouts in both themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/protocols');
    await output.create(recursive: true);
    try {
      for (final size in [const Size(960, 640), const Size(393, 852)]) {
        debugDefaultTargetPlatformOverride =
            size.width < 600 ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          for (final protocol in [NodeProtocol.vmess, NodeProtocol.tuic]) {
            final router = createRouter(initialLocation: '/nodes');
            final capture = GlobalKey();
            await tester.pumpWidget(RepaintBoundary(
                key: capture,
                child: ProviderScope(
                    overrides: visualOverrides(theme: theme),
                    child: RainlinkApp(router: router))));
            await tester.pumpAndSettle();
            await tester.tap(find.text('添加'));
            await tester.pumpAndSettle();
            await tester
                .tap(find.byType(DropdownButtonFormField<NodeProtocol>));
            await tester.pumpAndSettle();
            await tester.tap(find.text(protocol.label).last);
            await tester.pumpAndSettle();
            Future<void> screenshot(String state) async {
              expect(tester.takeException(), isNull);
              await tester.runAsync(() async {
                final boundary = capture.currentContext?.findRenderObject()
                    as RenderRepaintBoundary;
                final rendered = await boundary.toImage(pixelRatio: 1);
                try {
                  final data =
                      await rendered.toByteData(format: ui.ImageByteFormat.png);
                  if (data == null) {
                    throw StateError('Screenshot encoding failed');
                  }
                  await File(
                          '${output.path}/${state == 'subscription' ? 'add' : protocol.wireName}-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                      .writeAsBytes(data.buffer.asUint8List());
                } finally {
                  rendered.dispose();
                }
              });
            }

            await screenshot('editor');
            await tester.ensureVisible(find.text('高级选项'));
            await tester.tap(find.text('高级选项'));
            await tester.pumpAndSettle();
            await tester.ensureVisible(find.byKey(ValueKey(
                protocol == NodeProtocol.vmess
                    ? 'node-option-alterId'
                    : 'node-option-heartbeat')));
            await tester.pumpAndSettle();
            await screenshot('advanced');
            if (protocol == NodeProtocol.tuic) {
              await tester.tap(find.byTooltip('关闭'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('添加'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('订阅'));
              await tester.pumpAndSettle();
              await screenshot('subscription');
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            router.dispose();
          }
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
