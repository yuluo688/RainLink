import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../../domain/groups/node_group.dart';
import '../../domain/groups/subscription_issue.dart';
import '../../domain/nodes/node_validation.dart';
import '../../domain/nodes/proxy_node.dart';
import 'tuic_uri_parser.dart';
import 'vmess_uri_parser.dart';
import 'singbox_outbound_parser.dart';

const maxSubscriptionNodes = 2000;

Uri validateSubscriptionUrl(String input) {
  final url = Uri.tryParse(input.trim());
  if (input.length > 4096 ||
      url == null ||
      !['http', 'https'].contains(url.scheme) ||
      url.host.isEmpty ||
      url.userInfo.isNotEmpty ||
      url.hasFragment) {
    throw const NodeException('请输入有效的 HTTP/HTTPS 订阅地址，不包含用户名或片段');
  }
  if (url.toString().length > 4096) throw const NodeException('订阅地址超过长度限制');
  return url;
}

String _decode64(String value) =>
    utf8.decode(base64Url.decode(base64Url.normalize(value.trim())));
String _string(Object? value, [String fallback = '']) => switch (value) {
  null => fallback,
  String() => value,
  num() => value.toString(),
  _ => throw const NodeException('节点字段类型无效'),
};
Map<String, Object?> _map(Object? value) {
  if (value == null) return const {};
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const NodeException('配置对象或字段名称无效');
  }
  return value.cast<String, Object?>();
}

List<String> _strings(Object? value) {
  if (value == null) return const [];
  if (value is! List) throw const NodeException('节点列表字段类型无效');
  return value.map((v) => _string(v)).toList();
}

int _port(Object? value) => int.tryParse(_string(value)) ?? 0;

