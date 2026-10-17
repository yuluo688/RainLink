import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/node_validation.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'support/subscription_fixtures.dart';

const _uuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';
final _source = Uri.parse('https://example.test/sub');
String _vmess(Map<String, Object?> fields) =>
    'vmess://${base64Url.encode(utf8.encode(jsonEncode({
          'v': '2',
          'ps': '日本 VMess',
          'add': 'jp.example.test',
          'port': '443',
          'id': _uuid,
          'aid': '0',
          'net': 'ws',
          'type': 'none',
          'tls': 'tls',
          'path': '/ws',
          'host': 'edge.example.test',
          ...fields,
        })))}';

void main() {
  test('VMess Base64 JSON preserves AEAD, TLS, transport and optional flags',
      () {
    final encoded = _vmess({
      'scy': 'chacha20-poly1305',
      'fp': 'chrome',
      'alpn': 'h2,http/1.1',
      'globalPadding': true,
      'authenticatedLength': true,
      'packetEncoding': 'xudp'
    });
    final node = parseNodeUri(encoded);
    expect(node.protocol, NodeProtocol.vmess);
    expect(node.name, '日本 VMess');
    expect(node.password, _uuid);
    expect(node.tls, isTrue);
    expect(node.options.transport, 'ws');
    expect(node.options.path, '/ws');
    expect(node.options.serverName, 'edge.example.test');
    expect(node.options.vmessSecurity, 'chacha20-poly1305');
    expect(node.options.alterId, 0);
    expect(node.options.globalPadding, isTrue);
    expect(node.options.authenticatedLength, isTrue);
    expect(node.options.packetEncoding, 'xudp');
    expect(node.options.alpn, ['h2', 'http/1.1']);
    final subscription = parseSubscription(
        base64.encode(utf8.encode(encoded)), const {}, _source);
    expect(subscription.nodes.single.password, _uuid);
    final grpc = parseNodeUri(_vmess(
        {'net': 'grpc', 'path': 'rainlink', 'sni': 'grpc.example.test'}));
    expect(grpc.options.serviceName, 'rainlink');
    final legacy = parseNodeUri(
        'vmess://$_uuid@example.test:8080?encryption=auto&alterId=64');
    expect(legacy.options.alterId, 64);
    expect(legacy.tls, isFalse);
  });

  test('TUIC v5 URI retains separately protected UUID and encoded password',
      () {
    final node = parseNodeUri(
        'tuic://$_uuid:p%40ss%3Aword@example.test/?sni=edge.example.test&alpn=h3&congestion_control=bbr&udp_relay_mode=quic&heartbeat=1500ms&disable_sni=true&allow_insecure=1#%E6%97%A5%E6%9C%AC');
    expect(node.name, '日本');
    expect(node.username, _uuid);
    expect(node.password, 'p@ss:word');
    expect(node.port, 443);
    expect(node.tls, isTrue);
    expect(node.options.transport, 'quic');
    expect(node.options.congestionControl, 'bbr');
    expect(node.options.udpRelayMode, 'quic');
    expect(node.options.heartbeatMillis, 1500);
    expect(node.options.disableSni, isTrue);
    expect(node.options.insecure, isTrue);
    expect(node.options.zeroRttHandshake, isFalse);
    expect(parseNodeUri('tuic://$_uuid:@example.test:443').password, isEmpty);
    final stream = parseNodeUri(
        'tuic://$_uuid:p@example.test:443?udp_over_stream=1&heartbeat=12s&reduce_rtt=true');
    expect(stream.options.heartbeatMillis, 12000);
    expect(stream.options.udpOverStream, isTrue);
    expect(stream.options.zeroRttHandshake, isTrue);
    expect(NodeOptions.fromJson(node.options.toJson()).toJson(),
        node.options.toJson());
    expect(node.options.toJson().toString(), isNot(contains(_uuid)));
    expect(node.options.toJson().toString(), isNot(contains('p@ss')));
  });

  test('Clash YAML imports all eight protocols including VMess and TUIC v5',
      () {
    final doc = parseSubscription('''
proxies:
  - {name: HTTP, type: http, server: example.test, port: 80}
  - {name: SOCKS, type: socks5, server: example.test, port: 1080}
  - {name: SS, type: ss, server: example.test, port: 443, password: fixture, cipher: aes-128-gcm}
  - {name: VLESS, type: vless, server: example.test, port: 443, uuid: $_uuid, packet-encoding: xudp}
  - {name: Trojan, type: trojan, server: example.test, port: 443, password: fixture}
  - {name: HY2, type: hysteria2, server: example.test, port: 443, password: fixture}
  - {name: VMess, type: vmess, server: example.test, port: 443, uuid: $_uuid, alterId: 64, cipher: auto, network: grpc, grpc-opts: {grpc-service-name: rainlink}, tls: true, global-padding: true, authenticated-length: true, packet-encoding: packetaddr}
  - {name: TUIC, type: tuic, server: example.test, port: 443, uuid: $_uuid, password: fixture-tuic, congestion-controller: new_reno, udp-relay-mode: quic, heartbeat-interval: 1500, reduce-rtt: true, disable-sni: true, alpn: [h3]}
''', const {}, _source);
    expect(doc.nodes, hasLength(8));
    expect(doc.skippedNodes, 0);
    expect(doc.nodes.map((node) => node.protocol).toSet(),
        NodeProtocol.values.toSet());
    final vmess = doc.nodes[6];
    expect(vmess.options.alterId, 64);
    expect(vmess.options.serviceName, 'rainlink');
    expect(vmess.options.globalPadding, isTrue);
    expect(vmess.options.authenticatedLength, isTrue);
    final tuic = doc.nodes[7];
    expect(tuic.username, _uuid);
    expect(tuic.password, 'fixture-tuic');
    expect(tuic.options.congestionControl, 'new_reno');
    expect(tuic.options.heartbeatMillis, 1500);
    expect(tuic.options.zeroRttHandshake, isTrue);
  });

  test('VMess malformed and unsupported links reject without echoing secrets',
      () {
    for (final encoded in [
      'vmess://fixture-secret',
      'vmess://${base64.encode(utf8.encode('["$_uuid"]'))}',
      _vmess({'id': 'fixture-secret'}),
      _vmess({'aid': 'bad'}),
      _vmess({'aid': 65536}),
      _vmess({'type': 'http'}),
      _vmess({'net': 'kcp'}),
      _vmess({'tls': 'reality'}),
      _vmess({'scy': 'unsupported'}),
      _vmess({'scy': 'aes-128-ctr'}),
      _vmess({'allowInsecure': 'maybe'}),
      _vmess({'mux': true}),
      'vmess://$_uuid@example.test:443?alterId=x',
      'vmess://$_uuid@example.test:443?security=tls&security=none',
    ]) {
      expect(
          () => parseNodeUri(encoded),
          throwsA(isA<NodeException>()
              .having((e) => e.message, 'redacted',
                  isNot(contains('fixture-secret')))
              .having(
                  (e) => e.message, 'uuid redacted', isNot(contains(_uuid)))));
    }
  });

  test('TUIC v4, conflicting UDP/TLS flags and invalid extensions reject', () {
    for (final link in [
      'tuic://fixture-secret@example.test:443',
      'tuic://invalid:fixture-secret@example.test:443',
      'tuic://$_uuid:p@example.test:443?udp_relay_mode=quic&udp_over_stream=1',
      for (final query in [
        'congestion_control=unknown',
        'heartbeat=0',
        'heartbeat=1ms',
        'heartbeat=3601s',
        'sni=a&sni=b',
        'insecure=1&allow_insecure=0',
        'reduce_rtt=1&zero_rtt_handshake=0',
        'token=hidden',
        'disable_sni=maybe'
      ])
        'tuic://$_uuid:fixture-secret@example.test:443?$query',
    ]) {
      expect(
          () => parseNodeUri(link),
          throwsA(isA<NodeException>().having((e) => e.message, 'redacted',
              isNot(contains('fixture-secret')))));
    }
    for (final field in [
      'token: hidden',
      'version: 4',
      'network: ws',
      'ip: 1.2.3.4',
      'heartbeat-interval: 0',
      'reduce-rtt: maybe',
      'udp-relay-mode: unsupported',
      'client-fingerprint: chrome',
      'tls: false'
    ]) {
      expect(
          () => parseSubscription(
              'proxies: [{name: TUIC, type: tuic, server: example.test, port: 443, uuid: $_uuid, password: fixture, $field}]',
              const {},
              _source),
          throwsA(isA<NodeException>()));
    }
  });

  test(
      'new options are backwards compatible while rejecting cross-protocol contamination',
      () {
    final old = NodeOptions.fromJson(const {});
    expect(old.vmessSecurity, 'auto');
    expect(old.congestionControl, 'cubic');
    expect(old.heartbeatMillis, 10000);
    for (final options in [
      const NodeOptions(vmessSecurity: 'none'),
      const NodeOptions(alterId: 1),
      const NodeOptions(udpOverStream: true),
      const NodeOptions(disableSni: true),
    ]) {
      expect(
          () => validateNode(NodeDraft(
              name: 'HTTP',
              protocol: NodeProtocol.http,
              server: 'example.test',
              port: 80,
              options: options)),
          throwsA(isA<NodeException>()));
    }
    expect(chainCompatibilityIssue([NodeProtocol.http, NodeProtocol.tuic]),
        contains('第 2 跳'));
    expect(chainCompatibilityIssue([NodeProtocol.tuic, NodeProtocol.http]),
        isNull);
    expect(chainCompatibilityIssue([NodeProtocol.vmess, NodeProtocol.tuic]),
        isNull);
  });

  test(
      'TUIC persistence keeps UUID/password encrypted; blank edits preserve credentials',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = TestSecretStore();
    final repo = DriftNodeRepository(db, secrets);
    final first = await repo.save(parseNodeUri(
        'tuic://$_uuid:fixture-secret@example.test:443?congestion_control=bbr'));
    final raw = await db.select(db.nodes).getSingle();
    expect(raw.options, isNot(contains(_uuid)));
    expect(raw.credential, isNot(contains(_uuid)));
    expect(raw.credential, isNot(contains('fixture-secret')));
    final auth = await secrets.reveal(first.id, first.credential);
    expect(auth.username, _uuid);
    expect(auth.password, 'fixture-secret');
    final edited = await repo.save(NodeDraft(
        name: '重命名',
        protocol: first.protocol,
        server: first.server,
        port: first.port,
        tls: true,
        options: first.options,
        original: first));
    expect(edited.credential, first.credential);
    expect((await repo.watchNodes().first).single.options.congestionControl,
        'bbr');
    await expectLater(
        repo.save(NodeDraft(
            name: 'bad',
            protocol: NodeProtocol.vmess,
            server: first.server,
            port: first.port,
            original: edited)),
        throwsA(isA<NodeException>()));
  });

  test(
      'subscription refresh retains VMess/TUIC IDs and selection when protocol options are unchanged',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final secrets = TestSecretStore();
    final fetcher = TestSubscriptionFetcher();
    final nodes = DriftNodeRepository(db, secrets);
    final groups = DriftGroupRepository(db, secrets, fetcher);
    fetcher.document = parseSubscription(
        '${_vmess({})}\ntuic://$_uuid:fixture@example.test:443',
        const {},
        _source);
    final id = await groups.importUrl(
        _source.toString(), SubscriptionCancellation(),
        autoUpdate: false);
    final first = await nodes.watchNodes().first;
    final tuic =
        first.singleWhere((node) => node.protocol == NodeProtocol.tuic);
    await nodes.select(tuic.id);
    await groups.refresh(id, SubscriptionCancellation());
    final group = (await groups.watchGroups().first).single;
    expect(group.autoUpdate, isFalse);
    expect(group.isDue(DateTime.now().add(const Duration(days: 2))), isFalse);
    final after = await nodes.watchNodes().first;
    expect(after.map((node) => node.id).toSet(),
        first.map((node) => node.id).toSet());
    expect(after.map((node) => node.revision), everyElement(1));
    expect(await nodes.watchSelectedId().first, tuic.id);
  });
}
