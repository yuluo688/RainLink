import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/traffic/drift_traffic_repository.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

class _Protector implements CredentialProtector {
  int calls = 0;
  bool fail = false;
  @override
  Future<String> protect(String id, String username, String password,
      {String obfsPassword = ''}) async {
    calls++;
    if (fail) throw const NodeException('无法加密凭据');
    return 'protected-ciphertext-$id';
  }
}

NodeDraft draft(
        {ProxyNode? original, bool auth = false, String password = ''}) =>
    NodeDraft(
        name: '测试节点',
        protocol: NodeProtocol.http,
        server: '127.0.0.1',
        port: 8080,
        authenticate: auth,
        password: password,
        original: original);

void main() {
  test(
      'node and selection persist across database reopen; delete clears selection',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('rainlink-node-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/nodes.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    final protector = _Protector();
    var repository = DriftNodeRepository(database, protector);
    final node =
        await repository.save(draft(auth: true, password: 'fixture-password'));
    await repository.select(node.id);
    final raw = await database.select(database.nodes).getSingle();
    expect(raw.credential, startsWith('protected-ciphertext-'));
    expect(raw.credential, isNot(contains('fixture-password')));
    await database.close();
    database = AppDatabase(NativeDatabase(file));
    addTearDown(database.close);
    repository = DriftNodeRepository(database, protector);
    expect((await repository.watchNodes().first).single.id, node.id);
    expect(await repository.watchSelectedId().first, node.id);
    await repository.delete(node.id);
    expect(await repository.watchNodes().first, isEmpty);
    expect(await repository.watchSelectedId().first, isNull);
  });

  test('migration from v1 preserves theme and adds node storage', () async {
    final database = AppDatabase(NativeDatabase.memory(setup: (sqlite) {
      sqlite.execute(
          'CREATE TABLE preferences (key TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)');
      sqlite.execute("INSERT INTO preferences VALUES ('theme', 'dark')");
      sqlite.execute('PRAGMA user_version = 1');
    }));
    addTearDown(database.close);
    final repository = DriftNodeRepository(database, _Protector());
    await repository.save(draft());
    expect((await database.select(database.preferences).getSingle()).value,
        'dark');
    expect(await repository.watchNodes().first, hasLength(1));
  });

  test('edit preserves encrypted credentials and rejects stale revisions',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final protector = _Protector();
    final repository = DriftNodeRepository(database, protector);
    final first = await repository.save(draft(auth: true, password: 'fixture'));
    final second = await repository.save(draft(original: first, auth: true));
    expect(second.revision, 2);
    expect(second.credential, first.credential);
    expect(protector.calls, 1);
    await expectLater(
        repository.save(draft(original: first)), throwsA(isA<NodeException>()));
    expect((await repository.watchNodes().first).single.revision, 2);
  });

  test('invalid input and protection failure never insert a node', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final protector = _Protector()..fail = true;
    final repository = DriftNodeRepository(database, protector);
    for (final server in [
      'https://example.com/path',
      'example.com:80',
      'bad host'
    ]) {
      await expectLater(
          repository.save(NodeDraft(
              name: 'x',
              protocol: NodeProtocol.http,
              server: server,
              port: 80)),
          throwsA(isA<NodeException>()));
    }
    await expectLater(repository.save(draft(auth: true, password: 'fixture')),
        throwsA(isA<NodeException>()));
    expect(await repository.watchNodes().first, isEmpty);
  });

  test(
      'protocol changes require new secrets and persist VLESS TLS transport options',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = DriftNodeRepository(database, _Protector());
    final http =
        await repository.save(draft(auth: true, password: 'old-http-password'));
    await expectLater(
        repository.save(NodeDraft(
            name: 'VLESS',
            protocol: NodeProtocol.vless,
            server: 'example.test',
            port: 443,
            original: http)),
        throwsA(isA<NodeException>()));
    final vless = await repository.save(NodeDraft(
        name: 'VLESS',
        protocol: NodeProtocol.vless,
        server: 'example.test',
        port: 443,
        tls: true,
        password: 'a6db2f50-361a-4294-8bce-1df5f356764f',
        options: const NodeOptions(
            transport: 'ws',
            path: '/tunnel',
            host: 'edge.example.test',
            serverName: 'edge.example.test'),
        original: http));
    final saved = (await repository.watchNodes().first).single;
    expect(saved.id, http.id);
    expect(saved.protocol, NodeProtocol.vless);
    expect(saved.tls, isTrue);
    expect(saved.options.path, '/tunnel');
    expect(saved.options.host, 'edge.example.test');
    expect(saved.options.transport, 'ws');
    expect(vless.revision, http.revision + 1);
  });

  test('traffic totals count deltas once across reconnects and day rollover',
      () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var now = DateTime(2026, 10, 16, 23);
    final traffic = DriftTrafficRepository(database, now: () => now);
    await traffic.record('a', 10, 100);
    await traffic.record('a', 10, 100);
    await traffic.record('a', 20, 150);
    expect((await traffic.watchToday().first).total, 170);
    await traffic.record('b', 5, 20);
    expect((await traffic.watchToday().first).total, 195);
    now = DateTime(2026, 10, 17, 0, 1);
    await traffic.record('b', 8, 30);
    expect((await traffic.watchToday().first).total, 13);
  });
}