/// Only imports upstream nodes. Remote rules, scripts and local listeners are never applied.
SubscriptionDocument parseSubscription(
  String body,
  Map<String, String> headers,
  Uri source,
) {
  var text = body.trim().replaceFirst('\uFEFF', '');
  if (text.isEmpty) throw const NodeException('订阅内容为空');
  if (!text.contains('://') &&
      !RegExp(r'(^|\n)\s*proxies\s*:').hasMatch(text) &&
      !text.startsWith('{')) {
    try {
      text = _decode64(text.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const NodeException(
        '无法识别订阅格式，请使用 Clash YAML、sing-box JSON 或节点分享链接列表',
      );
    }
  }
  final nodes = <NodeDraft>[];
  final issues = <SubscriptionIssue>[];
  var skipped = 0;
  void add(int item, NodeDraft Function() parse) {
    try {
      final node = parse();
      validateNode(node);
      if (_isProviderNotice(node)) {
        skipped++;
        issues.add(
          SubscriptionIssue(
            kind: SubscriptionIssueKind.notice,
            item: item,
            reason: '服务商提示信息，不是可连接节点',
          ),
        );
      } else {
        nodes.add(node);
      }
    } on NodeException catch (error) {
      skipped++;
      // Parser/validator messages are owned static text; never use the input,
      // decoded URI, YAML exception text or node name as a diagnostic.
      issues.add(
        SubscriptionIssue(
          kind:
              error.message.contains('不支持')
                  ? SubscriptionIssueKind.unsupported
                  : SubscriptionIssueKind.invalid,
          item: item,
          reason: error.message,
        ),
      );
    } on FormatException {
      skipped++;
      issues.add(
        SubscriptionIssue(
          kind: SubscriptionIssueKind.invalid,
          item: item,
          reason: '链接编码或字段格式无效',
        ),
      );
    } on TypeError {
      skipped++;
      issues.add(
        SubscriptionIssue(
          kind: SubscriptionIssueKind.invalid,
          item: item,
          reason: '节点字段类型无效',
        ),
      );
    }
  }

  if (text.startsWith('{') || RegExp(r'(^|\n)\s*proxies\s*:').hasMatch(text)) {
    Object? decoded;
    try {
      decoded = text.startsWith('{') ? jsonDecode(text) : loadYaml(text);
    } on FormatException {
      throw const NodeException('订阅配置格式无效');
    }
    final configuration = _map(decoded);
    if (configuration.containsKey('proxies') &&
        configuration.containsKey('outbounds')) {
      throw const NodeException('订阅同时包含两种节点格式，请分别导入');
    }
    final singbox = configuration.containsKey('outbounds');
    final proxies = configuration[singbox ? 'outbounds' : 'proxies'];
    if (proxies is! List) throw const NodeException('订阅中没有可识别的节点列表');
    if (proxies.length > maxSubscriptionNodes) {
      throw const NodeException('订阅节点超过 2000 个，请缩小订阅范围');
    }
    for (var index = 0; index < proxies.length; index++) {
      add(
        index + 1,
        () =>
            singbox
                ? parseSingBoxOutbound(_map(proxies[index]))
                : _clashNode(_map(proxies[index])),
      );
    }
    for (final entry
        in const {
          'proxy-groups': '代理策略组',
          'rules': '分流规则',
          'proxy-providers': '节点来源',
          'rule-providers': '规则来源',
          'script': '脚本',
          'dns': 'DNS 设置',
          'tun': 'TUN 设置',
          'inbounds': '入站与监听设置',
          'route': '路由设置',
          'experimental': '实验设置',
          'endpoints': '端点设置',
          'log': '日志设置',
          'services': '服务设置',
          'port': '本地 HTTP 端口',
          'socks-port': '本地 SOCKS 端口',
          'mixed-port': '本地混合端口',
          'redir-port': '重定向端口',
          'tproxy-port': '透明代理端口',
          'external-controller': '外部控制接口',
          'external-ui': '外部控制界面',
          'secret': '控制接口认证',
          'allow-lan': '局域网访问设置',
          'bind-address': '监听地址',
          'mode': '代理模式',
          'log-level': '日志级别',
          'ipv6': 'IPv6 设置',
        }.entries) {
      final option = configuration[entry.key];
      if (option != null &&
          option != false &&
          option != '' &&
          !(option is Map && option.isEmpty) &&
          !(option is List && option.isEmpty)) {
        issues.add(
          SubscriptionIssue(
            kind: SubscriptionIssueKind.configuration,
            reason: '${entry.value}不会应用，只导入节点',
          ),
        );
      }
    }
    const recognized = {
      'proxies',
      'outbounds',
      'proxy-groups',
      'rules',
      'proxy-providers',
      'rule-providers',
      'script',
      'dns',
      'tun',
      'inbounds',
      'route',
      'experimental',
      'endpoints',
      'log',
      'services',
      'port',
      'socks-port',
      'mixed-port',
      'redir-port',
      'tproxy-port',
      'external-controller',
      'external-ui',
      'secret',
      'allow-lan',
      'bind-address',
      'mode',
      'log-level',
      'ipv6',
    };
    if (configuration.keys.any((key) => !recognized.contains(key))) {
      issues.add(
        const SubscriptionIssue(
          kind: SubscriptionIssueKind.configuration,
          reason: '其他全局配置不会应用，只导入节点',
        ),
      );
    }
  } else {
    final lines =
        const LineSplitter()
            .convert(text)
            .where((v) => v.trim().isNotEmpty && !v.trimLeft().startsWith('#'))
            .toList();
    if (lines.length > maxSubscriptionNodes) {
      throw const NodeException('订阅节点超过 2000 个，请缩小订阅范围');
    }
    for (var index = 0; index < lines.length; index++) {
      add(index + 1, () => parseNodeUri(lines[index].trim()));
    }
  }
  // Some providers encode account/client notices as loopback SS nodes. Keep
  // legitimate local subscriptions, but never present those notices as routes.
  if (nodes.isEmpty &&
      issues.isNotEmpty &&
      issues.every((issue) => issue.kind == SubscriptionIssueKind.notice)) {
    throw const NodeException('订阅服务器仅返回提示信息，未提供可连接的节点；请检查套餐及客户端兼容性');
  }
  if (nodes.isEmpty) {
    if (skipped > 0) {
      throw SubscriptionContentException(skippedNodes: skipped, issues: issues);
    }
    throw const NodeException('订阅中没有可用节点');
  }
  final metadata = <String, int>{};
  for (final field in (headers['subscription-userinfo'] ?? '').split(';')) {
    final parts = field.trim().split('=');
    if (parts.length != 2) continue;
    final value = int.tryParse(parts[1].trim());
    if (value != null && value >= 0 && value <= 0x7fffffffffffffff) {
      metadata[parts[0].trim().toLowerCase()] = value;
    }
  }
  var name = headers['profile-title'] ?? '';
  if (name.startsWith('base64:')) {
    try {
      name = _decode64(name.substring(7));
    } on FormatException {
      name = '';
    }
  }
  if (name.isEmpty) {
    final disposition = headers['content-disposition'] ?? '';
    final match = RegExp(
      r'''filename\*?=(?:UTF-8''|"?)([^";]+)''',
      caseSensitive: false,
    ).firstMatch(disposition);
    if (match != null) {
      try {
        name = Uri.decodeComponent(match.group(1) ?? '');
      } on FormatException {
        name = '';
      }
    }
  }
  name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F/\\]'), '').trim();
  if (name.isEmpty) name = source.host;
  if (name.length > 128) name = name.substring(0, 128);
  final expires = metadata['expire'];
  final interval = int.tryParse(headers['profile-update-interval'] ?? '');
  return SubscriptionDocument(
    name: name,
    nodes: List.unmodifiable(nodes),
    skippedNodes: skipped,
    issues: List.unmodifiable(issues),
    uploaded: metadata['upload'],
    downloaded: metadata['download'],
    total: metadata['total'],
    expiresAt:
        expires != null && expires > 0 && expires < 253402300800
            ? DateTime.fromMillisecondsSinceEpoch(expires * 1000, isUtc: true)
            : null,
    intervalHours:
        interval != null && interval >= 1 && interval <= 168 ? interval : 24,
  );
}

