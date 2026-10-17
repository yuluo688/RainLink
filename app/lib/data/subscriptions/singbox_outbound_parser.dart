import '../../domain/nodes/node_validation.dart';
import '../../domain/nodes/proxy_node.dart';

/// Imports the node subset supported by our domain model and pinned core.
/// Dialer overrides, detours and configuration-only outbounds need review;
/// translating them to a direct connection would change their meaning.
NodeDraft parseSingBoxOutbound(Map<String, Object?> value) {
  final protocol = switch (_text(value['type'])) {
    'http' => NodeProtocol.http,
    'socks' => NodeProtocol.socks5,
    'shadowsocks' => NodeProtocol.shadowsocks,
    'vless' => NodeProtocol.vless,
    'vmess' => NodeProtocol.vmess,
    'trojan' => NodeProtocol.trojan,
    'hysteria2' => NodeProtocol.hysteria2,
    'tuic' => NodeProtocol.tuic,
    'selector' ||
    'urltest' ||
    'direct' ||
    'block' ||
    'dns' =>
      throw const NodeException('此出站是策略或内置行为，不支持作为节点导入'),
    _ => throw const NodeException('暂不支持此 sing-box 出站协议'),
  };
  final specific = switch (protocol) {
    NodeProtocol.http => {'username', 'password'},
    NodeProtocol.socks5 => {'version', 'username', 'password'},
    NodeProtocol.shadowsocks => {'method', 'password'},
    NodeProtocol.vless => {'uuid', 'flow', 'packet_encoding', 'transport'},
    NodeProtocol.vmess => {
        'uuid',
        'security',
        'alter_id',
        'global_padding',
        'authenticated_length',
        'packet_encoding',
        'transport',
      },
    NodeProtocol.trojan => {'password', 'transport'},
    NodeProtocol.hysteria2 => {
        'password',
        'up_mbps',
        'down_mbps',
        'obfs',
        'server_ports',
        'hop_interval',
      },
    NodeProtocol.tuic => {
        'uuid',
        'password',
        'congestion_control',
        'udp_relay_mode',
        'udp_over_stream',
        'zero_rtt_handshake',
        'heartbeat',
      },
  };
  _fields(value, {'type', 'tag', 'server', 'server_port', 'tls', ...specific},
      '此出站包含暂不支持的附加字段（如拨号、代理链或复用配置）');
  if (protocol == NodeProtocol.socks5 &&
      ![null, '5'].contains(value['version'])) {
    throw const NodeException('仅支持 SOCKS5 出站');
  }

  final tls = _object(value['tls']);
  _fields(
      tls,
      {
        'enabled',
        'server_name',
        'insecure',
        'alpn',
        'disable_sni',
        'utls',
        'reality',
        'rainlink_certificate_sha256'
      },
      '暂不支持此 TLS 附加配置（如自定义证书、分片或 ECH）');
  final enabled = _flag(tls['enabled']);
  if (!enabled && tls.keys.any((key) => key != 'enabled')) {
    throw const NodeException('TLS 参数与启用状态不匹配');
  }
  final utls = _object(tls['utls']);
  _fields(utls, {'enabled', 'fingerprint'}, '暂不支持此 TLS 指纹扩展');
  final utlsEnabled = _flag(utls['enabled']);
  if (!utlsEnabled && utls.keys.any((key) => key != 'enabled')) {
    throw const NodeException('TLS 指纹参数与启用状态不匹配');
  }
  final reality = _object(tls['reality']);
  _fields(reality, {'enabled', 'public_key', 'short_id'}, '暂不支持此 Reality 扩展');
  final realityEnabled = _flag(reality['enabled']);
  if (!realityEnabled && reality.keys.any((key) => key != 'enabled')) {
    throw const NodeException('Reality 参数与启用状态不匹配');
  }
  if (utlsEnabled && _text(utls['fingerprint']).isEmpty ||
      realityEnabled && _text(reality['public_key']).isEmpty) {
    throw const NodeException('TLS 指纹或 Reality 缺少必填参数');
  }

  final transport = _object(value['transport']);
  final transportType = transport.isEmpty
      ? (protocol.usesQuic ? 'quic' : 'tcp')
      : _text(transport['type']);
  final headers = _object(transport['headers']);
  switch (transportType) {
    case 'tcp' || 'quic':
      if (transport.isNotEmpty) {
        throw const NodeException('原生传输不支持附加传输对象');
      }
    case 'ws':
      _fields(transport, {'type', 'path', 'headers'},
          '暂不支持此 WebSocket 扩展（如 Early Data）');
      if (headers.keys.any((key) => key.toLowerCase() != 'host') ||
          headers.length > 1) {
        throw const NodeException('暂不支持自定义 WebSocket 头');
      }
    case 'grpc':
      _fields(transport, {'type', 'service_name'}, '暂不支持此 gRPC 扩展');
    default:
      throw const NodeException('暂不支持此 sing-box 传输方式');
  }
  final host =
      headers.isEmpty ? const <String>[] : _list(headers.values.single);
  if (host.length > 1) throw const NodeException('WebSocket Host 只能填写一个值');
  final obfs = _object(value['obfs']);
  _fields(obfs, {'type', 'password'}, '暂不支持此混淆扩展');
  final server = _text(value['server']);
  final port = _integer(value['server_port']);
  final tag = _text(value['tag']);
  final draft = NodeDraft(
    name: tag.isEmpty ? '$server:$port' : tag,
    protocol: protocol,
    server: server,
    port: port,
    tls: enabled,
    authenticate: value['username'] != null ||
        value['password'] != null ||
        value['uuid'] != null,
    username: _text(
        protocol == NodeProtocol.tuic ? value['uuid'] : value['username']),
    password: _text([NodeProtocol.vless, NodeProtocol.vmess].contains(protocol)
        ? value['uuid']
        : value['password']),
    obfsPassword: _text(obfs['password']),
    options: NodeOptions(
      method: _text(value['method'], 'aes-128-gcm'),
      vmessSecurity: _text(value['security'], 'auto'),
      alterId: _integer(value['alter_id']),
      globalPadding: _flag(value['global_padding']),
      authenticatedLength: _flag(value['authenticated_length']),
      packetEncoding: _text(value['packet_encoding']),
      flow: _text(value['flow']),
      serverName: _text(tls['server_name']),
      insecure: _flag(tls['insecure']),
      alpn: _list(tls['alpn']),
      disableSni: _flag(tls['disable_sni']),
      certificateSha256:
          normalizeCertificateSha256(_text(tls['rainlink_certificate_sha256'])),
      fingerprint: utlsEnabled ? _text(utls['fingerprint']) : '',
      realityPublicKey: realityEnabled ? _text(reality['public_key']) : '',
      realityShortId: realityEnabled ? _text(reality['short_id']) : '',
      transport: transportType,
      path: _text(transport['path'], '/'),
      host: host.firstOrNull ?? '',
      serviceName: _text(transport['service_name']),
      obfs: _text(obfs['type']),
      upMbps: _integer(value['up_mbps']),
      downMbps: _integer(value['down_mbps']),
      serverPorts: parseHysteriaPorts(_list(value['server_ports']).join(',')),
      hopIntervalSeconds: _duration(value['hop_interval'],
              fallbackMillis: 0, wholeSeconds: true) ~/
          1000,
      congestionControl: _text(value['congestion_control'], 'cubic'),
      udpRelayMode: _text(value['udp_relay_mode'], 'native'),
      udpOverStream: _flag(value['udp_over_stream']),
      zeroRttHandshake: _flag(value['zero_rtt_handshake']),
      heartbeatMillis: _duration(value['heartbeat'], fallbackMillis: 10000),
    ),
  );
  validateNode(draft);
  return draft;
}

