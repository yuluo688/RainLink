import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/features/nodes/presentation/node_editor_dialog.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'support/memory_preferences.dart';
import 'support/subscription_fixtures.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'isFocused');
  });
  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
  });
  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    final mobile = platform == TargetPlatform.android;
    for (final size in mobile
        ? [const Size(393, 852), const Size(320, 740)]
        : [const Size(1040, 720), const Size(640, 640)]) {
      testWidgets(
          '$platform $size imports subscription in a URL-only dialog and selects group without connecting',
          (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final secrets = TestSecretStore();
        final fetcher = TestSubscriptionFetcher();
        final groups = DriftGroupRepository(db, secrets, fetcher);
        final nodes = DriftNodeRepository(db, secrets);
        final router = createRouter();
        addTearDown(router.dispose);
        router.go('/groups');
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(ProviderScope(overrides: [
          groupRepositoryProvider.overrideWithValue(groups),
          nodeRepositoryProvider.overrideWithValue(nodes),
          preferencesRepositoryProvider.overrideWithValue(MemoryPreferences()),
          coreGatewayProvider
              .overrideWithValue(const UnavailableCoreGateway('界面验证')),
        ], child: RainlinkApp(router: router)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('添加订阅'));
        await tester.pumpAndSettle();
        expect(find.byType(NodeEditorDialog), findsOneWidget);
        expect(find.byKey(const ValueKey('node-name')), findsNothing);
        expect(find.text('分组名称'), findsNothing);
        await tester.enterText(find.byKey(const ValueKey('subscription-url')),
            'https://example.test/sub');
        await tester.tap(find.byKey(const ValueKey('save-node')));
        await tester.pumpAndSettle();
        expect(find.text('测试订阅'), findsOneWidget);
        expect(find.text('日本 01'), findsNothing);
        expect(find.textContaining('5.0 KB'), findsOneWidget);
        final container =
            ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
        final group = container.read(groupsProvider).requireValue.single;
        await tester.tap(find.byKey(ValueKey('group-${group.id}')));
        await tester.pumpAndSettle();
        expect(container.read(sessionControllerProvider).connected, isFalse);
        expect(container.read(selectedNodeIdProvider).valueOrNull, isNotNull);
        await tester.tap(find.byTooltip('分组操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('分组详情'));
        await tester.pumpAndSettle();
        expect(find.text('套餐流量'), findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('5.0 KB / 1.0 MB')),
            findsOneWidget);
        expect(find.text('自动更新'), findsWidgets);
        expect(find.text('2030-01-01'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        router.go('/nodes');
        await tester.pumpAndSettle();
        expect(find.text('日本 01'), findsOneWidget);
        await tester.tap(find.byTooltip('节点操作'));
        await tester.pumpAndSettle();
        expect(find.text('查看来源'), findsOneWidget);
        expect(find.text('移入分组'), findsNothing);
        expect(find.text('删除'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
  testWidgets(
      'Hysteria2 editor exposes QUIC credentials without TCP or TLS fingerprint controls',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showNodeEditor(context),
                        child: const Text('添加')))))));
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<NodeProtocol>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hysteria2').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('QUIC · TLS'), findsOneWidget);
    expect(find.text('UUID'), findsNothing);
    await tester.ensureVisible(find.text('高级选项'));
    await tester.tap(find.text('高级选项'));
    await tester.pumpAndSettle();
    expect(find.text('TLS 指纹'), findsNothing);
    expect(find.text('传输方式'), findsNothing);
    await tester.ensureVisible(find.text('启用 Salamander 混淆'));
    await tester.tap(find.text('启用 Salamander 混淆'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('node-obfs-password')), findsOneWidget);
    final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('node-obfs-password')));
    expect(field.controller?.text, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets(
      'manual editor exposes protocol-specific fields without losing the shared layout',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () => showNodeEditor(context),
                        child: const Text('添加')))))));
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<NodeProtocol>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VLESS').last);
    await tester.pumpAndSettle();
    expect(find.text('UUID'), findsOneWidget);
    expect(find.text('用户名'), findsNothing);
    await tester.ensureVisible(find.text('高级选项'));
    await tester.tap(find.text('高级选项'));
    await tester.pumpAndSettle();
    expect(find.text('传输方式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
