import '../../domain/nodes/node_validation.dart';
import '../../domain/nodes/proxy_node.dart';

int parseTuicHeartbeat(Object? value, {bool milliseconds = false}) {
  if (value == null || value == '') return 10000;
  final text = value.toString().trim();
  final match = RegExp(r'^(\d+)(ms|s)?$').firstMatch(text);
  final number = match == null ? null : int.tryParse(match.group(1) ?? '');
  if (number == null) throw const NodeException('TUIC 心跳间隔格式无效');
  final unit = match?.group(2);
  return number * (unit == 's' || unit == null && !milliseconds ? 1000 : 1);
}

NodeDraft parseTuicUri(Uri uri) {
  final query = uri.queryParameters;
  const supported = {
    'sni',
    'alpn',
    'allow_insecure',
    'allowInsecure',
    'insecure',
    'congestion_control',
    'udp_relay_mode',
    'udp_over_stream',
    'zero_rtt_handshake',
    'reduce_rtt',
    'heartbeat',
    'disable_sni',
    'pinSHA256'
  };
  if (query.keys.any((key) => !supported.contains(key)) ||
      uri.queryParametersAll.values.any((values) => values.length != 1) ||
      uri.path.isNotEmpty && uri.path != '/') {
    throw const NodeException('TUIC 链接包含暂不支持或重复的参数');
  }
  bool flag(String key) => switch (query[key]) {
        null || '0' || 'false' => false,
        '1' || 'true' => true,
        _ => throw const NodeException('TUIC 开关参数无效'),
      };
  final auth = uri.userInfo.indexOf(':');
  if (auth < 0) throw const NodeException('TUIC v5 链接需要 UUID:密码');
  final insecureKeys = ['insecure', 'allow_insecure', 'allowInsecure']
      .where(query.containsKey)
      .toList();
  if (insecureKeys.map(flag).toSet().length > 1 ||
      query.containsKey('reduce_rtt') &&
          query.containsKey('zero_rtt_handshake') &&
          flag('reduce_rtt') != flag('zero_rtt_handshake')) {
    throw const NodeException('TUIC 链接的开关参数冲突');
  }
  final port = uri.hasPort ? uri.port : 443;
  final draft = NodeDraft(
      name: uri.fragment.isEmpty
          ? '${uri.host}:$port'
          : Uri.decodeComponent(uri.fragment),
      protocol: NodeProtocol.tuic,
      server: uri.host,
      port: port,
      tls: true,
      authenticate: true,
      username: Uri.decodeComponent(uri.userInfo.substring(0, auth)),
      password: Uri.decodeComponent(uri.userInfo.substring(auth + 1)),
      options: NodeOptions(
          transport: 'quic',
          serverName: query['sni'] ?? '',
          alpn: query['alpn']?.split(',') ?? const [],
          insecure: insecureKeys.any(flag),
          certificateSha256:
              normalizeCertificateSha256(query['pinSHA256'] ?? ''),
          congestionControl: query['congestion_control'] ?? 'cubic',
          udpRelayMode: query['udp_relay_mode'] ?? 'native',
          udpOverStream: flag('udp_over_stream'),
          zeroRttHandshake: flag('zero_rtt_handshake') || flag('reduce_rtt'),
          disableSni: flag('disable_sni'),
          heartbeatMillis: parseTuicHeartbeat(query['heartbeat'])));
  validateNode(draft);
  return draft;
}