void _fields(Map<String, Object?> value, Set<String> allowed, String reason) {
  if (value.keys.any((key) => !allowed.contains(key))) {
    throw NodeException(reason);
  }
}

Map<String, Object?> _object(Object? value) {
  if (value == null) return const {};
  if (value is! Map<String, Object?>) throw const NodeException('节点对象字段类型无效');
  return value;
}

String _text(Object? value, [String fallback = '']) => switch (value) {
      null => fallback,
      String() => value,
      _ => throw const NodeException('节点文本字段类型无效'),
    };

int _integer(Object? value) => switch (value) {
      null => 0,
      int() => value,
      _ => throw const NodeException('节点整数字段类型无效'),
    };

bool _flag(Object? value) => switch (value) {
      null || false => false,
      true => true,
      _ => throw const NodeException('节点开关字段类型无效'),
    };

List<String> _list(Object? value) {
  if (value == null) return const [];
  if (value is String) return [value];
  if (value is! List) throw const NodeException('节点列表字段类型无效');
  return value.map((value) => _text(value)).toList();
}

int _duration(Object? value,
    {required int fallbackMillis, bool wholeSeconds = false}) {
  if (value == null) return fallbackMillis;
  final match = RegExp(r'^(\d+)(ms|s|m)$').firstMatch(_text(value));
  final amount = match == null ? null : int.tryParse(match.group(1) ?? '');
  if (amount == null || amount > 86400000) {
    throw const NodeException('持续时间应使用整数 ms、s 或 m');
  }
  final millis =
      amount * switch (match?.group(2)) { 'ms' => 1, 's' => 1000, _ => 60000 };
  if (wholeSeconds && millis % 1000 != 0) {
    throw const NodeException('端口跳跃间隔需要完整秒数');
  }
  return millis;
}
