import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/data/subscriptions/subscription_parser.dart';
import 'package:rainlink/domain/groups/subscription_issue.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';

const _uuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';
final _source = Uri.parse('https://provider.example.test/private-token');
const _http = {
  'type': 'http',
  'server': 'proxy.example.test',
  'server_port': 8080
};

void main() {
  test(
      'sing-box JSON imports all eight protocols with exact transport and authentication options',
      () {
    final key = base64Url.encode(List.filled(32, 1)).replaceAll('=', '');
    final document = parseSubscription(
        jsonEncode({
          'outbounds': [
            {
              ..._http,
              'tag': 'HTTP',
              'username': 'user-fixture',
              'password': 'secret-fixture'
            },
            {
              'type': 'socks',
              'tag': 'SOCKS',
              'server': 'edge.example.test',
              'server_port': 1080,
              'version': '5'
            },
            {
              'type': 'shadowsocks',
              'tag': 'SS',
              'server': 'edge.example.test',
              'server_port': 443,
              'method': 'aes-256-gcm',
              'password': 'secret-fixture'
            },
            {
              'type': 'vless',
              'tag': 'VLESS',
              'server': 'edge.example.test',
              'server_port': 443,
              'uuid': _uuid,
              'flow': 'xtls-rprx-vision',
              'tls': {
                'enabled': true,
                'server_name': 'sni.example.test',
                'utls': {'enabled': true, 'fingerprint': 'chrome'},
                'reality': {
                  'enabled': true,
                  'public_key': key,
                  'short_id': 'abcd'
                }
              }
            },
            {
              'type': 'vmess',
              'tag': 'VMess',
              'server': 'edge.example.test',
              'server_port': 443,
              'uuid': _uuid,
              'security': 'aes-128-gcm',
              'alter_id': 4,
              'global_padding': true,
              'authenticated_length': true,
              'packet_encoding': 'xudp',
              'tls': {
                'enabled': true,
                'alpn': ['http/1.1']
              },
              'transport': {
                'type': 'ws',
                'path': '/stream',
                'headers': {
                  'Host': ['edge.example.test']
                }
              }
            },
            {
              'type': 'trojan',
              'tag': 'Trojan',
              'server': 'edge.example.test',
              'server_port': 443,
              'password': 'secret-fixture',
              'tls': {'enabled': true},
              'transport': {'type': 'grpc', 'service_name': 'rainlink'}
            },
            {
              'type': 'hysteria2',
              'tag': 'HY2',
              'server': 'edge.example.test',
              'server_port': 443,
              'password': 'secret-fixture',
              'tls': {'enabled': true, 'insecure': true},
              'obfs': {'type': 'salamander', 'password': 'obfs-fixture'},
              'up_mbps': 100,
              'down_mbps': 200,
              'server_ports': ['443:444', '8443'],
              'hop_interval': '30s'
            },
            {
              'type': 'tuic',
              'tag': 'TUIC',
              'server': 'edge.example.test',
              'server_port': 443,
              'uuid': _uuid,
              'password': 'secret-fixture',
              'tls': {'enabled': true, 'disable_sni': true},
              'congestion_control': 'bbr',
              'udp_over_stream': true,
              'zero_rtt_handshake': true,
              'heartbeat': '2500ms'
            },
          ]
        }),
        const {},
        _source);
    expect(document.nodes.map((n) => n.protocol), NodeProtocol.values);
    expect(document.requiresReview, isFalse);
    expect(document.nodes[0].username, 'user-fixture');
    expect(document.nodes[3].password, _uuid);
    expect(document.nodes[3].options.flow, 'xtls-rprx-vision');
    expect(document.nodes[3].options.realityPublicKey, key);
    expect(document.nodes[4].options.vmessSecurity, 'aes-128-gcm');
    expect(document.nodes[4].options.alterId, 4);
    expect(document.nodes[4].options.globalPadding, isTrue);
    expect(document.nodes[4].options.authenticatedLength, isTrue);
    expect(document.nodes[4].options.packetEncoding, 'xudp');
    expect(document.nodes[4].options.transport, 'ws');
    expect(document.nodes[4].options.host, 'edge.example.test');
    expect(document.nodes[5].options.serviceName, 'rainlink');
    expect(document.nodes[6].obfsPassword, 'obfs-fixture');
    expect(document.nodes[6].options.upMbps, 100);
    expect(document.nodes[6].options.serverPorts, ['443:444', '8443']);
    expect(document.nodes[6].options.hopIntervalSeconds, 30);
    expect(document.nodes[7].username, _uuid);
    expect(document.nodes[7].options.heartbeatMillis, 2500);
    expect(document.nodes[7].options.disableSni, isTrue);
    expect(document.nodes[7].options.udpOverStream, isTrue);
  });

  test(
      'sing-box configuration-only outbounds and remote settings require explicit review by original position',
      () {
    final document = parseSubscription(
        jsonEncode({
          'outbounds': [
            _http,
            {
              'type': 'selector',
              'tag': 'credential-fixture',
              'outbounds': ['HTTP']
            },
            {'type': 'direct'}
          ],
          'inbounds': [
            {'type': 'mixed', 'listen_port': 8080}
          ],
          'route': {'final': 'credential-fixture'},
          'dns': {
            'servers': ['https://credential-fixture/dns-query']
          },
          'unknown-credential-fixture': 'secret-fixture',
        }),
        const {},
        _source);
    expect(document.nodes, hasLength(1));
    expect(document.skippedNodes, 2);
    expect(document.requiresReview, isTrue);
    expect(document.issues.where((i) => i.item != null).map((i) => i.item),
        [2, 3]);
    expect(
        document.issues
            .where((i) => i.kind == SubscriptionIssueKind.configuration),
        hasLength(4));
    final diagnostics =
        jsonEncode(document.issues.map((i) => i.toJson()).toList());
    for (final secret in [
      'credential-fixture',
      'private-token',
      'secret-fixture',
      _uuid
    ]) {
      expect(diagnostics, isNot(contains(secret)));
    }
  });

  test(
      'unknown nested fields, dialer changes and invalid JSON types cannot be silently translated',
      () {
    for (final item in [
      {..._http, 'detour': 'secret-fixture'},
      {..._http, 'bind_interface': 'secret-fixture'},
      {..._http, 'connect_timeout': '5s'},
      {
        ..._http,
        'multiplex': {'enabled': true}
      },
      {
        ..._http,
        'tls': {'enabled': true, 'certificate': 'secret-fixture'}
      },
      {
        ..._http,
        'tls': {
          'enabled': true,
          'ech': {'enabled': true}
        }
      },
      {
        ..._http,
        'tls': {'enabled': false, 'server_name': 'secret-fixture'}
      },
      {..._http, 'tls': 'secret-fixture'},
      {..._http, 'server_port': '443'},
      {
        ..._http,
        'password': ['secret-fixture']
      },
      {
        ..._http,
        'tls': {'enabled': 'true'}
      },
      {
        'type': 'socks',
        'version': '4',
        'server': 'edge.example.test',
        'server_port': 1080
      },
      {
        'type': 'vmess',
        'server': 'edge.example.test',
        'server_port': 443,
        'uuid': _uuid,
        'transport': {'type': 'ws', 'path': '/', 'max_early_data': 2048}
      },
      {
        'type': 'trojan',
        'server': 'edge.example.test',
        'server_port': 443,
        'password': 'secret-fixture',
        'tls': {'enabled': true},
        'transport': {'type': 'grpc', 'idle_timeout': '10s'}
      },
      {
        'type': 'tuic',
        'server': 'edge.example.test',
        'server_port': 443,
        'uuid': _uuid,
        'password': 'secret-fixture',
        'tls': {'enabled': true},
        'heartbeat': '1.5s'
      },
      {
        'type': 'hysteria2',
        'server': 'edge.example.test',
        'server_port': 443,
        'password': 'secret-fixture',
        'tls': {'enabled': true},
        'server_ports': ['8443'],
        'hop_interval': '5500ms'
      },
    ]) {
      final document = parseSubscription(
          jsonEncode({
            'outbounds': [_http, item]
          }),
          const {},
          _source);
      expect(document.nodes, hasLength(1),
          reason: 'Invalid item should not become a changed connection');
      expect(document.issues.single.item, 2);
      expect(document.requiresReview, isTrue);
      expect(jsonEncode(document.issues.single.toJson()),
          isNot(contains('secret-fixture')));
    }
  });

  test(
      'ambiguous formats are rejected and large outbound lists retain the same import bound',
      () {
    for (final data in [
      {
        'outbounds': [_http],
        'proxies': [_http]
      },
      {'outbounds': 'secret-fixture'},
      {'outbounds': List.filled(maxSubscriptionNodes + 1, _http)},
    ]) {
      expect(() => parseSubscription(jsonEncode(data), const {}, _source),
          throwsA(isA<NodeException>()));
    }
  });
}
