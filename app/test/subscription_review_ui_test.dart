import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/app/rainlink_app.dart';
import 'package:rainlink/app/router.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/device_settings_controller.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/groups/subscription_issue.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/domain/preferences/device_settings.dart';
import 'package:rainlink/features/nodes/presentation/node_editor_dialog.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'package:rainlink/platform/window/desktop_window.dart';

import 'support/memory_preferences.dart';
import 'support/subscription_fixtures.dart';

void main() => registerSubscriptionReviewUiTests();

/// The native visual runner reuses these assertions with real font rendering.
void registerSubscriptionReviewUiTests({bool captureScreenshots = false}) {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  if (!captureScreenshots) {
    setUp(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'),
        (call) async => call.method == 'isFocused'));
    tearDown(() => binding.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null));
  }
  for (final (size, platform, textSize) in [
    (const Size(1440, 900), TargetPlatform.windows, AppTextSize.standard),
    (const Size(960, 640), TargetPlatform.windows, AppTextSize.standard),
    (const Size(393, 852), TargetPlatform.android, AppTextSize.standard),
    (const Size(320, 640), TargetPlatform.android, AppTextSize.extraLarge),
  ]) {
    for (final theme in [AppTheme.dark, AppTheme.light]) {
      testWidgets(
          'subscription review $size ${theme.name} ${textSize.name}: edit URL, expand, accept and update without connection',
          (tester) async {
        if (captureScreenshots) await initializeDesktopWindow();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        final mobile = platform == TargetPlatform.android;
        final safe = mobile
            ? const FakeViewPadding(top: 24, bottom: 24)
            : const FakeViewPadding();
        tester.view.padding = safe;
        tester.view.viewPadding = safe;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetPadding);
        addTearDown(tester.view.resetViewPadding);
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fetcher = TestSubscriptionFetcher()
          ..document = parseSubscription(
              jsonEncode({
                'proxies': [
                  {
                    'name': '测试 HTTP',
                    'type': 'http',
                    'server': 'proxy.example.test',
                    'port': 8080
                  },
                  {
                    'name': '私有节点名称',
                    'type': 'unknown',
                    'password': 'private-password'
                  },
                  {
                    'type': 'vless',
                    'server': 'proxy.example.test',
                    'port': 443,
                    'uuid': 'private-uuid'
                  },
                  {
                    'name': '剩余流量 100 GB',
                    'type': 'ss',
                    'server': 'localhost',
                    'port': 8080,
                    'password': 'private-password'
                  },
                ],
                'rules': ['DOMAIN,private.example.test,DIRECT'],
                'dns': {
                  'nameserver': ['private.example.test']
                },
                'mixed-port': 17890,
              }),
              {
                'profile-title': '兼容测试订阅',
                'subscription-userinfo':
                    'upload=1024;download=4096;total=1048576;expire=1893456000'
              },
              Uri.parse('https://example.test/sub'));
        final secrets = TestSecretStore();
        final groups = DriftGroupRepository(db, secrets, fetcher);
        final nodes = DriftNodeRepository(db, secrets);
        final router = createRouter(initialLocation: '/groups');
        addTearDown(router.dispose);
        final capture = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
            key: capture,
            child: ProviderScope(overrides: [
              groupRepositoryProvider.overrideWithValue(groups),
              nodeRepositoryProvider.overrideWithValue(nodes),
              preferencesRepositoryProvider
                  .overrideWithValue(MemoryPreferences()..theme = theme),
              initialThemeProvider.overrideWithValue(theme),
              initialDeviceSettingsProvider.overrideWithValue(DeviceSettings(
                  appearance: AppearancePreferences(textSize: textSize))),
              coreGatewayProvider
                  .overrideWithValue(const UnavailableCoreGateway('布局验证')),
            ], child: RainlinkApp(router: router))));
        await tester.pumpAndSettle();
        expect(Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
            theme == AppTheme.dark ? Brightness.dark : Brightness.light);
        Future<void> screenshot(String state) async {
          expect(tester.takeException(), isNull);
          if (!captureScreenshots) return;
          await tester.runAsync(() async {
            final output =
                Directory('../docs/verification/subscription-compatibility');
            await output.create(recursive: true);
            final boundary = capture.currentContext?.findRenderObject()
                as RenderRepaintBoundary;
            final rendered = await boundary.toImage(pixelRatio: 1);
            try {
              final bytes =
                  await rendered.toByteData(format: ui.ImageByteFormat.png);
              if (bytes == null) throw StateError('Screenshot encoding failed');
              await File(
                      '${output.path}/$state-${size.width.toInt()}-${theme.name}-${textSize.name}-fixture.png')
                  .writeAsBytes(bytes.buffer.asUint8List());
            } finally {
              rendered.dispose();
            }
          });
        }

        Future<void> tap(Finder finder) async {
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        Future<void> menu(String label) async {
          await tap(find.byTooltip('分组操作'));
          await tap(find.text(label));
        }

        await tap(find.text('添加订阅'));
        final url = find.byKey(const ValueKey('subscription-url'));
        await tester.enterText(url, 'https://example.test/sub');
        await tap(find.byKey(const ValueKey('save-node')));
        expect(find.text('导入前确认'), findsOneWidget);
        expect(await db.select(db.nodeGroups).get(), isEmpty);
        expect(await db.select(db.nodes).get(), isEmpty);
        await tester.ensureVisible(find.text('导入前确认'));
        await tester.pumpAndSettle();
        await screenshot('import-review');
        await tap(find.byKey(const ValueKey('toggle-compatibility-issues')));
        expect(find.text('收起原因'), findsOneWidget);
        await tap(url);
        await tester.enterText(url, 'https://example.test/edited');
        await tester.pumpAndSettle();
        expect(tester.widget<TextFormField>(url).controller?.text,
            'https://example.test/edited');
        expect(find.text('导入前确认'), findsNothing);
        await tap(find.byKey(const ValueKey('save-node')));
        expect(fetcher.calls, 2);
        expect(await db.select(db.nodeGroups).get(), isEmpty);
        await tap(find.byKey(const ValueKey('save-node')));
        expect(find.byType(NodeEditorDialog), findsNothing);
        expect(fetcher.calls, 2);
        final old = await db.select(db.nodes).getSingle();
        await menu('分组详情');
        expect(find.text('兼容信息'), findsOneWidget);
        expect(find.text('导入前确认'), findsNothing);
        expect(
            find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text('5.0 KB / 1.0 MB')),
            findsOneWidget);
        await screenshot('accepted-details');
        await tap(find.byTooltip('返回'));
        fetcher.document = SubscriptionDocument(
            name: '更新后的订阅',
            nodes: [subscriptionNode(name: '更新后的节点')],
            skippedNodes: 1,
            issues: const [
              SubscriptionIssue(
                  kind: SubscriptionIssueKind.unsupported,
                  item: 2,
                  reason: '暂不支持此附加字段')
            ]);
        await menu('更新订阅');
        expect(find.text('导入前确认'), findsOneWidget);
        expect((await db.select(db.nodes).getSingle()).id, old.id);
        await screenshot('update-review');
        await tap(find.byTooltip('返回'));
        expect((await db.select(db.nodes).getSingle()).id, old.id);
        await menu('更新订阅');
        await tap(find.text('确认更新'));
        expect(find.text('导入前确认'), findsNothing);
        expect((await db.select(db.nodes).getSingle()).name, '更新后的节点');
        expect(find.text('服务商未提供流量信息'), findsOneWidget);
        expect(find.text('未提供 / 未提供'), findsNothing);
        final container =
            ProviderScope.containerOf(tester.element(find.byType(RainlinkApp)));
        expect(container.read(sessionControllerProvider).connected, isFalse);
        await screenshot('updated-details');
        final retained = await db.select(db.nodes).getSingle();
        fetcher.handler = (url, _) async => parseSubscription(
            'unknown://private-password@edge.example.test:443\nhttp://edge.example.test:0',
            const {},
            url);
        await tap(find.text('更新订阅'));
        expect(find.textContaining('可导入 0 个节点'), findsOneWidget);
        expect(find.text('确认更新'), findsNothing);
        expect((await db.select(db.nodes).getSingle()).id, retained.id);
        await screenshot('unusable-update');
        await tap(find.byTooltip('返回'));
        await tap(find.text('添加订阅'));
        await tester.enterText(find.byKey(const ValueKey('subscription-url')),
            'https://example.test/unusable');
        await tap(find.byKey(const ValueKey('save-node')));
        expect(find.textContaining('可导入 0 个节点'), findsOneWidget);
        expect(find.text('确认导入'), findsNothing);
        expect(await db.select(db.nodeGroups).get(), hasLength(1));
        await tap(find.byTooltip('关闭'));
        expect((await db.select(db.nodes).getSingle()).id, retained.id);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }, variant: TargetPlatformVariant.only(platform));
    }
  }
}