bool _isProviderNotice(NodeDraft node) {
  final local =
      node.server.toLowerCase() == 'localhost' ||
      (InternetAddress.tryParse(node.server)?.isLoopback ?? false);
  return local &&
      RegExp(
        r'不支持.*(?:软件|客户端)|请.*(?:换用|更换).*(?:软件|客户端)|官网地址|(?:剩余|已用|总)流量|(?:套餐|订阅|账户).*(?:到期|过期)|到期时间|下次重置|流量.*(?:重置|用尽)|unsupported.*(?:client|software)',
        caseSensitive: false,
      ).hasMatch(node.name);
}

NodeProtocol _protocol(String name) => switch (name.toLowerCase()) {
  'ss' || 'shadowsocks' => NodeProtocol.shadowsocks,
  'vless' => NodeProtocol.vless,
  'vmess' => NodeProtocol.vmess,
  'tuic' => NodeProtocol.tuic,
  'trojan' => NodeProtocol.trojan,
  'hysteria2' || 'hy2' => NodeProtocol.hysteria2,
  'http' || 'https' => NodeProtocol.http,
  'socks' || 'socks5' => NodeProtocol.socks5,
  _ => throw const NodeException('暂不支持此协议'),
};

NodeDraft _clashNode(Map<String, Object?> value) {
  final type = _string(value['type']);
  final protocol = _protocol(type);
  final hysteria = protocol == NodeProtocol.hysteria2;
  final tuic = protocol == NodeProtocol.tuic;
  final vmess = protocol == NodeProtocol.vmess;
  const common = {
    'name',
    'type',
    'server',
    'port',
    'tls',
    'servername',
    'sni',
    'skip-cert-verify',
    'alpn',
    'network',
    'client-fingerprint',
    'udp',
  };
  final specific = switch (protocol) {
    NodeProtocol.http || NodeProtocol.socks5 => {'username', 'password'},
    NodeProtocol.shadowsocks => {'cipher', 'password'},
    NodeProtocol.vless => {
      'uuid',
      'flow',
      'encryption',
      'packet-encoding',
      'reality-opts',
      'ws-opts',
      'grpc-opts',
    },
    NodeProtocol.vmess => {
      'uuid',
      'cipher',
      'alterId',
      'global-padding',
      'authenticated-length',
      'packet-encoding',
      'ws-opts',
      'grpc-opts',
    },
    NodeProtocol.trojan => {'password', 'ws-opts', 'grpc-opts'},
    NodeProtocol.hysteria2 => {
      'password',
      'obfs',
      'obfs-password',
      'up',
      'down',
      'ports',
      'mport',
      'hop-interval',
      'fingerprint',
    },
    NodeProtocol.tuic => {
      'uuid',
      'password',
      'version',
      'congestion-controller',
      'udp-relay-mode',
      'udp-over-stream',
      'reduce-rtt',
      'disable-sni',
      'heartbeat-interval',
      'fingerprint',
    },
  };
  const disabledOptions = {
    'plugin',
    'plugin-opts',
    'dialer-proxy',
    'smux',
    'http-opts',
    'h2-opts',
    'udp-over-tcp',
    'tfo',
    'mptcp',
  };
  if (value.keys.any(
    (key) =>
        !common.contains(key) &&
        !specific.contains(key) &&
        !disabledOptions.contains(key),
  )) {
    throw const NodeException('节点包含暂不支持的附加字段');
  }
  // Never silently discard parameters that would change the remote connection.
  for (final key in [
    'plugin',
    'plugin-opts',
    'dialer-proxy',
    'smux',
    'http-opts',
    'h2-opts',
    'tfo',
    'mptcp',
  ]) {
    final option = value[key];
    if (option != null &&
        option != false &&
        option != '' &&
        !(option is Map && option.isEmpty) &&
        !(key == 'smux' &&
            _map(option).length == 1 &&
            _map(option)['enabled'] == false)) {
      throw const NodeException('此附加配置暂不支持');
    }
  }
  if (_strictBool(value['udp-over-tcp'])) {
    throw const NodeException('暂不支持 UDP over TCP');
  }
  if (value['udp'] != null &&
      !_strictBool(value['udp']) &&
      protocol != NodeProtocol.http) {
    throw const NodeException('暂不支持按节点禁用 UDP');
  }
  if (hysteria || tuic) {
    for (final key in [
      'certificate',
      'private-key',
      'name-cert-verify',
      'ca',
      'ca-str',
      'recv-window-conn',
      'recv-window',
      'disable-mtu-discovery',
      'fast-open',
    ]) {
      if (value[key] != null && value[key] != false && value[key] != '') {
        throw const NodeException('暂不支持此证书或 QUIC 扩展');
      }
    }
    if (value['tls'] == false ||
        !['', 'quic'].contains(_string(value['network']))) {
      throw const NodeException('Hysteria2 和 TUIC 必须使用 QUIC 和 TLS');
    }
  }
  if (tuic &&
      (value.containsKey('token') ||
          value.containsKey('version') &&
              _strictInt(value['version'], 5) != 5 ||
          value.containsKey('ip') ||
          value.containsKey('request-timeout') ||
          value.containsKey('max-open-streams') ||
          value.containsKey('max-udp-relay-packet-size'))) {
    throw const NodeException('仅支持 TUIC v5，暂不支持此 TUIC 扩展');
  }
  if (protocol == NodeProtocol.vless &&
      !['', 'none'].contains(_string(value['encryption']))) {
    throw const NodeException('暂不支持此 VLESS 加密选项');
  }
  final ws = _map(value['ws-opts']);
  if (ws.keys.any(
    (key) =>
        !{
          'path',
          'headers',
          'max-early-data',
          'early-data-header-name',
        }.contains(key),
  )) {
    throw const NodeException('暂不支持此 WebSocket 扩展');
  }
  if ((_port(ws['max-early-data']) != 0) ||
      ws.containsKey('early-data-header-name')) {
    throw const NodeException('暂不支持 WebSocket Early Data');
  }
  final wsHeaders = _map(ws['headers']);
  if (wsHeaders.keys.any((k) => k.toLowerCase() != 'host')) {
    throw const NodeException('暂不支持自定义 WebSocket 头');
  }
  if (wsHeaders.length > 1) throw const NodeException('WebSocket Host 参数重复');
  final reality = _map(value['reality-opts']);
  if (reality.keys.any((key) => !{'public-key', 'short-id'}.contains(key))) {
    throw const NodeException('暂不支持此 Reality 扩展');
  }
  final grpc = _map(value['grpc-opts']);
  if (grpc.keys.any((key) => key != 'grpc-service-name')) {
    throw const NodeException('暂不支持此 gRPC 扩展');
  }
  final transport =
      protocol.usesQuic ? 'quic' : _string(value['network'], 'tcp');
  if (ws.isNotEmpty && transport != 'ws' ||
      grpc.isNotEmpty && transport != 'grpc') {
    throw const NodeException('附加传输参数与传输方式不匹配');
  }
  final name = _string(
    value['name'],
    '${_string(value['server'])}:${_string(value['port'])}',
  );
  final explicitTls = value['tls'] == null ? null : _strictBool(value['tls']);
  final requiredTls =
      protocol.usesQuic || protocol == NodeProtocol.trojan || type == 'https';
  if (requiredTls && explicitTls == false) {
    throw const NodeException('此协议需要启用 TLS');
  }
  final tls = requiredTls || (explicitTls ?? false);
  if (!tls &&
      (_string(value['servername'] ?? value['sni']).isNotEmpty ||
          _strictBool(value['skip-cert-verify']) ||
          _strings(value['alpn']).isNotEmpty ||
          _string(value['client-fingerprint']).isNotEmpty ||
          reality.isNotEmpty)) {
    throw const NodeException('TLS 参数需要启用 TLS');
  }
  if (value['servername'] != null &&
      value['sni'] != null &&
      value['servername'] != value['sni']) {
    throw const NodeException('SNI 参数冲突');
  }
  final options = NodeOptions(
    method: _string(value['cipher'], 'aes-128-gcm'),
    vmessSecurity: vmess ? _string(value['cipher'], 'auto') : 'auto',
    alterId: vmess ? _strictInt(value['alterId'], 0) : 0,
    globalPadding: vmess && _strictBool(value['global-padding']),
    authenticatedLength: vmess && _strictBool(value['authenticated-length']),
    packetEncoding: _string(value['packet-encoding']),
    congestionControl:
        tuic ? _string(value['congestion-controller'], 'cubic') : 'cubic',
    udpRelayMode: tuic ? _string(value['udp-relay-mode'], 'native') : 'native',
    udpOverStream: tuic && _strictBool(value['udp-over-stream']),
    zeroRttHandshake: tuic && _strictBool(value['reduce-rtt']),
    disableSni: tuic && _strictBool(value['disable-sni']),
    heartbeatMillis:
        tuic
            ? parseTuicHeartbeat(
              value['heartbeat-interval'],
              milliseconds: true,
            )
            : 10000,
    serverName: _string(value['servername'] ?? value['sni']),
    insecure: _strictBool(value['skip-cert-verify']),
    transport: transport,
    path: _string(ws['path'], '/'),
    host: _string(wsHeaders['Host'] ?? wsHeaders['host']),
    serviceName: _string(grpc['grpc-service-name']),
    flow: _string(value['flow']),
    fingerprint: _string(value['client-fingerprint']),
    certificateSha256:
        protocol.usesQuic
            ? normalizeCertificateSha256(_string(value['fingerprint']))
            : '',
    realityPublicKey: _string(reality['public-key']),
    realityShortId: _string(reality['short-id']),
    alpn: _strings(value['alpn']),
    obfs: hysteria ? _string(value['obfs']) : '',
    upMbps: hysteria ? _hysteriaBandwidth(value['up']) : 0,
    downMbps: hysteria ? _hysteriaBandwidth(value['down']) : 0,
    serverPorts: hysteria ? _clashHysteriaPorts(value) : const [],
    hopIntervalSeconds: hysteria ? _hysteriaInterval(value['hop-interval']) : 0,
  );
  return NodeDraft(
    name: name,
    protocol: protocol,
    server: _string(value['server']),
    port: _port(value['port']),
    tls: tls,
    username: _string(tuic ? value['uuid'] : value['username']),
    password: _string(
      protocol == NodeProtocol.vless || vmess
          ? value['uuid']
          : value['password'],
    ),
    obfsPassword: hysteria ? _string(value['obfs-password']) : '',
    authenticate:
        value['username'] != null ||
        value['password'] != null ||
        value['uuid'] != null,
    options: options,
  );
}

