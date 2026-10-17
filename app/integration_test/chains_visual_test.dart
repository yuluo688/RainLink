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
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';

ProxyChain _fixture() {
  final draft = ProxyChain(
      id: 'visual-chain',
      name: '开发代理链',
      revision: 1,
      hopIds: ['visual-http', 'visual-jp']);
  final snapshot = ChainSnapshot(draft, [visualNodes.last, visualNodes.first]);
  return draft.copyWith(
      lastTest: ChainTestResult(
          fingerprint: snapshot.fingerprint,
          checkedAt: DateTime(2026, 10, 16, 12),
          passed: true,
          hops: const [
        ChainHopTest(hop: 1, latency: 12, passed: true),
        ChainHopTest(hop: 2, latency: 24, passed: true)
      ]));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('chain editor and node picker render in both layouts and themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/chains');
    await output.create(recursive: true);
    try {
      for (final size in [
        const Size(1440, 900),
        const Size(960, 640),
        const Size(393, 852)
      ]) {
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final mobile = size.width < 600;
          debugDefaultTargetPlatformOverride =
              mobile ? TargetPlatform.android : TargetPlatform.windows;
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final capture = GlobalKey();
          final router = createRouter(initialLocation: '/chain');
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme),
                chainsProvider.overrideWith((_) => Stream.value([_fixture()])),
                selectedChainIdProvider
                    .overrideWith((_) => Stream.value('visual-chain')),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          Future<void> screenshot(String state) async {
            await tester.runAsync(() async {
              final boundary = capture.currentContext?.findRenderObject()
                  as RenderRepaintBoundary;
              final rendered = await boundary.toImage(pixelRatio: 1);
              try {
                final data =
                    await rendered.toByteData(format: ui.ImageByteFormat.png);
                await File(
                        '${output.path}/chain-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                    .writeAsBytes(data!.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          await screenshot('editor');
          final change = find.text('更换').first;
          await tester.ensureVisible(change);
          await tester.tap(change);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await screenshot('picker');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          router.dispose();
        }
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  });
}
