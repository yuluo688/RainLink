import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:rainlink/data/database/app_database.dart';
import 'package:rainlink/data/groups/drift_group_repository.dart';
import 'package:rainlink/data/nodes/drift_node_repository.dart';
import 'package:rainlink/data/subscriptions/http_subscription_fetcher.dart';
import 'package:rainlink/domain/core/core_gateway.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/groups/subscription_review.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/platform/core/host_session_client.dart';

/// Opt-in real-provider verification. Private JSON inputs arrive only on stdin.
/// Use tools/verify_remote.py to supply inputs without console echo or argv.
Future<void> main() async {
  final input =
      await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  final config = jsonDecode(input) as Map<String, Object?>;
  final client = HostSessionClient(config['host']! as String);
  final database = AppDatabase(NativeDatabase.memory());
  final secrets = _RemoteSecrets(client);
  final nodes = DriftNodeRepository(database, secrets);
  final fetcher = _VerificationFetcher();
  final groups = DriftGroupRepository(database, secrets, fetcher);
  final report = <String, Object?>{
    'at': DateTime.now().toUtc().toIso8601String(),
    'database': 'memory',
    'systemProxyRequested': false,
  };
  try {
    final hello = await client.request('hello');
    report['coreVersion'] = hello['coreVersion'];
    final manual = <ProxyNode>[];
    for (final (index, value)
        in (config['proxies']! as List<Object?>).indexed) {
      final proxy = value! as Map<String, Object?>;
      manual.add(await nodes.save(NodeDraft(
          name: 'HTTP ${index + 1}',
          protocol: NodeProtocol.http,
          server: proxy['server']! as String,
          port: proxy['port']! as int,
          authenticate: true,
          username: proxy['username']! as String,
          password: proxy['password']! as String)));
    }
    report['manualStorage'] = {
      'count': manual.length,
      'ungrouped': manual.every((node) => node.groupId == null),
      'protectedCredentials':
          manual.every((node) => node.credential.isNotEmpty),
    };
    final results = <Map<String, Object?>>[];
    report['connections'] = results;
    for (final (index, node) in manual.indexed) {
      final result = await _verify(client, node, 'http-${index + 1}');
      results.add(result);
      _emit({'event': 'connection', ...result});
    }
    // Existing encrypted node snapshots can be tested without refetching an
    // unavailable subscription or modifying the user's on-disk database.
    final stored = config['storedNodes'] as List<Object?>? ?? const [];
    if (stored.length > 32) {
      throw const NodeException('Too many stored verification nodes');
    }
    for (final (index, value) in stored.indexed) {
      final node = _storedNode(value! as Map<String, Object?>);
      final result = await _verify(client, node, 'stored-${index + 1}');
      results.add(result);
      _emit({'event': 'connection', ...result});
    }
    final subscriptionUrl = config['subscription'] as String?;
    if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
      try {
        final viaManual = config['subscriptionViaManual'] as int?;
        if (viaManual != null) {
          final bootstrap = manual[viaManual];
          final connection = await client.request('connect', {
            'node': bootstrap.toHost(),
            'mode': 'global',
            'systemProxy': false,
          });
          fetcher.proxyPort = connection['proxyPort']! as int;
        }
        String groupId;
        try {
          groupId = await groups.importUrl(
              subscriptionUrl, SubscriptionCancellation());
        } on SubscriptionReviewRequired catch (error) {
          report['compatibilityReview'] = _reviewSummary(error.review,
              accepted: config['acceptCompatible'] == true);
          if (config['acceptCompatible'] != true) rethrow;
          // Explicit QA option; imports only into this disposable memory DB.
          groupId = await groups.acceptReview(
              error.review, SubscriptionCancellation());
        }
        final group = (await groups.watchGroups().first).single;
        final imported = (await nodes.watchNodes().first)
            .where((node) => node.groupId == groupId)
            .toList();
        final counts = <String, int>{};
        for (final node in imported) {
          counts.update(node.protocol.label, (v) => v + 1, ifAbsent: () => 1);
        }
        final subscription = <String, Object?>{
          'imported': true,
          'automaticGroup': group.kind == GroupKind.subscription,
          'nameFromProvider': group.name.isNotEmpty,
          'nodeCount': imported.length,
          'protocols': counts,
          'skipped': group.skippedNodes,
          'usageProvided': group.used != null,
          'usedBytes': group.used,
          'totalBytes': group.total,
          'expiresAt': group.expiresAt?.toIso8601String(),
          'intervalHours': group.intervalHours,
          'fetchRoute':
              viaManual == null ? 'system-network' : 'provided-http-proxy',
        };
        report['subscription'] = subscription;
        _emit({'event': 'subscription-import', ...subscription});
        final sampleLimit = config['sampleLimit'] as int? ?? 6;
        if (sampleLimit < 1 || sampleLimit > 12) {
          throw const NodeException('sampleLimit must be between 1 and 12');
        }
        final sampleProtocol = config['sampleProtocol'] as String?;
        final candidates = sampleProtocol == null
            ? imported
            : imported
                .where((node) => node.protocol.wireName == sampleProtocol)
                .toList();
        if (candidates.isEmpty) throw const NodeException('订阅没有目标协议的节点');
        final samples = _samples(candidates, sampleLimit);
        await nodes.select(samples.first.id);
        final beforeIds = imported.map((node) => node.id).toSet();
        try {
          try {
            await groups.refresh(groupId, SubscriptionCancellation());
          } on SubscriptionReviewRequired catch (error) {
            subscription['refreshReview'] = _reviewSummary(error.review,
                accepted: config['acceptCompatible'] == true);
            if (config['acceptCompatible'] != true) rethrow;
            await groups.acceptReview(error.review, SubscriptionCancellation());
          }
          final after = (await nodes.watchNodes().first)
              .where((node) => node.groupId == groupId)
              .toList();
          subscription['refresh'] = {
            'succeeded': true,
            'nodeCount': after.length,
            'sameNodeIds': after.length == beforeIds.length &&
                after.every((node) => beforeIds.contains(node.id)),
            'selectionPreserved':
                await nodes.watchSelectedId().first == samples.first.id,
            'manualNodesPreserved': (await nodes.watchNodes().first)
                    .where((node) => node.groupId == null)
                    .length ==
                manual.length,
          };
        } on Exception catch (error) {
          subscription['refresh'] = {
            'succeeded': false,
            'error': _error(error)
          };
        }
        _emit({
          'event': 'subscription-refresh',
          'result': subscription['refresh']
        });
        await client.request('disconnect');
        fetcher.proxyPort = null;
        subscription['testedNodes'] = samples.length;
        for (final (index, node) in samples.indexed) {
          final result =
              await _verify(client, node, 'subscription-${index + 1}');
          results.add(result);
          _emit({'event': 'connection', ...result});
        }
      } on Exception catch (error) {
        report['subscription'] = {'imported': false, 'error': _error(error)};
        _emit(
            {'event': 'subscription-import', 'result': report['subscription']});
      } finally {
        await client.request('disconnect');
        fetcher.proxyPort = null;
      }
    }
  } on Object catch (error) {
    report['fatal'] = _error(error);
    exitCode = 1;
  } finally {
    await client.close();
    await database.close();
  }
  final connections = report['connections'] as List<Map<String, Object?>>?;
  final subscription = report['subscription'] as Map<String, Object?>?;
  final refresh = subscription?['refresh'] as Map<String, Object?>?;
  final passed = !report.containsKey('fatal') &&
      connections != null &&
      connections.isNotEmpty &&
      connections.every((item) =>
          item['httpsTransfer'] == true &&
          item['trafficRecorded'] == true &&
          item['listenerClosed'] == true &&
          !item.containsKey('cleanupError')) &&
      (subscription == null ||
          subscription['imported'] == true && refresh?['succeeded'] == true);
  report['passed'] = passed;
  exitCode = passed ? 0 : 1;
  _emit({'event': 'report', ...report});
}