NodeDraft parseNodeUri(String input) {
  if (input.length > 65536) throw const NodeException('节点分享链接超过长度限制');
  var text = input;
  if (text.startsWith('vmess://') &&
      !text.substring(8).split('#').first.contains('@')) {
    return parseVmessBase64Uri(text);
  }
  if (text.startsWith('ss://') &&
      !text.substring(5).split('#').first.contains('@')) {
    final parts = text.substring(5).split('#');
    text =
        'ss://${_decode64(parts.first)}${parts.length > 1 ? '#${parts.skip(1).join('#')}' : ''}';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) {
    throw const NodeException('节点链接地址或端口无效');
  }
  final protocol = _protocol(uri.scheme);
  if (protocol == NodeProtocol.hysteria2) return _hysteriaUri(uri);
  if (protocol == NodeProtocol.tuic) return parseTuicUri(uri);
  // Uri normalizes an explicit :80/:443 away. HTTP share links also use the
  // scheme's default port when omitted; other protocols require a port.
  if (!uri.hasPort && protocol != NodeProtocol.http) {
    throw const NodeException('节点链接地址或端口无效');
  }
  final query = uri.queryParameters;
  final stream = [
    NodeProtocol.vless,
    NodeProtocol.vmess,
    NodeProtocol.trojan,
  ].contains(protocol);
  final common = {
    if (stream || protocol == NodeProtocol.http) ...{
      'security',
      'sni',
      'peer',
      'allowInsecure',
      'insecure',
      'fp',
      'alpn',
    },
    if (stream) ...{'type', 'path', 'host', 'serviceName'},
    if (protocol == NodeProtocol.vless) ...{
      'flow',
      'pbk',
      'sid',
      'encryption',
      'packetEncoding',
    },
    if (protocol == NodeProtocol.vmess) ...{
      'encryption',
      'alterId',
      'packetEncoding',
    },
  };
  if (query.keys.any((k) => !common.contains(k)) ||
      uri.queryParametersAll.values.any((values) => values.length != 1) ||
      (query['encryption'] != null &&
          !(protocol == NodeProtocol.vmess
              ? vmessSecurityMethods.contains(query['encryption'])
              : query['encryption'] == 'none')) ||
      query.containsKey('alterId') && protocol != NodeProtocol.vmess) {
    throw const NodeException('节点链接包含暂不支持的参数');
  }
  var username = '';
  var password = '';
  var method = 'aes-128-gcm';
  if (protocol == NodeProtocol.shadowsocks) {
    var user = Uri.decodeComponent(uri.userInfo);
    if (!user.contains(':')) user = _decode64(user);
    final split = user.indexOf(':');
    if (split < 1) throw const NodeException('Shadowsocks 凭据格式无效');
    method = user.substring(0, split);
    password = user.substring(split + 1);
  } else if (protocol == NodeProtocol.vless ||
      protocol == NodeProtocol.vmess ||
      protocol == NodeProtocol.trojan) {
    password = Uri.decodeComponent(uri.userInfo);
  } else {
    final user = uri.userInfo.split(':');
    username = Uri.decodeComponent(user.first);
    if (user.length > 1) password = Uri.decodeComponent(user.skip(1).join(':'));
  }
  final security =
      query['security'] ??
      (protocol == NodeProtocol.trojan || uri.scheme == 'https'
          ? 'tls'
          : 'none');
  if (!['tls', 'none', 'reality'].contains(security) ||
      security == 'reality' &&
          (protocol != NodeProtocol.vless || (query['pbk'] ?? '').isEmpty) ||
      query.containsKey('pbk') && security != 'reality' ||
      uri.scheme == 'https' && security != 'tls') {
    throw const NodeException('TLS 安全参数无效');
  }
  final transport = query['type'] ?? 'tcp';
  if (query.containsKey('path') && transport != 'ws' ||
      query.containsKey('host') && transport != 'ws' ||
      query.containsKey('serviceName') && transport != 'grpc') {
    throw const NodeException('附加传输参数与传输方式不匹配');
  }
  final allowInsecureFlag = _uriFlag(query['allowInsecure']);
  final insecureFlag = _uriFlag(query['insecure']);
  final insecure = allowInsecureFlag || insecureFlag;
  if (query.containsKey('allowInsecure') &&
          query.containsKey('insecure') &&
          allowInsecureFlag != insecureFlag ||
      query.containsKey('sni') &&
          query.containsKey('peer') &&
          query['sni'] != query['peer']) {
    throw const NodeException('节点链接的 TLS 参数冲突');
  }
  if (security == 'none' &&
      (insecure ||
          (query['sni'] ?? query['peer'] ?? '').isNotEmpty ||
          (query['fp'] ?? '').isNotEmpty ||
          (query['alpn'] ?? '').isNotEmpty)) {
    throw const NodeException('TLS 参数需要启用 TLS');
  }
  if (uri.path.isNotEmpty && uri.path != '/') {
    throw const NodeException('分享链接路径无效');
  }
  final options = NodeOptions(
    method: method,
    vmessSecurity:
        protocol == NodeProtocol.vmess ? query['encryption'] ?? 'auto' : 'auto',
    alterId: _strictInt(query['alterId'], 0),
    packetEncoding: query['packetEncoding'] ?? '',
    serverName: query['sni'] ?? query['peer'] ?? '',
    insecure: insecure,
    transport: transport,
    path: query['path'] ?? '/',
    host: query['host'] ?? '',
    serviceName: query['serviceName'] ?? '',
    flow: query['flow'] ?? '',
    fingerprint: query['fp'] ?? '',
    realityPublicKey: query['pbk'] ?? '',
    realityShortId: query['sid'] ?? '',
    alpn: query['alpn']?.split(',') ?? const [],
  );
  final draft = NodeDraft(
    name:
        uri.fragment.isEmpty
            ? '${uri.host}:${uri.port}'
            : Uri.decodeComponent(uri.fragment),
    protocol: protocol,
    server: uri.host,
    port: uri.port,
    tls: security != 'none',
    authenticate: uri.userInfo.isNotEmpty,
    username: username,
    password: password,
    options: options,
  );
  validateNode(draft);
  return draft;
}

