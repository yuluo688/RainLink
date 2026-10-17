import 'dart:convert';

import '../../domain/nodes/node_validation.dart';
import '../../domain/nodes/proxy_node.dart';

/// The widely used v2rayN VMess link embeds a JSON object, not URI authority.
NodeDraft parseVmessBase64Uri(String input) {
  try {
    final parts = input.substring('vmess://'.length).split('#');
    final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts.first))));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException();
    }
    const supported = {
      'v',
      'ps',
      'add',
      'port',
      'id',
      'aid',
      'scy',
      'net',
      'type',
      'host',
      'path',
      'tls',
      'sni',
      'alpn',
      'fp',
      'allowInsecure',
      'packetEncoding',
      'globalPadding',
      'authenticatedLength'
    };
    if (decoded.keys.any((key) => !supported.contains(key))) {
      throw const NodeException('VMess 链接包含暂不支持的参数');
    }
    String text(String key, [String fallback = '']) =>
        decoded[key]?.toString() ?? fallback;
    int integer(String key, [int fallback = 0]) {
      final value = decoded[key];
      if (value == null || value == '') return fallback;
      final result = int.tryParse(value.toString());
      if (result == null) throw const FormatException();
      return result;
    }

    bool flag(String key) => switch (decoded[key]) {
          null || '' || false || 0 || '0' || 'false' => false,
          true || 1 || '1' || 'true' => true,
          _ => throw const FormatException(),
        };
    if (!['', '1', '2'].contains(text('v')) ||
        !['', 'none'].contains(text('type')) ||
        !['', 'none', 'tls'].contains(text('tls'))) {
      throw const NodeException('暂不支持此 VMess 链接版本、伪装或 TLS 模式');
    }
    final tls = text('tls') == 'tls';
    final server = text('add');
    final port = integer('port');
    if (parts.length > 2) throw const FormatException();
    final label = parts.length == 2
        ? Uri.decodeComponent(parts.last)
        : text('ps', '$server:$port');
    final name = label.isEmpty ? '$server:$port' : label;
    final transport = text('net', 'tcp');
    final draft = NodeDraft(
        name: name,
        protocol: NodeProtocol.vmess,
        server: server,
        port: port,
        tls: tls,
        authenticate: true,
        password: text('id'),
        options: NodeOptions(
            vmessSecurity: text('scy', 'auto'),
            alterId: integer('aid'),
            globalPadding: flag('globalPadding'),
            authenticatedLength: flag('authenticatedLength'),
            packetEncoding: text('packetEncoding'),
            transport: transport,
            host: text('host'),
            path: text('path', '/'),
            serviceName: transport == 'grpc' ? text('path') : '',
            serverName: text('sni').isEmpty && tls ? text('host') : text('sni'),
            fingerprint: text('fp'),
            insecure: flag('allowInsecure'),
            alpn: text('alpn').isEmpty ? const [] : text('alpn').split(',')));
    validateNode(draft);
    return draft;
  } on FormatException {
    // Decoding errors can embed source text, which includes the user's UUID.
    throw const NodeException('VMess 链接的 Base64、JSON 或字段格式无效');
  }
}
