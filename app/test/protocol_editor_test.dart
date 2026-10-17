import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/design_system/widgets/rainlink_switch.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/features/nodes/presentation/node_editor_dialog.dart';
import 'support/subscription_fixtures.dart';

const _uuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';

void main() {
  testWidgets(
      'subscription paste only fills a draft, persists auto-update choice and ignores a late clipboard reply',
      (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    final secrets = TestSecretStore();
    final groups = DriftGroupRepository(db, secrets, TestSubscriptionFetcher());
    Completer<Map<String, Object?>>? pending;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return pending?.future ??
            {'text': 'https://example.test/clipboard-sub'};
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      await tester.pumpWidget(ProviderScope(
          overrides: [groupRepositoryProvider.overrideWithValue(groups)],
          child: MaterialApp(
              home: Scaffold(
                  body: Builder(
                      builder: (context) => TextButton(
                          onPressed: () =>
                              showNodeEditor(context, subscription: true),
                          child: const Text('添加')))))));
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('粘贴链接'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextFormField>(
                  find.byKey(const ValueKey('subscription-url')))
              .controller
              ?.text,
          'https://example.test/clipboard-sub');
      expect(await tester.runAsync(() => groups.watchGroups().first), isEmpty);
      await tester.tap(find.byType(RainlinkSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await tester.pumpAndSettle();
      expect(find.byType(NodeEditorDialog), findsNothing);
      expect(
          (await tester.runAsync(() => groups.watchGroups().first))!
              .single
              .autoUpdate,
          isFalse);
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      pending = Completer<Map<String, Object?>>();
      await tester.tap(find.text('粘贴链接'));
      await tester.pump();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      pending.complete({'text': 'https://example.test/late-secret'});
      await tester.pumpAndSettle();
      expect(find.byType(NodeEditorDialog), findsNothing);
      expect((await tester.runAsync(() => groups.watchGroups().first))!,
          hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(db.close);
    }
  });
  for (final protocol in [NodeProtocol.vmess, NodeProtocol.tuic]) {
    final mobile = protocol == NodeProtocol.tuic;
    testWidgets(
        '${protocol.label} editor validates and saves protocol-specific options',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          mobile ? const Size(393, 852) : const Size(960, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final db = AppDatabase(NativeDatabase.memory());
      final secrets = TestSecretStore();
      final repository = DriftNodeRepository(db, secrets);
      try {
        await tester.pumpWidget(ProviderScope(
            overrides: [nodeRepositoryProvider.overrideWithValue(repository)],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(mobile ? 1.3 : 1)),
                    child: child!),
                home: Scaffold(
                    body: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => showNodeEditor(context),
                            child: const Text('添加')))))));
        await tester.tap(find.text('添加'));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<NodeProtocol>));
        await tester.pumpAndSettle();
        await tester.tap(find.text(protocol.label).last);
        await tester.pumpAndSettle();
        Future<void> enter(String key, String value) async {
          final finder = find.byKey(ValueKey(key));
          await tester.ensureVisible(finder);
          await tester.enterText(finder, value);
          await tester.pump();
        }

        await enter('node-name', '协议表单验收');
        await enter('node-server', 'example.test');
        await enter('node-port', '443');
        if (mobile) {
          await enter('node-username', 'invalid-uuid');
          await enter('node-password', 'fixture-secret');
          await tester.tap(find.byKey(const ValueKey('save-node')));
          await tester.pumpAndSettle();
          expect(find.text('请输入有效的 TUIC UUID'), findsOneWidget);
          expect(await tester.runAsync(() => repository.watchNodes().first),
              isEmpty);
          await enter('node-username', _uuid);
        } else {
          expect(find.text('用户名'), findsNothing);
          await enter('node-password', _uuid);
        }
        await tester.ensureVisible(find.text('高级选项'));
        await tester.tap(find.text('高级选项'));
        await tester.pumpAndSettle();
        if (mobile) {
          expect(find.text('TLS 指纹'), findsNothing);
          expect(find.text('传输方式'), findsNothing);
          await enter('node-option-heartbeat', '1500');
          await tester.ensureVisible(find.text('不发送 SNI'));
          await tester.tap(find.text('不发送 SNI'));
          await tester.pumpAndSettle();
        } else {
          expect(find.text('传输方式'), findsOneWidget);
          await enter('node-option-alterId', '64');
          await tester.ensureVisible(find.text('长度块加密'));
          await tester.tap(find.text('长度块加密'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('save-node')));
        await tester.pumpAndSettle();
        expect(find.byType(NodeEditorDialog), findsNothing);
        final node =
            (await tester.runAsync(() => repository.watchNodes().first))!
                .single;
        expect(node.protocol, protocol);
        final auth = await secrets.reveal(node.id, node.credential);
        if (mobile) {
          expect(auth.username, _uuid);
          expect(auth.password, 'fixture-secret');
          expect(node.options.heartbeatMillis, 1500);
          expect(node.options.disableSni, isTrue);
          expect(node.options.transport, 'quic');
          expect(node.tls, isTrue);
        } else {
          expect(auth.password, _uuid);
          expect(node.options.alterId, 64);
          expect(node.options.authenticatedLength, isTrue);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(db.close);
      }
    },
        variant: TargetPlatformVariant.only(
            mobile ? TargetPlatform.android : TargetPlatform.windows));
  }
}
