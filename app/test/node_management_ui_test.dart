import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_probe_controller.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_overrides_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/node_probe.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'support/memory_preferences.dart';
import 'support/subscription_fixtures.dart';

class _Probe implements NodeTester {
  final ids = <String>[];
  @override
  Future<NodeProbeResult> testNode(ProxyNode node) async {
    ids.add(node.id);
    return NodeProbeResult(
        nodeId: node.id,
        revision: node.revision,
        checkedAt: DateTime.now(),
        passed: true,
        latency: 24);
  }

  @override
  Future<void> cancelNodeTests() async {}
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isFocused'));
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('window_manager'), null));
  for (final (platform, size, scale) in [
    (TargetPlatform.windows, const Size(960, 640), 1.0),
    (TargetPlatform.windows, const Size(640, 640), 1.0),
    (TargetPlatform.android, const Size(393, 852), 1.0),
    (TargetPlatform.android, const Size(320, 740), 1.3),
  ]) {
    testWidgets(
        '$platform $size favorites/alias/hide/restore and batch probe never connect',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final secrets = TestSecretStore();
      final fetcher = TestSubscriptionFetcher()
        ..document = subscriptionDocument(nodes: [
          subscriptionNode(),
          subscriptionNode(name: '香港 01', server: 'hk.example.test')
        ]);
      final groups = DriftGroupRepository(db, secrets, fetcher);
      final nodes = DriftNodeRepository(db, secrets);
      final local = DriftNodeOverridesRepository(db);
      final probe = _Probe();
      await groups.importUrl(
          'https://example.test/sub', SubscriptionCancellation());
      final list = await db.select(db.nodes).get();
      final a = list.first, b = list.last;
      await nodes.select(b.id);
      final router = createRouter(initialLocation: '/nodes');
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(overrides: [
        preferencesRepositoryProvider.overrideWithValue(MemoryPreferences()),
        coreGatewayProvider
            .overrideWithValue(const UnavailableCoreGateway('界面验证')),
        groupRepositoryProvider.overrideWithValue(groups),
        nodeRepositoryProvider.overrideWithValue(nodes),
        nodeOverridesRepositoryProvider.overrideWithValue(local),
        nodeTesterProvider.overrideWithValue(probe),
      ], child: RainlinkApp(router: router)));
      await tester.pumpAndSettle();
      final container =
          ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
      Future<void> menu(String text) async {
        final button = find.byKey(ValueKey('node-menu-${a.id}'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.text(text));
        await tester.pumpAndSettle();
      }

      Future<void> filter(String text) async {
        await tester.tap(find.byKey(const ValueKey('node-group-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.ancestor(
            of: find.text(text).last,
            matching: find.byType(CheckedPopupMenuItem<String>)));
        await tester.pumpAndSettle();
      }

      final favorite = find.byKey(ValueKey('node-favorite-${a.id}'));
      if (favorite.evaluate().isNotEmpty) {
        await tester.tap(favorite);
        await tester.pumpAndSettle();
      } else {
        await menu('收藏节点');
      }
      expect(
          container
              .read(nodesProvider)
              .requireValue
              .firstWhere((n) => n.id == a.id)
              .favorite,
          isTrue);
      expect(container.read(selectedNodeIdProvider).valueOrNull, b.id);
      await filter('仅收藏');
      expect(find.byKey(ValueKey('node-${b.id}')), findsNothing);
      await menu('本地别名');
      await tester.enterText(find.byKey(const ValueKey('node-alias')), '工作线路');
      await tester.tap(find.byKey(const ValueKey('save-node-alias')));
      await tester.pumpAndSettle();
      expect(find.text('工作线路'), findsOneWidget);
      await filter('全部节点');
      await menu('隐藏节点');
      await tester.tap(find.widgetWithText(FilledButton, '隐藏'));
      await tester.pumpAndSettle();
      expect(find.text('工作线路'), findsNothing);
      expect(container.read(selectedNodeIdProvider).valueOrNull, b.id);
      await filter('已隐藏');
      expect(find.text('工作线路'), findsOneWidget);
      await menu('恢复显示');
      expect(find.text('没有已隐藏的节点'), findsOneWidget);
      await filter('全部节点');
      await tester.tap(find.byKey(const ValueKey('probe-visible-nodes')));
      await tester.pumpAndSettle();
      expect(probe.ids.toSet(), {a.id, b.id});
      expect(container.read(nodeProbeProvider).completed, 2);
      expect(container.read(sessionControllerProvider).connected, isFalse);
      expect(container.read(selectedNodeIdProvider).valueOrNull, b.id);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }, variant: TargetPlatformVariant.only(platform));
  }
}
