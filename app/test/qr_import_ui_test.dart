import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/import/qr_import_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/import/qr_import_parser.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/features/nodes/presentation/node_editor_dialog.dart';
import 'package:rainlink/features/nodes/presentation/qr_import_dialog.dart';
import 'package:rainlink/platform/qr/qr_camera_session.dart';

import 'support/qr_fixtures.dart';
import 'support/subscription_fixtures.dart';

void main() {
  late AppDatabase database;
  late TestSecretStore secrets;
  late TestSubscriptionFetcher fetcher;
  late DriftNodeRepository nodes;
  late DriftGroupRepository groups;
  late FixtureQrCamera camera;
  var factoryCalls = 0;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    secrets = TestSecretStore();
    fetcher = TestSubscriptionFetcher();
    nodes = DriftNodeRepository(database, secrets);
    groups = DriftGroupRepository(database, secrets, fetcher);
    camera = FixtureQrCamera();
    factoryCalls = 0;
  });
  tearDown(() async {
    await camera.close();
    await database.close();
  });

  Future<void> settle(WidgetTester tester) async {
    // Camera callbacks and SQLite use real async work, outside frame scheduling.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<T> io<T extends Object>(
    WidgetTester tester,
    Future<T> Function() operation,
  ) async {
    final result = await tester.runAsync(operation);
    expect(result, isNotNull);
    return result!;
  }

  Future<void> pump(
    WidgetTester tester, {
    bool subscription = true,
    bool cameraAvailable = true,
    ProxyNode? node,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(960, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          qrImportParserProvider.overrideWithValue(
            const StandardQrImportParser(),
          ),
          qrCameraFactoryProvider.overrideWithValue(
            cameraAvailable
                ? () {
                  factoryCalls++;
                  return camera;
                }
                : null,
          ),
          nodeRepositoryProvider.overrideWithValue(nodes),
          groupRepositoryProvider.overrideWithValue(groups),
        ],
        child: MaterialApp(
          theme: buildRainlinkTheme(Brightness.dark),
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: TextButton(
                    onPressed:
                        () => showNodeEditor(
                          context,
                          node: node,
                          subscription: subscription,
                        ),
                    child: const Text('打开添加'),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开添加'));
    await settle(tester);
  }

  Future<void> scan(WidgetTester tester, String value) async {
    await tester.ensureVisible(find.byKey(const ValueKey('scan-import')));
    await tester.tap(find.byKey(const ValueKey('scan-import')));
    await settle(tester);
    camera.capture([value, value]);
    await settle(tester);
  }

  void uiTest(String name, WidgetTesterCallback callback) => testWidgets(
    name,
    callback,
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final entry in qrNodeLinks.entries) {
    uiTest(
      'scanned ${entry.key.label} previews without writes, then saves all fields',
      (tester) async {
        await pump(tester);
        expect(
          factoryCalls,
          0,
          reason: 'Opening the add form never opens camera',
        );
        await scan(tester, entry.value);
        expect(factoryCalls, 1);
        expect(camera.closes, 1);
        expect(find.byType(QrImportDialog), findsNothing);
        expect(find.byKey(const ValueKey('node-server')), findsOneWidget);
        expect(
          (tester.widget<TextFormField>(
            find.byKey(const ValueKey('node-server')),
          )).controller?.text,
          'proxy.example.test',
        );
        expect(
          await io(tester, () => database.select(database.nodes).get()),
          isEmpty,
        );
        expect(fetcher.calls, 0);
        await tester.tap(find.byKey(const ValueKey('save-node')));
        await io(
          tester,
          () => nodes
              .watchNodes()
              .firstWhere((values) => values.isNotEmpty)
              .timeout(const Duration(seconds: 5)),
        );
        await settle(tester);
        expect(find.byType(NodeEditorDialog), findsNothing);
        final saved = (await io(tester, () => nodes.watchNodes().first)).single;
        final expected = parseNodeUri(entry.value);
        expect(saved.groupId, isNull);
        expect(saved.protocol, expected.protocol);
        expect(saved.name, expected.name);
        expect(saved.server, expected.server);
        expect(saved.port, expected.port);
        expect(saved.tls, expected.tls);
        expect(saved.options.toJson(), expected.options.toJson());
        final secret = await secrets.reveal(saved.id, saved.credential);
        expect(secret.username, expected.username);
        expect(secret.password, expected.password);
        expect(secret.obfsPassword, expected.obfsPassword);
        expect(saved.toHost().toString(), isNot(contains('p@ss')));
        expect(await io(tester, () => groups.watchGroups().first), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  uiTest(
    'subscription scan waits for confirmation, then creates its own named group',
    (tester) async {
      await pump(tester, subscription: false);
      const url = 'https://provider.example.test/sub?token=private-fixture';
      await scan(tester, url);
      expect(find.byKey(const ValueKey('subscription-url')), findsOneWidget);
      expect(fetcher.calls, 0);
      expect(await io(tester, () => groups.watchGroups().first), isEmpty);
      expect(await io(tester, () => nodes.watchNodes().first), isEmpty);
      await tester.tap(find.byKey(const ValueKey('save-node')));
      await io(
        tester,
        () => groups
            .watchGroups()
            .firstWhere((values) => values.isNotEmpty)
            .timeout(const Duration(seconds: 5)),
      );
      await settle(tester);
      expect(fetcher.calls, 1);
      final savedGroup =
          (await io(tester, () => groups.watchGroups().first)).single;
      expect(savedGroup.name, '测试订阅');
      expect(savedGroup.total, isNotNull);
      expect(savedGroup.expiresAt, isNotNull);
      expect(
        (await io(tester, () => nodes.watchNodes().first)).single.groupId,
        savedGroup.id,
      );
      expect(find.byType(NodeEditorDialog), findsNothing);
    },
  );

  uiTest(
    'denied camera returns to the exact original form without touching clipboard',
    (tester) async {
      camera = FixtureQrCamera(initialStatus: QrCameraStatus.permissionDenied);
      var clipboardReads = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') clipboardReads++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pump(tester);
      await tester.enterText(
        find.byKey(const ValueKey('subscription-url')),
        'https://existing.example.test/sub',
      );
      await tester.tap(find.byKey(const ValueKey('scan-import')));
      await settle(tester);
      expect(find.textContaining('未获得相机权限'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('qr-return-paste')));
      await settle(tester);
      expect(find.byType(QrImportDialog), findsNothing);
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('subscription-url')),
            )
            .controller
            ?.text,
        'https://existing.example.test/sub',
      );
      expect(clipboardReads, 0);
      expect(fetcher.calls, 0);
      expect(camera.closes, 1);
    },
  );

  uiTest(
    'invalid and multiple codes can be corrected without reopening the camera',
    (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('scan-import')));
      await settle(tester);
      camera.capture([
        'https://one.example.test/sub',
        'https://two.example.test/sub',
      ]);
      await settle(tester);
      expect(find.textContaining('检测到多个二维码'), findsOneWidget);
      camera.capture(['not-a-link-private-fixture']);
      await settle(tester);
      expect(find.byKey(const ValueKey('qr-error')), findsOneWidget);
      expect(find.textContaining('private-fixture'), findsNothing);
      camera.capture([qrNodeLinks[NodeProtocol.trojan] ?? '']);
      await settle(tester);
      expect(find.byType(QrImportDialog), findsNothing);
      expect(find.byKey(const ValueKey('node-server')), findsOneWidget);
      expect(fetcher.calls, 0);
      expect(await io(tester, () => nodes.watchNodes().first), isEmpty);
    },
  );

  uiTest('bare HTTP URL requires a choice and cancel preserves the form', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(
      find.byKey(const ValueKey('subscription-url')),
      'https://existing.example.test/sub',
    );
    await scan(tester, 'http://proxy.example.test:80');
    expect(find.text('选择链接用途'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog).last,
        matching: find.text('取消'),
      ),
    );
    await settle(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('subscription-url')))
          .controller
          ?.text,
      'https://existing.example.test/sub',
    );
    expect(await io(tester, () => nodes.watchNodes().first), isEmpty);
    expect(fetcher.calls, 0);
  });

  uiTest('pause/resume follows lifecycle; top-left back releases camera once', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('scan-import')));
    await settle(tester);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(camera.activity.last, isFalse);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await settle(tester);
    expect(camera.activity.last, isTrue);
    await tester.tap(find.byKey(const ValueKey('qr-back')));
    await settle(tester);
    expect(camera.closes, 1);
    expect(find.byType(NodeEditorDialog), findsOneWidget);
  });

  uiTest('return does not wait for a pending permission/disposal response', (
    tester,
  ) async {
    final gate = Completer<void>();
    camera.closeGate = gate.future;
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('scan-import')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('qr-return-paste')));
    await settle(tester);
    expect(find.byType(QrImportDialog), findsNothing);
    expect(find.byType(NodeEditorDialog), findsOneWidget);
    gate.complete();
    await settle(tester);
    expect(camera.closes, 1);
  });

  uiTest(
    'editing never exposes a scan action that could replace node identity',
    (tester) async {
      await pump(
        tester,
        node: const ProxyNode(
          id: 'existing',
          name: 'existing',
          protocol: NodeProtocol.http,
          server: 'proxy.example.test',
          port: 8080,
        ),
      );
      expect(find.byKey(const ValueKey('scan-import')), findsNothing);
      expect(find.byKey(const ValueKey('paste-node-link')), findsNothing);
      expect(factoryCalls, 0);
    },
  );

  uiTest(
    'paste fallback works without camera support and does not save automatically',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.getData') {
              return {'text': qrNodeLinks[NodeProtocol.hysteria2]};
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await pump(tester, subscription: false, cameraAvailable: false);
      expect(find.byKey(const ValueKey('scan-import')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('paste-node-link')));
      await settle(tester);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('node-name')))
            .controller
            ?.text,
        'Hysteria2',
      );
      expect(await io(tester, () => nodes.watchNodes().first), isEmpty);
      expect(fetcher.calls, 0);
      expect(factoryCalls, 0);
    },
  );

  for (final label in ['HTTP 节点', '订阅地址']) {
    uiTest('ambiguous HTTP URL applies the explicit $label choice only', (
      tester,
    ) async {
      await pump(tester);
      await scan(tester, 'http://proxy.example.test:80');
      await tester.tap(
        find.widgetWithText(
          label == 'HTTP 节点' ? OutlinedButton : FilledButton,
          label,
        ),
      );
      await settle(tester);
      expect(
        find.byKey(
          ValueKey(label == 'HTTP 节点' ? 'node-port' : 'subscription-url'),
        ),
        findsOneWidget,
      );
      expect(await io(tester, () => nodes.watchNodes().first), isEmpty);
      expect(fetcher.calls, 0);
    });
  }
}