int _strictInt(Object? value, int fallback) {
  if (value == null) return fallback;
  final parsed = int.tryParse(value.toString());
  if (parsed == null) throw const NodeException('节点整数参数无效');
  return parsed;
}

bool _strictBool(Object? value) => switch (value) {
  null || false || 'false' => false,
  true || 'true' => true,
  _ => throw const NodeException('节点开关参数无效'),
};

bool _uriFlag(String? value) => switch (value) {
  null || '0' || 'false' => false,
  '1' || 'true' => true,
  _ => throw const NodeException('节点链接开关参数无效'),
};

int _hysteriaBandwidth(Object? value) {
  if (value == null || value == '') return 0;
  final match = RegExp(
    r'^(\d+)(?:\s*(?:mbps|m))?$',
    caseSensitive: false,
  ).firstMatch(_string(value).trim());
  final result = match == null ? null : int.tryParse(match.group(1) ?? '');
  if (result == null || result > maxHysteriaBandwidthMbps) {
    throw const NodeException('Hysteria2 带宽应为整数 Mbps');
  }
  return result;
}

List<String> _hysteriaPorts(Object? value) => parseHysteriaPorts(
  value is List ? value.map((v) => _string(v)).join(',') : _string(value),
);

List<String> _clashHysteriaPorts(Map<String, Object?> value) {
  final ports = _hysteriaPorts(value['ports']);
  final alias = _hysteriaPorts(value['mport']);
  if (ports.isNotEmpty &&
      alias.isNotEmpty &&
      ports.join(',') != alias.join(',')) {
    throw const NodeException('Hysteria2 跳跃端口参数冲突');
  }
  return ports.isNotEmpty ? ports : alias;
}

