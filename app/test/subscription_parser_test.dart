import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/groups/subscription_issue.dart';

void main() {
  final source = Uri.parse('https://provider.example.test/sub?token=hidden');
  test('a notice mixed with invalid nodes does not hide the real failures', () {
    expect(
        () => parseSubscription('''
proxies:
  - {name: 剩余流量, type: ss, server: localhost, port: 8080, password: secret-fixture}
  - {type: vless, server: edge.example.test, port: 443, uuid: invalid-fixture}
''', const {}, source),
        throwsA(isA<SubscriptionContentException>().having(
            (error) => error.issues.length, 'all diagnostic items', 2)));
  });
  test(
      'URI parameters cannot be silently lost or change TLS and transport meaning',
      () {
    for (final link in [
      'http://example.test:8080?path=/ignored',
      'http://example.test:8080?encryption=none',
      'socks5://example.test:1080?type=tcp',
      'trojan://secret@example.test:443?type=tcp&host=edge.example.test',
      'trojan://secret@example.test:443?type=ws&serviceName=ignored',
      'vless://a6db2f50-361a-4294-8bce-1df5f356764f@example.test:443?security=none&sni=edge.example.test',
      'trojan://secret@example.test:443?allowInsecure=true&insecure=invalid',
      'hy2://secret@example.test:443?insecure=invalid',
      'hy2://secret@example.test:443?insecure=true&allowInsecure=false',
      'https://example.test:443?security=none',
    ]) {
      expect(() => parseNodeUri(link), throwsA(isA<NodeException>()));
    }
    expect(
        parseNodeUri('trojan://secret@example.test:443?allowInsecure=true')
            .options
            .insecure,
        isTrue);
  });
  test('documents without any usable nodes retain safe individual diagnostics',
      () {
    expect(
        () => parseSubscription(
            'unknown://hidden@example.test:443\nhttp://example.test:0',
            const {},
            source),
        throwsA(isA<SubscriptionContentException>().having(
            (error) => error.issues.map((issue) => issue.item), 'positions', [
          1,
          2
        ]).having((error) => error.issues.map((issue) => issue.reason).join(),
            'redacted', isNot(contains('hidden')))));
  });
  test(
      'incompatible Clash fields and remote configuration produce safe positioned diagnostics',
      () {
    final document = parseSubscription('''
proxies:
  - {type: http, server: edge.example.test, port: 8080}
  - {type: http, server: edge.example.test, port: 8080, private-token: secret-fixture}
  - {type: vless, server: edge.example.test, port: 443, uuid: a6db2f50-361a-4294-8bce-1df5f356764f, tls: true, reality-opts: {public-key: hidden, unknown-option: secret-fixture}}
  - {type: vmess, server: edge.example.test, port: 443, uuid: a6db2f50-361a-4294-8bce-1df5f356764f, network: ws, ws-opts: {path: /ws, unknown-option: secret-fixture}}
  - {type: http, server: edge.example.test, port: 8080, password: [secret-fixture]}
rules: ['DOMAIN,secret-fixture,DIRECT']
dns: {nameserver: ['https://secret-fixture/dns-query']}
mixed-port: 17890
unknown-private-token: secret-fixture
''', const {}, source);
    expect(document.nodes, hasLength(1));
    expect(document.skippedNodes, 4);
    expect(document.requiresReview, isTrue);
    expect(document.issues.where((i) => i.item != null).map((i) => i.item),
        [2, 3, 4, 5]);
    expect(
        document.issues
            .where((i) => i.kind == SubscriptionIssueKind.configuration),
        hasLength(4));
    final diagnostics =
        jsonEncode(document.issues.map((i) => i.toJson()).toList());
    for (final secret in [
      'private-token',
      'secret-fixture',
      'hidden',
      'a6db2f50'
    ]) {
      expect(diagnostics, isNot(contains(secret)));
    }
    expect(
        SubscriptionIssue.fromJson(
            {'kind': 'unsupported', 'reason': 'bad\ninput', 'item': 1}),
        isNull);
    expect(
        SubscriptionIssue.fromJson(
            {'kind': 'unsupported', 'reason': 'bad', 'item': 2001}),
        isNull);
  });
  test('provider client notices do not become selectable loopback proxies', () {
    const notices = '''
proxies:
  - {name: 不支持您的代理软件, type: ss, server: 127.0.0.1, port: 6666, cipher: aes-128-gcm, password: fixture}
  - {name: 请换用支持的代理软件, type: ss, server: localhost, port: 6666, cipher: aes-128-gcm, password: fixture}
  - {name: 官网地址, type: ss, server: '::1', port: 6666, cipher: aes-128-gcm, password: fixture}
''';
    expect(
        () => parseSubscription(notices, const {}, source),
        throwsA(isA<NodeException>()
            .having((e) => e.message, 'reason', contains('提示信息'))
            .having((e) => e.message, 'redacted', isNot(contains('fixture')))));
    final document = parseSubscription('''$notices
  - {name: 本机代理, type: http, server: 127.0.0.1, port: 8080}
  - {name: 东京线路, type: ss, server: edge.example.test, port: 443, cipher: aes-128-gcm, password: fixture}
''', const {}, source);
    expect(document.nodes.map((node) => node.name), ['本机代理', '东京线路']);
    expect(document.skippedNodes, 3);
  });
  test('usage placeholders are skipped while real endpoints stay available',
      () {
    final document = parseSubscription('''
proxies:
  - {name: 剩余流量 100 GB, type: ss, server: 127.0.0.1, port: 6666, cipher: aes-128-gcm, password: fixture}
  - {name: 套餐到期 2030-01-01, type: ss, server: 127.0.0.1, port: 6666, cipher: aes-128-gcm, password: fixture}
  - {name: 距离下次重置剩余 7 天, type: ss, server: 127.0.0.1, port: 6666, cipher: aes-128-gcm, password: fixture}
  - {name: 订阅到期, type: ss, server: edge.example.test, port: 443, cipher: aes-128-gcm, password: fixture}
''', const {}, source);
    expect(document.nodes.single.server, 'edge.example.test');
    expect(document.skippedNodes, 3);
  });
  test(
      'Clash YAML imports all supported protocols and preserves public transport settings',
      () {
    final document = parseSubscription('''
proxies:
  - {name: HTTP, type: http, server: proxy.example.test, port: 8080, username: user, password: secret}
  - {name: SOCKS, type: socks5, server: proxy.example.test, port: 1080}
  - {name: SS, type: ss, server: jp.example.test, port: 443, cipher: aes-256-gcm, password: secret}
  - name: VLESS
    type: vless
    server: us.example.test
    port: 443
    uuid: a6db2f50-361a-4294-8bce-1df5f356764f
    tls: true
    servername: edge.example.test
    network: ws
    ws-opts:
      path: /tunnel
      headers: {Host: edge.example.test}
  - {name: Trojan, type: trojan, server: hk.example.test, port: 443, password: secret, network: grpc, grpc-opts: {grpc-service-name: rainlink}}
''', {
      'profile-title': 'base64:${base64.encode(utf8.encode('我的订阅'))}',
      'subscription-userinfo':
          'upload=1024; download=2048; total=1073741824; expire=1893456000',
      'profile-update-interval': '12'
    }, source);
    expect(document.name, '我的订阅');
    expect(document.nodes, hasLength(5));
    expect(document.skippedNodes, 0);
    expect(document.nodes[2].options.method, 'aes-256-gcm');
    expect(document.nodes[3].options.path, '/tunnel');
    expect(document.nodes[3].options.host, 'edge.example.test');
    expect(document.nodes[4].tls, isTrue);
    expect(document.nodes[4].options.serviceName, 'rainlink');
    expect(document.uploaded, 1024);
    expect(document.downloaded, 2048);
    expect(document.total, 1073741824);
    expect(document.expiresAt, DateTime.utc(2030));
    expect(document.intervalHours, 12);
  });
  test(
      'JSON proxies, unknown protocols and connection-changing extensions are explicit skips',
      () {
    final document = parseSubscription(
        jsonEncode({
          'proxies': [
            {
              'name': 'valid',
              'type': 'ss',
              'server': 'example.test',
              'port': 443,
              'cipher': 'aes-128-gcm',
              'password': 'secret'
            },
            {'name': 'unsupported', 'type': 'vmess'},
            {'name': 'plugin', 'type': 'ss', 'plugin': 'obfs'},
            {
              'name': 'bad UUID',
              'type': 'vless',
              'server': 'example.test',
              'port': 443,
              'uuid': 'not-a-uuid'
            },
            {
              'name': 'bad transport',
              'type': 'trojan',
              'server': 'example.test',
              'port': 443,
              'password': 'secret',
              'network': 'h2'
            },
          ]
        }),
        const {},
        source);
    expect(document.nodes.single.name, 'valid');
    expect(document.skippedNodes, 4);
    expect(document.total, isNull);
    expect(document.expiresAt, isNull);
    expect(document.name, source.host);
  });
  test(
      'SIP002 and legacy SS links, encoded URI lists and native VLESS/Trojan links',
      () {
    final lines = [
      'ss://${base64Url.encode(utf8.encode('aes-128-gcm:p@ss:word'))}@jp.example.test:443#${Uri.encodeComponent('日本节点')}',
      'ss://${base64.encode(utf8.encode('aes-256-gcm:legacy@legacy.example.test:8388'))}#Legacy',
      'vless://a6db2f50-361a-4294-8bce-1df5f356764f@us.example.test:443?security=tls&type=ws&path=%2Fws&host=edge.example.test#VLESS',
      'trojan://p%40ss@hk.example.test:443?sni=edge.example.test&type=grpc&serviceName=rainlink#Trojan',
      'http://user:password@localhost:8080#HTTP',
      'socks5://localhost:1080#SOCKS',
    ];
    for (final input in [
      lines.join('\n'),
      base64.encode(utf8.encode(lines.join('\n')))
    ]) {
      final document = parseSubscription(input, const {}, source);
      expect(document.nodes, hasLength(6));
      expect(document.nodes.first.name, '日本节点');
      expect(document.nodes.first.password, 'p@ss:word');
      expect(document.nodes[3].password, 'p@ss');
      expect(document.nodes[2].options.transport, 'ws');
      expect(document.nodes[2].options.path, '/ws');
    }
  });
  test('Reality and Vision options round trip with validated keys', () {
    final key = base64Url.encode(List<int>.filled(32, 1)).replaceAll('=', '');
    final node = parseNodeUri(
        'vless://a6db2f50-361a-4294-8bce-1df5f356764f@example.test:443?security=reality&pbk=$key&sid=01ab&fp=chrome&sni=edge.example.test&flow=xtls-rprx-vision');
    expect(node.protocol, NodeProtocol.vless);
    expect(node.tls, isTrue);
    expect(node.options.realityPublicKey, key);
    expect(
        NodeOptions.fromJson(node.options.toJson()).flow, 'xtls-rprx-vision');
    expect(() => parseNodeUri('vless://invalid@example.test:443'),
        throwsA(isA<NodeException>()));
    expect(
        () => parseNodeUri(
            'ss://${base64.encode(utf8.encode('aes-128-gcm:password'))}@example.test:443?plugin=obfs'),
        throwsA(isA<NodeException>()));
  });
  test(
      'missing, malformed and zero metadata never fabricates expiry or capacity',
      () {
    final document = parseSubscription(
        'socks5://localhost:1080',
        {
          'subscription-userinfo':
              'upload=-5; download=foo; total=999999999999999999999999; expire=0',
          'profile-title': 'base64:@@@',
          'profile-update-interval': '99999',
        },
        source);
    expect(document.uploaded, isNull);
    expect(document.downloaded, isNull);
    expect(document.total, isNull);
    expect(document.expiresAt, isNull);
    expect(document.intervalHours, 24);
    expect(document.name, source.host);
  });
  test(
      'invalid, empty, unsupported-only and oversized documents fail without echoing payload',
      () {
    for (final input in [
      '',
      '<html>token=hidden</html>',
      'proxies: [',
      'vmess://hidden',
      'proxies: []'
    ]) {
      expect(
          () => parseSubscription(input, const {}, source),
          throwsA(isA<NodeException>().having(
              (e) => e.message, 'redacted', isNot(contains('token=hidden')))));
    }
    expect(
        () => parseSubscription(
            List.filled(2001, 'socks5://localhost:1080').join('\n'),
            const {},
            source),
        throwsA(isA<NodeException>()));
    for (final url in [
      'file:///tmp/sub',
      'https://user:password@example.test/sub',
      'https://example.test/sub#secret',
      'http://'
    ]) {
      expect(() => validateSubscriptionUrl(url), throwsA(isA<NodeException>()));
    }
  });
}
