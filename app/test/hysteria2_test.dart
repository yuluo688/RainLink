import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/node_validation.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

import 'support/subscription_fixtures.dart';

void main() {
  final source = Uri.parse('https://example.test/sub');
  const yaml = '''
proxies:
  - name: 日本 Hysteria2
    type: hysteria2
    server: jp.example.test
    port: 443
    password: fixture-auth
    sni: edge.example.test
    alpn: [h3]
    skip-cert-verify: true
    obfs: salamander
    obfs-password: fixture-obfs
    up: 100 Mbps
    down: 250
    ports: 20000-30000,443
    hop-interval: 30
''';

  test('Clash Hysteria2 nodes are imported with QUIC options and two secrets',
      () {
    final document = parseSubscription(yaml, const {}, source);
    expect(document.skippedNodes, 0);
    final node = document.nodes.single;
    expect(node.protocol, NodeProtocol.hysteria2);
    expect(node.tls, isTrue);
    expect(node.password, 'fixture-auth');
    expect(node.obfsPassword, 'fixture-obfs');
    expect(node.options.transport, 'quic');
    expect(node.options.serverName, 'edge.example.test');
    expect(node.options.insecure, isTrue);
    expect(node.options.alpn, ['h3']);
    expect(node.options.upMbps, 100);
    expect(node.options.downMbps, 250);
    expect(node.options.serverPorts, ['20000:30000', '443']);
    expect(node.options.hopIntervalSeconds, 30);
    final encoded = node.options.toJson();
    expect(encoded.toString(), isNot(contains('fixture-auth')));
    expect(encoded.toString(), isNot(contains('fixture-obfs')));
    expect(NodeOptions.fromJson(encoded).toJson(), encoded);
  });

  test('hy2 and hysteria2 URI aliases preserve encoded auth and default TLS',
      () {
    for (final scheme in ['hy2', 'hysteria2']) {
      final node = parseNodeUri(
          '$scheme://user%3Ap%40ss@example.test/?sni=edge.example.test&obfs=salamander&obfs-password=m%2Bix&insecure=1&mport=20000-30000,443&hop-interval=30#%E6%97%A5%E6%9C%AC');
      expect(node.port, 443);
      expect(node.name, '日本');
      expect(node.password, 'user:p@ss');
      expect(node.obfsPassword, 'm+ix');
      expect(node.options.insecure, isTrue);
      expect(node.options.serverPorts, ['20000:30000', '443']);
    }
  });

  test('provider certificate pins and duplicate port aliases retain semantics',
      () {
    final pin = List.filled(32, 'ab').join();
    final colonPin = List.filled(32, 'AB').join(':');
    final doc = parseSubscription('''
proxies:
  - name: HY2 provider fixture
    type: hysteria2
    server: example.test
    port: 35000
    password: fixture-auth
    sni: edge.example.test
    udp: true
    skip-cert-verify: true
    fingerprint: $colonPin
    ports: 35000-39000
    mport: 35000-39000
''', const {}, source);
    final node = doc.nodes.single;
    expect(doc.skippedNodes, 0);
    expect(node.options.certificateSha256, pin);
    expect(node.options.insecure, isTrue);
    expect(node.options.serverPorts, ['35000:39000']);
    final uri = parseNodeUri('hy2://fixture@example.test/?pinSHA256=$pin');
    expect(uri.options.certificateSha256, pin);
    expect(NodeOptions.fromJson(node.options.toJson()).certificateSha256, pin);
    expect(() => parseSubscription('''
proxies:
  - {name: conflict, type: hy2, server: example.test, port: 443, password: fixture, ports: 20000-30000, mport: 40000-50000}
''', const {}, source), throwsA(isA<NodeException>()));
  });

  test('invalid or unsupported Hysteria2 settings fail without leaking secrets',
      () {
    for (final suffix in [
      '?obfs=salamander',
      '?obfs=unknown&obfs-password=hidden',
      '?pinSHA256=hidden',
      '?sni=a&sni=b',
      '?up=-1',
      '?mport=65536',
      '?mport=30000-20000',
      '?mport=20000-30000&hop-interval=1',
      '?hop-interval=10',
    ]) {
      expect(
          () => parseNodeUri('hy2://hidden@example.test:443/$suffix'),
          throwsA(isA<NodeException>().having(
              (e) => e.message, 'redacted', isNot(contains('hidden')))));
    }
    for (final fields in [
      'tls: false',
      'network: ws',
      'obfs: salamander',
      'client-fingerprint: chrome',
      'up: invalid',
      'fingerprint: fixture-pin',
    ]) {
      expect(
          () => parseSubscription(
              'proxies: [{name: invalid, type: hysteria2, server: example.test, port: 443, password: hidden, $fields}]',
              const {},
              source),
          throwsA(isA<NodeException>()));
    }
    expect(
        () => validateNode(const NodeDraft(
            name: 'invalid',
            protocol: NodeProtocol.hysteria2,
            server: 'example.test',
            port: 443,
            password: 'fixture')),
        throwsA(isA<NodeException>()));
  });

  test(
      'subscription refresh adds HY2 while preserving previous selection and encrypted secrets',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = TestSecretStore();
    final fetcher = TestSubscriptionFetcher();
    final nodes = DriftNodeRepository(db, secrets);
    final groups = DriftGroupRepository(db, secrets, fetcher);
    final id =
        await groups.importUrl(source.toString(), SubscriptionCancellation());
    final existing = (await nodes.watchNodes().first).single;
    await nodes.select(existing.id);
    final hy2 = parseSubscription(yaml, const {}, source).nodes.single;
    fetcher.document = subscriptionDocument(nodes: [subscriptionNode(), hy2]);
    await groups.refresh(id, SubscriptionCancellation());
    var imported = (await nodes.watchNodes().first)
        .singleWhere((n) => n.protocol == NodeProtocol.hysteria2);
    expect(await nodes.watchSelectedId().first, existing.id);
    expect((await db.select(db.nodes).get()).toString(),
        isNot(contains('fixture-obfs')));
    final auth = await secrets.reveal(imported.id, imported.credential);
    expect(auth.password, 'fixture-auth');
    expect(auth.obfsPassword, 'fixture-obfs');
    final cipher = imported.credential;
    final revision = imported.revision;
    final importedId = imported.id;
    await groups.refresh(id, SubscriptionCancellation());
    imported =
        (await nodes.watchNodes().first).singleWhere((n) => n.id == importedId);
    expect(imported.credential, cipher);
    expect(imported.revision, revision);
    fetcher.document = subscriptionDocument(nodes: [
      subscriptionNode(),
      parseSubscription(
              yaml.replaceAll('fixture-obfs', 'rotated-obfs'), const {}, source)
          .nodes
          .single
    ]);
    await groups.refresh(id, SubscriptionCancellation());
    imported =
        (await nodes.watchNodes().first).singleWhere((n) => n.id == importedId);
    expect(imported.revision, revision + 1);
    expect(
        (await secrets.reveal(imported.id, imported.credential)).obfsPassword,
        'rotated-obfs');
  });

  test(
      'manual editing preserves both encrypted secrets only when left together',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = TestSecretStore();
    final nodes = DriftNodeRepository(db, secrets);
    final draft = parseSubscription(yaml, const {}, source).nodes.single;
    final first = await nodes.save(draft);
    NodeDraft edit({String password = '', String obfs = ''}) => NodeDraft(
        name: first.name,
        protocol: first.protocol,
        server: first.server,
        port: first.port,
        tls: first.tls,
        options: first.options,
        password: password,
        obfsPassword: obfs,
        original: first);
    await expectLater(nodes.save(edit(password: 'replacement')),
        throwsA(isA<NodeException>()));
    final edited = await nodes.save(edit());
    expect(edited.credential, first.credential);
    expect((await secrets.reveal(edited.id, edited.credential)).obfsPassword,
        'fixture-obfs');
  });
}