int _hysteriaInterval(Object? value) {
  if (value == null || value == '') return 0;
  final result = int.tryParse(
    _string(value).trim().replaceFirst(RegExp(r's$'), ''),
  );
  if (result == null) throw const NodeException('端口跳跃间隔应为整数秒');
  return result;
}

NodeDraft _hysteriaUri(Uri uri) {
  final query = uri.queryParameters;
  const supported = {
    'sni',
    'insecure',
    'allowInsecure',
    'alpn',
    'obfs',
    'obfs-password',
    'mport',
    'up',
    'down',
    'hop-interval',
    'pinSHA256',
  };
  if (query.keys.any((key) => !supported.contains(key)) ||
      uri.queryParametersAll.values.any((values) => values.length != 1) ||
      uri.path.isNotEmpty && uri.path != '/') {
    throw const NodeException('Hysteria2 链接包含暂不支持或重复的参数');
  }
  final port = uri.hasPort ? uri.port : 443;
  final insecure = _uriFlag(query['insecure']);
  final allowInsecure = _uriFlag(query['allowInsecure']);
  if (query.containsKey('insecure') &&
      query.containsKey('allowInsecure') &&
      insecure != allowInsecure) {
    throw const NodeException('Hysteria2 链接的开关参数冲突');
  }
  final draft = NodeDraft(
    name:
        uri.fragment.isEmpty
            ? '${uri.host}:$port'
            : Uri.decodeComponent(uri.fragment),
    protocol: NodeProtocol.hysteria2,
    server: uri.host,
    port: port,
    tls: true,
    authenticate: true,
    password: Uri.decodeComponent(uri.userInfo),
    obfsPassword: query['obfs-password'] ?? '',
    options: NodeOptions(
      transport: 'quic',
      serverName: query['sni'] ?? '',
      certificateSha256: normalizeCertificateSha256(query['pinSHA256'] ?? ''),
      insecure: insecure || allowInsecure,
      alpn: query['alpn']?.split(',') ?? const [],
      obfs: query['obfs'] ?? '',
      upMbps: _hysteriaBandwidth(query['up']),
      downMbps: _hysteriaBandwidth(query['down']),
      serverPorts: _hysteriaPorts(query['mport']),
      hopIntervalSeconds: _hysteriaInterval(query['hop-interval']),
    ),
  );
  validateNode(draft);
  return draft;
}
