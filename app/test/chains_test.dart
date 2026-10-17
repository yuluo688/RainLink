import 'dart:async';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/chains/chain_providers.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/data/chains/chain_records.dart';
import 'package:rainlink/data/chains/drift_chain_repository.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/subscriptions/http_subscription_fetcher.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/routing/drift_route_repository.dart';
import 'package:rainlink/data/routing/drift_routing_resolver.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/routing/route_rules.dart';

class ChainFixtureTester implements ChainTester {
  Future<void> Function()? onValidate;
  Exception? failure;
  Completer<ChainTestResult>? pending;
  int cancellations = 0;
  @override
  Future<void> validateChain(ChainSnapshot chain) async {
    await onValidate?.call();
    if (failure case final error?) throw error;
  }

  @override
  Future<ChainTestResult> testChain(ChainSnapshot chain) =>
      (pending ??= Completer()).future;
  @override
  Future<void> cancelChainTest() async {
    cancellations++;
    final running = pending;
    if (running != null && !running.isCompleted) {
      running.completeError(const ChainException('已取消'));
    }
  }
}

class _Protector implements SecretStore {
  @override
  Future<NodeCredentials> reveal(String id, String cipher) async =>
      throw StateError('Manual grouping must not reveal credentials');
  @override
  Future<String> protect(String nodeId, String username, String password,
          {String obfsPassword = ''}) async =>
      'encrypted';
}

class _RulesValidator implements RouteRuleValidator {
  @override
  Future<void> validateRules(RouteRuleSet rules) async {}
}

class _Gateway implements CoreGateway {
  int connects = 0;
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    connects++;
    throw StateError('A cancelled request must not connect');
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<CoreStatus> inspect() async => const CoreStatus.unavailable('test');
  @override
  void dispose() {}
}

const chainNodes = [
  ProxyNode(
      id: 'entry',
      name: '办公 HTTP',
      protocol: NodeProtocol.http,
      server: '127.0.0.1',
      port: 8080),
  ProxyNode(
      id: 'exit',
      name: '东京 · 樱花',
      protocol: NodeProtocol.vless,
      server: 'example.test',
      port: 443,
      credential: 'encrypted-auth'),
];
ChainSnapshot draft({int revision = 0, List<ProxyNode> nodes = chainNodes}) =>
    ChainSnapshot(
        ProxyChain(
            id: 'chain',
            name: '开发代理链',
            revision: revision,
            hopIds: nodes.map((node) => node.id).toList()),
        nodes);
Future<void> seed(AppDatabase db) async {
  for (final node in chainNodes) {
    await db.into(db.nodes).insert(NodesCompanion.insert(
        id: node.id,
        name: node.name,
        protocol: node.protocol.wireName,
        server: node.server,
        port: node.port,
        credential: Value(node.credential)));
  }
}

