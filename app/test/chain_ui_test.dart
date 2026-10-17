import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/data/chains/chain_records.dart';
import 'package:rainlink/data/chains/drift_chain_repository.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/features/chain/presentation/chain_page.dart';

const _nodes = [
  ProxyNode(
      id: 'http',
      name: '办公 HTTP',
      protocol: NodeProtocol.http,
      server: '127.0.0.1',
      port: 8080),
  ProxyNode(
      id: 'vless',
      name: '东京 · 樱花',
      protocol: NodeProtocol.vless,
      server: 'jp.example.test',
      port: 443),
  ProxyNode(
      id: 'hy2',
      name: 'Hysteria2',
      protocol: NodeProtocol.hysteria2,
      server: 'hy.example.test',
      port: 443),
];

class _Tester implements ChainTester {
  Exception? failure;
  final pending = Completer<ChainTestResult>();
  @override
  Future<void> validateChain(ChainSnapshot chain) async {
    if (failure case final error?) throw error;
  }

  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) => pending.future;
  @override
  Future<void> cancelChainTest() async {
    if (!pending.isCompleted) {
      pending.completeError(const ChainException('已取消'));
    }
  }
}

Future<(AppDatabase, _Tester)> _pump(WidgetTester tester,
    {Size size = const Size(960, 640), double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  for (final node in _nodes) {
    await database.into(database.nodes).insert(NodesCompanion.insert(
        id: node.id,
        name: node.name,
        protocol: node.protocol.wireName,
        server: node.server,
        port: node.port));
  }
  final core = _Tester();
  final repository = DriftChainRepository(database, core);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        chainTesterProvider.overrideWithValue(core),
        chainRepositoryProvider.overrideWithValue(repository),
        nodesProvider.overrideWith((_) => Stream.value(_nodes))
      ],
      child: MaterialApp(
          theme: buildRainlinkTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const Scaffold(body: ChainPage()))));
  await tester.pumpAndSettle();
  return (database, core);
}

Future<void> _add(WidgetTester tester, String id) async {
  final add = find.byKey(const ValueKey('chain-add-hop'));
  await tester.ensureVisible(add);
  await tester.tap(add);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('chain-pick-$id')));
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(db.close);
}

void main() {
  testWidgets(
      'node search, duplicate prevention, order and save persist the visible chain',
      (tester) async {
    final (db, _) = await _pump(tester);
    await _add(tester, 'http');
    await tester.tap(find.byKey(const ValueKey('chain-add-hop')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('chain-pick-http')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<ListTile>(find.byKey(const ValueKey('chain-pick-hy2')))
            .enabled,
        isFalse);
    await tester.enterText(
        find.byKey(const ValueKey('chain-node-search')), 'VLESS');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-pick-http')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chain-pick-vless')));
    await tester.pumpAndSettle();
    final path = find.byKey(const ValueKey('chain-path'));
    expect(tester.widget<Text>(path).data, '本机 → 办公 HTTP → 东京 · 樱花 → 目标');
    await tester.ensureVisible(find.text('下移').first);
    await tester.tap(find.text('下移').first);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(path).data, '本机 → 东京 · 樱花 → 办公 HTTP → 目标');
    await tester.ensureVisible(find.byKey(const ValueKey('chain-save')));
    await tester.tap(find.byKey(const ValueKey('chain-save')));
    await tester.pumpAndSettle();
    expect((await loadChains(db)).single.hopIds, ['vless', 'http']);
    expect(find.text('已保存并选中，请到概览连接'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('chain-library')));
    await tester.tap(find.byKey(const ValueKey('chain-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建代理链'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-hop-http')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('chain-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新代理链').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chain-hop-http')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chain-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除当前代理链'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();
    expect(await loadChains(db), isEmpty);
    expect(tester.takeException(), isNull);
    await _dispose(tester, db);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'core rejection preserves the editable draft and reports the failure',
      (tester) async {
    final (db, core) = await _pump(tester);
    await _add(tester, 'http');
    await _add(tester, 'vless');
    core.failure = const ChainException('核心未通过链路校验');
    await tester.ensureVisible(find.byKey(const ValueKey('chain-save')));
    await tester.tap(find.byKey(const ValueKey('chain-save')));
    await tester.pumpAndSettle();
    expect(await loadChains(db), isEmpty);
    expect(find.text('核心未通过链路校验'), findsOneWidget);
    expect(find.byKey(const ValueKey('chain-hop-http')), findsOneWidget);
    await _dispose(tester, db);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'mobile editor remains compact and usable with enlarged Chinese text',
      (tester) async {
    final (db, _) = await _pump(tester, size: const Size(393, 852), scale: 1.3);
    await _add(tester, 'http');
    await _add(tester, 'vless');
    await tester.ensureVisible(find.byKey(const ValueKey('chain-test')));
    await tester.tap(find.byKey(const ValueKey('chain-test')));
    await tester.pump();
    expect(find.text('取消测试'), findsOneWidget);
    await tester.tap(find.text('取消测试'));
    await tester.pumpAndSettle();
    expect(find.text('测试已取消'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _dispose(tester, db);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