void _emit(Map<String, Object?> result) => stdout.writeln(jsonEncode(result));

Map<String, Object?> _reviewSummary(SubscriptionReview review,
        {required bool accepted}) =>
    {
      'compatibleNodes': review.document.nodes.length,
      'skippedItems': review.document.skippedNodes,
      'issueCount': review.document.issues.length,
      'acceptedInMemory': accepted,
    };

ProxyNode _storedNode(Map<String, Object?> value) => ProxyNode(
      id: value['id']! as String,
      name: value['name']! as String,
      protocol: NodeProtocol.values
          .firstWhere((protocol) => protocol.wireName == value['protocol']),
      server: value['server']! as String,
      port: value['port']! as int,
      tls: value['tls']! as bool,
      options: NodeOptions.fromJson(value['options']! as Map<String, Object?>),
      credential: value['credential']! as String,
      revision: value['revision']! as int,
    );

String _error(Object error) => switch (error) {
      CoreGatewayException e => e.code,
      NodeException e => e.message,
      TimeoutException _ => 'timeout',
      HandshakeException _ => 'tls_handshake_failed',
      SocketException _ => 'socket_failed',
      HttpException _ => 'http_failed',
      _ => error.runtimeType.toString(),
    };

String _region(ProxyNode node) {
  for (final entry in const {
    'hk': ['香港', 'Hong Kong', '🇭🇰'],
    'jp': ['日本', 'Japan', '🇯🇵'],
    'sg': ['新加坡', 'Singapore', '🇸🇬'],
    'us': ['美国', 'United States', '🇺🇸'],
    'tw': ['台湾', 'Taiwan', '🇹🇼'],
    'kr': ['韩国', 'Korea', '🇰🇷'],
    'de': ['德国', 'Germany', '🇩🇪'],
    'gb': ['英国', 'United Kingdom', '🇬🇧'],
  }.entries) {
    if (entry.value.any(node.name.contains)) return entry.key;
  }
  return 'other';
}

