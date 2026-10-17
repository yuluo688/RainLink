import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/core/runtime_settings.dart';
import 'package:rainlink/domain/chains/proxy_chain.dart';
import 'package:rainlink/domain/routing/route_rules.dart';
import 'package:rainlink/domain/routing/routing_plan.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/platform/core/android_core_gateway.dart';

const node = ProxyNode(
    id: 'node',
    name: '测试',
    protocol: NodeProtocol.hysteria2,
    server: 'proxy.example',
    port: 443,
    tls: true,
    options: NodeOptions(transport: 'quic'),
    credential: 'rlk1.fixture');
ConnectRequest request({bool tun = true}) => ConnectRequest(
    target: const ProxyTarget(id: 'node', name: '测试', revision: 1),
    node: node,
    mode: ProxyMode.rule,
    tun: tun);
Map<String, Object?> receipt({bool tun = true}) => {
      'phase': 'connected',
      'sessionId': 'session',
      'target': {'id': 'node', 'name': '测试', 'revision': 1, 'kind': 'node'},
      'configRevision': 'config',
      'mode': 'rule',
      'proxyPort': 17890,
      'systemProxy': false,
      'tun': tun,
      'tunInterface': 'tun0',
      'runtimeSettings': const CoreRuntimeSettings().toJson(),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('rainlink/android-test');
  late AndroidCoreGateway gateway;
  final calls = <MethodCall>[];
  late Future<String> Function(MethodCall) respond;
  setUp(() {
    calls.clear();
    gateway = AndroidCoreGateway(channel: channel);
    respond = (_) async => '{}';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
      calls.add(call);
      return respond(call);
    });
  });
  tearDown(() {
    gateway.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android requires the tunnel and forwards encrypted Hysteria2 settings',
      () async {
    await expectLater(gateway.connect(request(tun: false)),
        throwsA(isA<CoreGatewayException>()));
    expect(calls, isEmpty);
    respond =
        (call) async => call.method == 'connect' ? jsonEncode(receipt()) : '{}';
    final result = await gateway.connect(request());
    expect(result.target.id, 'node');
    final body =
        jsonDecode(calls.single.arguments as String) as Map<String, Object?>;
    expect(body['tun'], true);
    expect(body['systemProxy'], false);
    expect((body['node'] as Map<String, Object?>)['protocol'], 'hysteria2');
    expect(
        (body['node'] as Map<String, Object?>)['credential'], 'rlk1.fixture');
  });

  test('a mismatched capture receipt is stopped before reporting connected',
      () async {
    respond = (call) async =>
        call.method == 'connect' ? jsonEncode(receipt(tun: false)) : '{}';
    await expectLater(
        gateway.connect(request()), throwsA(isA<CoreGatewayException>()));
    expect(calls.map((call) => call.method), ['connect', 'disconnect']);
  });

  test('cancel rejects a late successful connect', () async {
    final pending = Completer<String>();
    respond = (call) =>
        call.method == 'connect' ? pending.future : Future.value('{}');
    final connecting = gateway.connect(request());
    final assertion = expectLater(
        connecting,
        throwsA(isA<CoreGatewayException>()
            .having((error) => error.code, 'code', 'cancelled')));
    await Future<void>.delayed(Duration.zero);
    await gateway.cancel();
    pending.complete(jsonEncode(receipt()));
    await assertion;
    expect(calls.map((call) => call.method), ['connect', 'cancel']);
  });

  test('activity disposal leaves the native foreground session running',
      () async {
    gateway.dispose();
    await expectLater(gateway.observe(), throwsA(isA<CoreGatewayException>()));
    expect(calls, isEmpty);
  });

  test('recovery keeps encrypted target, rule and runtime snapshots', () async {
    final rules = RouteRuleSet.defaults();
    respond = (_) async => jsonEncode({
          ...receipt(),
          'ruleRevision': 0,
          'routeBindings': <String, Object?>{},
          'request': {
            'node': node.toHost(),
            'mode': 'rule',
            'tun': true,
            'systemProxy': false,
            'routing': {...rules.toJson(), 'outbounds': <Object?>[]},
            'runtimeSettings': const CoreRuntimeSettings().toJson(),
          }
        });
    final recovered = await gateway.recoverSession();
    expect(recovered.request?.node?.credential, node.credential);
    expect(recovered.request?.target.id, node.id);
    expect(
        recovered.request?.routing?.ruleSet.rules.length, rules.rules.length);
    expect(recovered.observation.active?.sessionId, 'session');
    expect(calls.single.method, 'restore');
  });

  for (final advanced in <String?>[null, '', ' {} ']) {
    for (final recovering in [false, true]) {
      test(
          '${recovering ? 'recovery' : 'connect'} accepts equivalent empty advanced configuration: $advanced',
          () async {
        final settings = const CoreRuntimeSettings().toJson();
        if (advanced == null) {
          settings.remove('advanced');
        } else {
          settings['advanced'] = advanced;
        }
        respond = (_) async => jsonEncode({
              ...receipt(),
              'runtimeSettings': settings,
              if (recovering)
                'request': {
                  'node': node.toHost(),
                  'mode': 'rule',
                  'tun': true,
                  'systemProxy': false,
                  'runtimeSettings': settings,
                }
            });
        final active = recovering
            ? (await gateway.recoverSession()).observation.active
            : await gateway.connect(request());
        expect(active?.sessionId, 'session');
        expect(calls.map((call) => call.method),
            [recovering ? 'restore' : 'connect']);
      });
    }
  }

  for (final mismatch in <String, Object?>{
    'proxyPort': 17891,
    'dnsMode': 'encrypted',
    'resolver': 'https://dns.example/dns-query',
    'bootstrapDns': '1.1.1.1',
    'ipv6': true,
    'logLevel': 'debug',
    'advanced': '{"log":{"timestamp":true}}',
  }.entries) {
    test('recovery stops an actual ${mismatch.key} mismatch', () async {
      respond = (call) async => call.method == 'restore'
          ? jsonEncode({
              ...receipt(),
              'runtimeSettings': {
                ...const CoreRuntimeSettings().toJson(),
                mismatch.key: mismatch.value,
              },
              'request': {
                'node': node.toHost(),
                'mode': 'rule',
                'tun': true,
                'systemProxy': false,
                'runtimeSettings': const CoreRuntimeSettings().toJson(),
              }
            })
          : '{}';
      await expectLater(
          gateway.recoverSession(),
          throwsA(isA<CoreGatewayException>()
              .having((error) => error.code, 'code', 'invalid_response')));
      expect(calls.map((call) => call.method), ['restore', 'disconnect']);
    });
  }

  test('invalid native runtime settings are rejected and disconnected',
      () async {
    respond = (call) async => call.method == 'connect'
        ? jsonEncode({
            ...receipt(),
            'runtimeSettings': {
              ...const CoreRuntimeSettings().toJson(),
              'advanced': '{invalid',
            }
          })
        : '{}';
    await expectLater(
        gateway.connect(request()),
        throwsA(isA<CoreGatewayException>()
            .having((error) => error.code, 'code', 'invalid_response')));
    expect(calls.map((call) => call.method), ['connect', 'disconnect']);
  });

  test('recovery preserves chain hops and independent rule targets', () async {
    const hop = ProxyNode(
        id: 'exit',
        name: '出口',
        protocol: NodeProtocol.http,
        server: 'exit.example',
        port: 443,
        revision: 2,
        credential: 'rlk1.exit');
    final chain = ChainSnapshot(
        ProxyChain(
            id: 'chain', name: '代理链', revision: 3, hopIds: [node.id, hop.id]),
        [node, hop]);
    final plan = RoutingPlan(
        ruleSet: RouteRuleSet.defaults(),
        primaryChain: chain,
        outbounds: [
          const RoutingOutbound(key: 'node:exit', name: '出口', node: hop)
        ]);
    respond = (_) async => jsonEncode({
          ...receipt(),
          'target': {
            'id': 'chain',
            'name': '代理链',
            'revision': 3,
            'kind': 'chain'
          },
          'routeBindings': plan.expectedBindings.map((key, value) =>
              MapEntry(key, {'id': value.id, 'revision': value.revision})),
          'request': {
            'chain': chain.toHost(),
            'routing': plan.toHost(),
            'mode': 'rule',
            'tun': true,
            'systemProxy': false,
            'runtimeSettings': const CoreRuntimeSettings().toJson()
          }
        });
    final recovered = await gateway.recoverSession();
    expect(recovered.request?.chain?.hops.map((node) => node.id),
        ['node', 'exit']);
    expect(recovered.request?.routing?.outbounds.single.node?.revision, 2);
    expect(recovered.request?.target.kind, 'chain');
  });

  test('invalid recovery is disconnected and plaintext is never adopted',
      () async {
    respond = (call) async => call.method == 'restore'
        ? jsonEncode({
            ...receipt(),
            'request': {
              'secrets': {'password': 'unexpected'}
            }
          })
        : '{}';
    await expectLater(
        gateway.recoverSession(), throwsA(isA<CoreGatewayException>()));
    expect(calls.map((call) => call.method), ['restore', 'disconnect']);
  });

  test('close still disconnects if test cancellation fails', () async {
    respond = (call) async {
      if (call.method == 'cancelTests') {
        throw PlatformException(code: 'cancel_failed');
      }
      return '{}';
    };
    await expectLater(gateway.close(), throwsA(isA<CoreGatewayException>()));
    expect(calls.map((call) => call.method),
        ['cancelTests', 'cancelDns', 'disconnect']);
  });

  test(
      'DNS replies require actual IPs and cancellation invalidates late results',
      () async {
    expect(
        () => DnsTestResult.fromJson({
              'addresses': ['not-an-ip'],
              'latency': 1
            }),
        throwsA(isA<SettingsException>()));
    final pending = Completer<String>();
    respond = (call) =>
        call.method == 'testDns' ? pending.future : Future.value('{}');
    final test = gateway.testDns(const CoreRuntimeSettings());
    final assertion = expectLater(test, throwsA(isA<SettingsException>()));
    await gateway.cancelDnsTest();
    pending.complete(jsonEncode({
      'addresses': ['203.0.113.1'],
      'latency': 7
    }));
    await assertion;
  });
}
