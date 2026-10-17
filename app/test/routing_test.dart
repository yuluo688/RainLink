import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/nodes/node_records.dart';
import 'package:rainlink/data/routing/drift_route_repository.dart';
import 'package:rainlink/data/routing/drift_routing_resolver.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/routing/route_rules.dart';
import 'package:rainlink/domain/routing/routing_plan.dart';
import 'package:rainlink/platform/core/host_session_client.dart';

class _Validator implements RouteRuleValidator {
  Exception? failure;
  Future<void> Function()? onValidate;
  int calls = 0;
  @override
  Future<void> validateRules(RouteRuleSet rules) async {
    calls++;
    await onValidate?.call();
    if (failure case final error?) throw error;
  }
}

RouteRule rule(String id, RouteRuleKind kind, String value,
        {String target = 'proxy', bool enabled = true}) =>
    RouteRule(
        id: id,
        kind: kind,
        value: value,
        target: RouteTarget.parse(target),
        enabled: enabled);

RouteRuleSet ruleSet(List<RouteRule> rules, {int revision = 0}) => RouteRuleSet(
    revision: revision,
    rules: [...rules, rule('fallback', RouteRuleKind.match, '')]);

Future<ProxyNode> insertNode(AppDatabase database, String id,
    {String? group, int revision = 1}) async {
  await database.into(database.nodes).insert(NodesCompanion.insert(
      id: id,
      name: id,
      protocol: 'http',
      server: '127.0.0.1',
      port: 8080,
      groupId: Value(group),
      revision: Value(revision)));
  return nodeFromRecord(await (database.select(database.nodes)
        ..where((row) => row.id.equals(id)))
      .getSingle());
}

class _Gateway implements CoreGateway {
  int connects = 0;
  @override
  Future<CoreStatus> inspect() async => const CoreStatus.unavailable('test');
  @override
  Future<ActiveConnectionSnapshot> connect(ConnectRequest request) async {
    connects++;
    return ActiveConnectionSnapshot(
        sessionId: 'test',
        target: request.target,
        mode: request.mode,
        configRevision: 'test');
  }

  @override
  Future<void> disconnect() async {}
  @override
  void dispose() {}
}

class _WaitingResolver implements RoutingResolver {
  final pending = Completer<RoutingPlan>();
  @override
  Future<RoutingPlan> resolve(ProxyNode? node, {ProxyChain? chain}) =>
      pending.future;
}