List<ProxyNode> _samples(List<ProxyNode> nodes, int limit) {
  final result = <ProxyNode>[];
  final seen = <String>{};
  final ordered = [
    ...nodes.where((node) => _region(node) != 'other'),
    ...nodes.where((node) => _region(node) == 'other'),
  ];
  for (final node in ordered) {
    if (seen.add('${node.protocol.name}:${_region(node)}')) {
      result.add(node);
    }
    if (result.length >= limit) return result;
  }
  for (final node in ordered) {
    if (!result.contains(node)) result.add(node);
    if (result.length >= limit) break;
  }
  return result;
}

Future<Map<String, Object?>> _verify(
    HostSessionClient client, ProxyNode node, String alias) async {
  final result = <String, Object?>{
    'alias': alias,
    'protocol': node.protocol.label,
    'transport': node.options.transport,
    'tls': node.tls,
    'reality': node.options.realityPublicKey.isNotEmpty,
    'vision': node.options.flow == 'xtls-rprx-vision',
    if (node.subscriptionManaged) 'regionHint': _region(node),
    if (node.subscriptionManaged)
      'nameHint': node.name
          .replaceAll(RegExp(r'https?://\S+'), '')
          .replaceAll(RegExp(r'[^\u4e00-\u9fff\s]'), '')
          .trim(),
    'endpointClass': switch (InternetAddress.tryParse(node.server)) {
      InternetAddress a when a.isLoopback => 'loopback',
      InternetAddress a when a.address == '0.0.0.0' || a.address == '::' =>
        'unspecified',
      _ => 'remote',
    },
    if (node.protocol == NodeProtocol.shadowsocks)
      'cipher': node.options.method,
  };
  int? port;
  final started = Stopwatch()..start();
  try {
    final connected = await client.request('connect', {
      'node': node.toHost(),
      'mode': 'global',
      'systemProxy': false,
    });
    port = connected['proxyPort']! as int;
    result['coreReady'] = connected['phase'] == 'connected';
    final trace = await _trace(port);
    result.addAll(trace);
    result['httpsTransfer'] = true;
    final deadline = DateTime.now().add(const Duration(seconds: 22));
    Map<String, Object?> snapshot;
    do {
      snapshot = await client.request('snapshot');
      final telemetry = snapshot['telemetry']! as Map<String, Object?>;
      if ((telemetry['ip'] as String? ?? '').isNotEmpty ||
          (telemetry['probeError'] as String? ?? '').isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } while (DateTime.now().isBefore(deadline));
    final telemetry = snapshot['telemetry']! as Map<String, Object?>;
    result['telemetry'] = {
      'ip': telemetry['ip'],
      'countryCode': telemetry['countryCode'],
      'latencyMs': telemetry['latency'],
      'uploadBytes': telemetry['uploadTotal'],
      'downloadBytes': telemetry['downloadTotal'],
      'probeError': telemetry['probeError'],
    };
    result['trafficRecorded'] = (telemetry['uploadTotal']! as int) > 0 &&
        (telemetry['downloadTotal']! as int) > 0;
  } on Object catch (error) {
    result['httpsTransfer'] = false;
    result['error'] = _error(error);
    if (error is HandshakeException) {
      final text = error.toString();
      result['tlsFailure'] = [
        'CERTIFICATE_VERIFY_FAILED',
        'WRONG_VERSION_NUMBER',
        'UNEXPECTED_EOF',
        'Connection terminated during handshake',
      ].where(text.contains).toList();
    }
  } finally {
    try {
      await client.request('disconnect');
      if (port != null) {
        try {
          final socket = await Socket.connect('127.0.0.1', port,
              timeout: const Duration(milliseconds: 500));
          socket.destroy();
          result['listenerClosed'] = false;
        } on SocketException {
          result['listenerClosed'] = true;
        }
      }
    } on Exception catch (error) {
      result['cleanupError'] = _error(error);
    }
    result['durationMs'] = started.elapsedMilliseconds;
  }
  return result;
}

Future<Map<String, Object?>> _trace(int port) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..findProxy = (_) => 'PROXY 127.0.0.1:$port';
  final watch = Stopwatch()..start();
  try {
    return await (() async {
      final request = await client
          .getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'));
      request.headers.set('User-Agent', 'RainLink/0.1');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw NodeException('egress_http_${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        if (bytes.length + chunk.length > 64 * 1024) {
          throw const NodeException('egress_response_limit');
        }
        bytes.addAll(chunk);
      }
      final fields = <String, String>{};
      for (final line in const LineSplitter().convert(utf8.decode(bytes))) {
        final separator = line.indexOf('=');
        if (separator > 0) {
          fields[line.substring(0, separator)] = line.substring(separator + 1);
        }
      }
      if (InternetAddress.tryParse(fields['ip'] ?? '') == null) {
        throw const NodeException('egress_invalid_ip');
      }
      return <String, Object?>{
        'egressIp': fields['ip'],
        'countryCode': fields['loc'],
        'httpsRequestMs': watch.elapsedMilliseconds,
        'responseBytes': bytes.length,
      };
    })()
        .timeout(const Duration(seconds: 15));
  } finally {
    client.close(force: true);
  }
}

class _RemoteSecrets implements SecretStore {
  const _RemoteSecrets(this.client);
  final HostSessionClient client;

  @override
  Future<String> protect(String id, String username, String password,
          {String obfsPassword = ''}) async =>
      (await client.request('protect', {
        'id': id,
        'username': username,
        'password': password,
        'obfsPassword': obfsPassword,
      }))['cipher']! as String;

  @override
  Future<NodeCredentials> reveal(String id, String cipher) async {
    final value = await client.request('reveal', {'id': id, 'cipher': cipher});
    return NodeCredentials(
        username: value['username']! as String,
        password: value['password']! as String,
        obfsPassword: value['obfsPassword'] as String? ?? '');
  }
}

class _VerificationFetcher implements SubscriptionFetcher {
  int? proxyPort;

  @override
  Future<SubscriptionDocument> fetch(
          Uri url, SubscriptionCancellation cancellation) =>
      HttpSubscriptionFetcher(localProxyPort: () => proxyPort)
          .fetch(url, cancellation);
}