void main() {
  test('selecting a group clears the chain and preserves its remembered node',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final nodes = DriftNodeRepository(db, _Protector());
    final groups =
        DriftGroupRepository(db, _Protector(), const HttpSubscriptionFetcher());
    final group = await groups.createManual('办公');
    await groups.moveUngrouped('entry', group);
    await nodes.select('entry');
    final repository = DriftChainRepository(db, ChainFixtureTester());
    await repository.save(draft());
    expect(await nodes.watchSelectedId().first, isNull);
    await groups.select(group);
    expect(await repository.watchSelectedId().first, isNull);
    expect(await nodes.watchSelectedId().first, 'entry');
    expect((await db.select(db.nodeGroups).getSingle()).lastSelectedNodeId,
        'entry');
  });

  test(
      'a partial or out-of-order response cannot report a successful chain test',
      () {
    final json = {
      'fingerprint': draft().fingerprint,
      'checkedAt': 1792140000000,
      'passed': true,
      'hops': [const ChainHopTest(hop: 1, latency: 12, passed: true).toJson()]
    };
    expect(
        () => ChainTestResult.fromJson(json), throwsA(isA<ChainException>()));
    json['hops'] = [
      const ChainHopTest(hop: 2, latency: 12, passed: true).toJson()
    ];
    expect(
        () => ChainTestResult.fromJson(json), throwsA(isA<ChainException>()));
    json['passed'] = false;
    json['hops'] = [
      const ChainHopTest(hop: 1, latency: 12, passed: true).toJson()
    ];
    expect(
        () => ChainTestResult.fromJson(json), throwsA(isA<ChainException>()));
  });
  test(
      'fingerprints expire on order and node revision, while names remain editable',
      () {
    final source = draft();
    expect(
        ChainSnapshot(
                source.chain.copyWith(name: '重命名', revision: 4), source.hops)
            .fingerprint,
        source.fingerprint);
    expect(draft(nodes: chainNodes.reversed.toList()).fingerprint,
        isNot(source.fingerprint));
    final updated = ProxyNode(
        id: 'exit',
        name: '东京',
        protocol: NodeProtocol.vless,
        server: 'example.test',
        port: 443,
        revision: 2);
    expect(draft(nodes: [chainNodes.first, updated]).fingerprint,
        isNot(source.fingerprint));
    expect(() => draft(nodes: [chainNodes.first, chainNodes.first]).validate(),
        throwsA(isA<ChainException>()));
    final quic = ProxyNode(
        id: 'quic',
        name: 'QUIC',
        protocol: NodeProtocol.hysteria2,
        server: 'example.test',
        port: 443,
        tls: true,
        options: const NodeOptions(transport: 'quic'));
    expect(() => draft(nodes: [chainNodes.first, quic]).validate(),
        throwsA(isA<ChainException>()));
    draft(nodes: [quic, chainNodes.first]).validate();
  });

  test(
      'saving persists IDs only, selects the chain, and node selection clears it',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final repository = DriftChainRepository(db, ChainFixtureTester());
    final nodes = DriftNodeRepository(db, _Protector());
    await nodes.select('entry');
    final saved = await repository.save(draft());
    expect(saved.revision, 1);
    expect(await repository.watchSelectedId().first, saved.id);
    expect(await nodes.watchSelectedId().first, isNull);
    final raw = await (db.select(db.preferences)
          ..where((row) => row.key.equals(chainsKey)))
        .getSingle();
    expect(raw.value, isNot(contains('encrypted-auth')));
    expect(raw.value, isNot(contains('example.test')));
    expect((await loadChains(db)).single.hopIds, ['entry', 'exit']);
    await nodes.select('exit');
    expect(await repository.watchSelectedId().first, isNull);
    await repository.select(saved);
    expect(await nodes.watchSelectedId().first, isNull);
  });

  test(
      'core failure and concurrent node changes preserve the saved chain and selection',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final tester = ChainFixtureTester();
    final repository = DriftChainRepository(db, tester);
    final saved = await repository.save(draft());
    tester.failure = const ChainException('核心拒绝');
    await expectLater(
        repository
            .save(ChainSnapshot(saved.copyWith(name: '不可保存'), chainNodes)),
        throwsA(isA<ChainException>()));
    expect((await loadChains(db)).single.name, saved.name);
    tester.failure = null;
    tester.onValidate = () async {
      await (db.update(db.nodes)..where((row) => row.id.equals('exit')))
          .write(const NodesCompanion(revision: Value(2)));
    };
    await expectLater(repository.save(ChainSnapshot(saved, chainNodes)),
        throwsA(isA<ChainException>()));
    expect((await loadChains(db)).single.revision, 1);
    expect(await repository.watchSelectedId().first, saved.id);
  });

  test(
      'stale edits and removed hops cannot silently replace or reroute a saved chain',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final repository = DriftChainRepository(db, ChainFixtureTester());
    final saved = await repository.save(draft());
    await repository
        .save(ChainSnapshot(saved.copyWith(name: '新版'), chainNodes));
    await expectLater(repository.save(ChainSnapshot(saved, chainNodes)),
        throwsA(isA<ChainException>()));
    await (db.delete(db.nodes)..where((row) => row.id.equals('exit'))).go();
    await expectLater(repository.select((await loadChains(db)).single),
        throwsA(isA<ChainException>()));
    expect((await loadChains(db)).single.hopIds, ['entry', 'exit']);
  });

  test(
      'primary and rule chains freeze every hop and invalidate bindings after node changes',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final saved =
        await DriftChainRepository(db, ChainFixtureTester()).save(draft());
    final rules = DriftRouteRepository(db, _RulesValidator());
    await rules.save(RouteRuleSet(revision: 0, rules: [
      RouteRule(
          id: 'fallback',
          kind: RouteRuleKind.match,
          value: '',
          target: RouteTarget(RouteTargetKind.chain, saved.id))
    ]));
    final resolver = DriftRoutingResolver(db, rules);
    final plan = await resolver.resolve(null, chain: saved);
    expect(plan.primaryChain?.hops.map((node) => node.id), ['entry', 'exit']);
    expect(plan.expectedBindings.length, 5);
    expect(plan.expectedBindings['chain:chain']?.revision, 1);
    expect(plan.expectedBindings['proxy/hop/1']?.id, 'exit');
    expect(plan.matchesBindings(plan.expectedBindings), isTrue);
    await (db.update(db.nodes)..where((row) => row.id.equals('exit')))
        .write(const NodesCompanion(revision: Value(2)));
    final changed = await resolver.resolve(null, chain: saved);
    expect(changed.matchesBindings(plan.expectedBindings), isFalse);
    expect(plan.primaryChain?.hops.last.revision, 1);
  });

  test(
      'saving discards a test for another path and deletion leaves rule references repairable',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final repository = DriftChainRepository(db, ChainFixtureTester());
    final test = ChainTestResult(
        fingerprint: draft().fingerprint,
        checkedAt: DateTime.now(),
        passed: true,
        hops: const [
          ChainHopTest(hop: 1, latency: 1, passed: true),
          ChainHopTest(hop: 2, latency: 2, passed: true)
        ]);
    final saved = await repository
        .save(draft(nodes: chainNodes.reversed.toList()), test: test);
    expect(saved.lastTest, isNull);
    final rules = DriftRouteRepository(db, _RulesValidator());
    await rules.save(RouteRuleSet(revision: 0, rules: [
      RouteRule(
          id: 'fallback',
          kind: RouteRuleKind.match,
          value: '',
          target: RouteTarget(RouteTargetKind.chain, saved.id))
    ]));
    await repository.delete(saved);
    expect(await repository.watchSelectedId().first, isNull);
    await expectLater(DriftRoutingResolver(db, rules).resolve(chainNodes.first),
        throwsA(isA<ChainException>()));
    expect((await rules.load()).rules.single.target.id, saved.id);
  });

  test('cancel discards late chain-test completion and keeps editor usable',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final tester = ChainFixtureTester();
    final controller =
        ChainEditorController(DriftChainRepository(db, tester), tester);
    addTearDown(controller.dispose);
    controller.load(draft().chain);
    final testing = controller.test(chainNodes);
    expect(controller.state.testing, isTrue);
    await controller.cancel();
    await testing;
    expect(controller.state.testing, isFalse);
    expect(controller.state.test, isNull);
    expect(controller.state.notice, '测试已取消');
    expect(tester.cancellations, 1);
  });

  test('cancel during chain resolution cannot start a delayed connection',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await seed(db);
    final saved =
        await DriftChainRepository(db, ChainFixtureTester()).save(draft());
    final gateway = _Gateway();
    final session = SessionController(gateway,
        routing: DriftRoutingResolver(
            db, DriftRouteRepository(db, _RulesValidator())),
        onMode: (_) {});
    addTearDown(session.dispose);
    final connecting = session.connectChain(saved, ProxyMode.global);
    await session.disconnect();
    await connecting;
    expect(session.state.phase, ConnectionPhase.idle);
    expect(gateway.connects, 0);
  });
}