void main() {
  test('rules normalize domain, IPv4 and IPv6 at the boundary', () {
    expect(normalizeRuleValue(RouteRuleKind.domainSuffix, ' GitHub.COM. '),
        'github.com');
    expect(normalizeRuleValue(RouteRuleKind.ipCidr, '192.168.1.123/16'),
        '192.168.0.0/16');
    expect(normalizeRuleValue(RouteRuleKind.ipCidr, '2001:db8:1::1234/32'),
        '2001:db8::/32');
    expect(normalizeRuleValue(RouteRuleKind.ipCidr, '::1/0'), '::/0');
    for (final value in [
      'https://github.com/path',
      '*.github.com',
      'a..com',
      '-bad.test',
      'bad_.test',
      '127.0.0.1',
      '中文.中国',
      'a' * 64
    ]) {
      expect(() => normalizeRuleValue(RouteRuleKind.domain, value),
          throwsA(isA<RoutingException>()));
    }
    for (final value in [
      '1.1.1.1',
      '192.168.0.1/33',
      '2001:db8::/129',
      'fe80::1%lo/64',
      '1.1.1.1/-1'
    ]) {
      expect(() => normalizeRuleValue(RouteRuleKind.ipCidr, value),
          throwsA(isA<RoutingException>()));
    }
  });

  test(
      'unique enabled final fallback and bounded rule/target count are enforced',
      () {
    final fallback = rule('fallback', RouteRuleKind.match, '');
    final domain = rule('domain', RouteRuleKind.domain, 'example.com');
    for (final rules in <List<RouteRule>>[
      [],
      [domain],
      [fallback, domain],
      [fallback, fallback],
      [fallback.copyWith(enabled: false)],
      [domain, domain, fallback],
      [rule('bad', RouteRuleKind.match, 'not-empty')],
      [
        for (var i = 0; i < 257; i++)
          rule('r$i', RouteRuleKind.domain, 'x$i.test'),
        fallback
      ],
      [
        for (var i = 0; i < 33; i++)
          rule('r$i', RouteRuleKind.domain, 'x$i.test', target: 'group:g$i'),
        fallback
      ],
    ]) {
      expect(() => RouteRuleSet(revision: 0, rules: rules).validated(),
          throwsA(isA<RoutingException>()));
    }
    expect(RouteRuleSet.defaults().validated().rules.last.kind,
        RouteRuleKind.match);
    expect(() => RouteTarget.parse('node:../config'),
        throwsA(isA<RoutingException>()));
  });

  test(
      'rules persist, normalize and reject stale or failed writes without replacing data',
      () async {
    final directory = await Directory.systemTemp.createTemp('rainlink-rules-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/test.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    final validator = _Validator();
    var repository = DriftRouteRepository(database, validator);
    final draft =
        ruleSet([rule('github', RouteRuleKind.domainSuffix, 'GitHub.COM.')]);
    await repository.save(draft);
    expect((await repository.load()).revision, 1);
    await expectLater(repository.save(draft), throwsA(isA<RoutingException>()));
    final saved = await repository.load();
    validator.failure = const RoutingException('核心拒绝');
    await expectLater(repository.save(ruleSet([], revision: 1)),
        throwsA(isA<RoutingException>()));
    expect(jsonEncode((await repository.load()).toJson()),
        jsonEncode(saved.toJson()));
    await database.close();
    database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    repository = DriftRouteRepository(database, _Validator());
    final reloaded = await repository.load();
    expect(reloaded.rules.first.value, 'github.com');
    expect(reloaded.revision, 1);
  });

  test(
      'references are checked after async validation and invalid writes roll back',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final node = await insertNode(database, 'temporary');
    final validator = _Validator()
      ..onValidate = () async {
        await (database.delete(database.nodes)
              ..where((row) => row.id.equals(node.id)))
            .go();
      };
    final repository = DriftRouteRepository(database, validator);
    await expectLater(
        repository.save(ruleSet([
          rule('ref', RouteRuleKind.domain, 'example.com',
              target: 'node:${node.id}')
        ])),
        throwsA(isA<RoutingException>()));
    expect((await repository.load()).revision, 0);
    expect(
        await (database.select(database.preferences)
              ..where((row) => row.key.equals(routeRulesKey)))
            .get(),
        isEmpty);
    // A disabled dangling reference can be saved and repaired later.
    await repository.save(ruleSet([
      rule('ref', RouteRuleKind.domain, 'example.com',
          target: 'node:${node.id}', enabled: false)
    ]));
    expect((await repository.load()).revision, 1);
  });

  test(
      'corrupt stored rules surface an error instead of silently resetting routing',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.preferences).insert(
        PreferencesCompanion.insert(key: routeRulesKey, value: 'broken json'));
    await expectLater(DriftRouteRepository(database, _Validator()).load(),
        throwsA(isA<RoutingException>()));
  });

  test(
      'resolver freezes group memory and falls back deterministically when it disappears',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final selected = await insertNode(database, 'selected');
    await database.into(database.nodeGroups).insert(NodeGroupsCompanion.insert(
        id: 'work',
        name: '工作',
        kind: 'manual',
        lastSelectedNodeId: const Value('b')));
    await insertNode(database, 'a', group: 'work');
    await insertNode(database, 'b', group: 'work', revision: 2);
    final repository = DriftRouteRepository(database, _Validator());
    await repository.save(ruleSet([
      rule('work', RouteRuleKind.domain, 'example.com', target: 'group:work'),
      rule('same', RouteRuleKind.domainSuffix, 'example.test',
          target: 'group:work'),
    ]));
    final resolver = DriftRoutingResolver(database, repository);
    final first = await resolver.resolve(selected);
    expect(first.outbounds, hasLength(1));
    expect(first.outbounds.single.node?.id, 'b');
    expect(first.outbounds.single.node?.revision, 2);
    await (database.delete(database.nodes)..where((row) => row.id.equals('b')))
        .go();
    final next = await resolver.resolve(selected);
    expect(next.outbounds.single.node?.id, 'a');
    expect(first.outbounds.single.node?.id, 'b');
    await (database.delete(database.nodes)..where((row) => row.id.equals('a')))
        .go();
    await expectLater(
        resolver.resolve(selected), throwsA(isA<RoutingException>()));
    expect((await repository.load()).revision, 1);
  });

  test('resolver refuses stale default nodes and removed rule targets',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final selected = await insertNode(database, 'selected');
    final target = await insertNode(database, 'target');
    final repository = DriftRouteRepository(database, _Validator());
    await repository.save(ruleSet([
      rule('ref', RouteRuleKind.domain, 'example.com',
          target: 'node:${target.id}')
    ]));
    final resolver = DriftRoutingResolver(database, repository);
    await (database.delete(database.nodes)
          ..where((row) => row.id.equals(target.id)))
        .go();
    await expectLater(
        resolver.resolve(selected), throwsA(isA<RoutingException>()));
    await (database.update(database.nodes)
          ..where((row) => row.id.equals(selected.id)))
        .write(const NodesCompanion(revision: Value(2)));
    await expectLater(
        resolver.resolve(selected), throwsA(isA<RoutingException>()));
  });

  test('rule moves preserve absolute order and cannot move or remove fallback',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftRouteRepository(database, _Validator());
    final controller = RulesController(repository);
    addTearDown(controller.dispose);
    await controller.save(ruleSet([
      rule('a', RouteRuleKind.domain, 'a.test'),
      rule('b', RouteRuleKind.domain, 'b.test'),
    ]));
    expect(await controller.move(await repository.load(), 'b', -1), isTrue);
    final current = await repository.load();
    expect(current.rules.map((rule) => rule.id), ['b', 'a', 'fallback']);
    expect(await controller.move(current, 'fallback', -1), isFalse);
    expect(await controller.move(current, 'a', 1), isFalse);
    expect(await controller.remove(current, 'fallback'), isFalse);
    expect((await repository.load()).revision, 2);
  });

  test('cancelling while routing resolves never starts a late core', () async {
    final gateway = _Gateway();
    final resolver = _WaitingResolver();
    final controller =
        SessionController(gateway, routing: resolver, onMode: (_) {});
    addTearDown(controller.dispose);
    const selected = ProxyNode(
        id: 'selected',
        name: 'selected',
        protocol: NodeProtocol.http,
        server: '127.0.0.1',
        port: 80);
    final connecting = controller.connect(selected, ProxyMode.rule);
    expect(controller.state.phase, ConnectionPhase.starting);
    await controller.disconnect();
    resolver.pending
        .complete(RoutingPlan(ruleSet: RouteRuleSet.defaults(), outbounds: []));
    await connecting;
    expect(gateway.connects, 0);
    expect(controller.state.phase, ConnectionPhase.idle);
  });

  test(
      'oversize UTF8 requests fail before opening or corrupting a host channel',
      () async {
    final client = HostSessionClient('intentionally-missing-host');
    addTearDown(client.close);
    await expectLater(
        client.request('validateRules', {'text': '中' * 50000}),
        throwsA(isA<CoreGatewayException>()
            .having((error) => error.code, 'code', 'request_too_large')));
    expect(client.terminated, isFalse);
  });
}
