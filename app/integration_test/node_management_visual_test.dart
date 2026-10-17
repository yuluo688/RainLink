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
import 'package:rainlink/application/nodes/node_probe_controller.dart';
import 'package:rainlink/domain/nodes/node_probe.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/window/desktop_window.dart';
import '../test/support/ui_fixture.dart';

// These screenshots demonstrate visual states, not network test receipts.
const _nodes = [
  ProxyNode(
      id: 'visual-jp',
      name: '工作线路',
      originalName: '🇯🇵东京 · 樱花',
      protocol: NodeProtocol.vless,
      server: 'jp.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-jp',
      favorite: true),
  ProxyNode(
      id: 'visual-sg',
      name: '🇸🇬新加坡 · 滨海湾',
      protocol: NodeProtocol.hysteria2,
      server: 'sg.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-sg',
      favorite: true),
  ProxyNode(
      id: 'visual-us',
      name: '🇺🇸洛杉矶 · 西海岸',
      protocol: NodeProtocol.shadowsocks,
      server: 'us.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-us'),
  ProxyNode(
      id: 'visual-http',
      name: '开发测试 HTTP',
      protocol: NodeProtocol.http,
      server: 'local.example.test',
      port: 8080),
  ProxyNode(
      id: 'visual-vmess',
      name: '🇩🇪法兰克福 · 欧洲',
      protocol: NodeProtocol.vmess,
      server: 'de.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-de'),
  ProxyNode(
      id: 'visual-tuic',
      name: '🇹🇼台湾 · 台北',
      protocol: NodeProtocol.tuic,
      server: 'tw.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-tw'),
  ProxyNode(
      id: 'visual-hk',
      name: '备用线路',
      originalName: '🇭🇰香港 · 中环',
      protocol: NodeProtocol.trojan,
      server: 'hk.example.test',
      port: 443,
      groupId: 'visual-main',
      sourceKey: 'visual-hk',
      hidden: true),
];

class _VisualTester implements NodeTester {
  const _VisualTester();
  @override
  Future<NodeProbeResult> testNode(ProxyNode node) async => NodeProbeResult(
      nodeId: node.id,
      revision: node.revision,
      checkedAt: DateTime.now(),
      passed: true,
      latency: 24);
  @override
  Future<void> cancelNodeTests() async {}
}

class _VisualProbes extends NodeProbeController {
  _VisualProbes() : super(const _VisualTester()) {
    state = NodeProbeState(total: 3, completed: 3, results: {
      for (final (id, latency) in [
        ('visual-jp', 24),
        ('visual-sg', 32),
        ('visual-us', 0)
      ])
        id: NodeProbeResult(
            nodeId: id,
            revision: 1,
            checkedAt: DateTime(2026, 10, 16, 15, 32),
            passed: latency > 0,
            latency: latency,
            error: latency > 0 ? '' : '测试站连接超时，请检查节点和网络')
    });
  }
  void showInFlight() {
    state = NodeProbeState(
        running: true,
        total: 6,
        completed: 3,
        results: state.results,
        pending: {'visual-http', 'visual-vmess', 'visual-tuic'});
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('node management stays compact in both layouts and themes',
      (tester) async {
    await initializeDesktopWindow();
    final output = Directory('../docs/verification/node-management');
    await output.create(recursive: true);
    try {
      for (final size in [const Size(960, 640), const Size(393, 852)]) {
        debugDefaultTargetPlatformOverride =
            size.width < 600 ? TargetPlatform.android : TargetPlatform.windows;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        for (final theme in [AppTheme.dark, AppTheme.light]) {
          final router = createRouter(initialLocation: '/nodes');
          final capture = GlobalKey();
          await tester.pumpWidget(RepaintBoundary(
              key: capture,
              child: ProviderScope(overrides: [
                ...visualOverrides(theme: theme, nodes: _nodes),
                nodeTesterProvider.overrideWithValue(const _VisualTester()),
                nodeProbeProvider.overrideWith((_) => _VisualProbes()),
              ], child: RainlinkApp(router: router))));
          await tester.pumpAndSettle();
          final container = ProviderScope.containerOf(
              tester.element(find.byType(RainlinkApp)));
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
                        '${output.path}/nodes-$state-${size.width.toInt()}-${theme.name}-fixture.png')
                    .writeAsBytes(data.buffer.asUint8List());
              } finally {
                rendered.dispose();
              }
            });
          }

          Future<void> filter(String label) async {
            await tester.tap(find.byKey(const ValueKey('node-group-filter')));
            await tester.pumpAndSettle();
            await tester.tap(find.ancestor(
                of: find.text(label).last,
                matching: find.byType(CheckedPopupMenuItem<String>)));
            await tester.pumpAndSettle();
          }

          await screenshot('list');
          // Preserve the requested 56 px mobile rows; larger text may grow them.
          expect(
              tester
                  .getSize(find.byKey(const ValueKey('node-visual-jp')))
                  .height,
              56);
          await tester.tap(find.byKey(const ValueKey('node-menu-visual-jp')));
          await tester.pumpAndSettle();
          await screenshot('menu');
          await tester.tap(find.text('本地别名'));
          await tester.pumpAndSettle();
          await screenshot('alias');
          await tester.tap(find.byTooltip('关闭'));
          await tester.pumpAndSettle();
          await filter('已隐藏');
          expect(find.text('备用线路'), findsOneWidget);
          await screenshot('hidden');
          await filter('全部节点');
          (container.read(nodeProbeProvider.notifier) as _VisualProbes)
              .showInFlight();
          await tester.pumpAndSettle();
          await screenshot('probing');
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
