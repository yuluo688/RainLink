import 'dart:convert';
import 'dart:io';
import 'proxy_node.dart';

const shadowsocksMethods = [
  'aes-128-gcm',
  'aes-256-gcm',
  'chacha20-ietf-poly1305',
  '2022-blake3-aes-128-gcm',
  '2022-blake3-aes-256-gcm',
  '2022-blake3-chacha20-poly1305',
];
const tlsFingerprints = [
  '',
  'chrome',
  'firefox',
  'safari',
  'ios',
  'android',
  'edge',
  'random',
  'randomized'
];

const maxHysteriaBandwidthMbps = 1000000;
const vmessSecurityMethods = [
  'auto',
  'none',
  'zero',
  'aes-128-gcm',
  'chacha20-poly1305',
];
const tuicCongestionControls = ['cubic', 'new_reno', 'bbr'];
const udpPacketEncodings = ['', 'packetaddr', 'xudp'];

bool isValidNodeUuid(String value) => RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
    .hasMatch(value);

String normalizeCertificateSha256(String input) {
  final value = input.trim().replaceAll(':', '').toLowerCase();
  if (value.isNotEmpty && !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw const NodeException('证书指纹应为 64 位 SHA-256 十六进制字符');
  }
  return value;
}

/// Converts a comma-separated port list to sing-box's canonical range syntax.
List<String> parseHysteriaPorts(String input) {
  if (input.trim().isEmpty) return const [];
  final parts = input.split(',');
  if (parts.length > 64) throw const NodeException('跳跃端口最多填写 64 项');
  return parts.map((part) {
    final range = part.trim().replaceAll('-', ':').split(':');
    final start = int.tryParse(range.first);
    final end = range.length == 2 ? int.tryParse(range.last) : start;
    if (range.length > 2 ||
        start == null ||
        end == null ||
        start < 1 ||
        end > 65535 ||
        end < start) {
      throw const NodeException('跳跃端口应为 1–65535 的端口或范围，如 443,20000-30000');
    }
    return range.length == 1 ? '$start' : '$start:$end';
  }).toList(growable: false);
}

void validateNode(NodeDraft draft, {bool preservingSecret = false}) {
  final server = draft.server.trim();
  if (draft.name.trim().isEmpty ||
      draft.name.trim().length > 128 ||
      draft.name.contains(RegExp(r'[\x00-\x1F\x7F]'))) {
    throw const NodeException('请输入 1–128 个字符的节点名称');
  }
  if (server.isEmpty ||
      server.length > 253 ||
      RegExp(r'[\s/\\@?#\x00]').hasMatch(server) ||
      server.contains(':') && InternetAddress.tryParse(server) == null) {
    throw const NodeException('请输入域名或 IP，不包含协议、端口或路径');
  }
  if (draft.port < 1 || draft.port > 65535) {
    throw const NodeException('端口必须在 1–65535 之间');
  }
  if (draft.username.length > 4096 ||
      draft.password.length > 4096 ||
      draft.obfsPassword.length > 4096) {
    throw const NodeException('凭据长度超过限制');
  }
  final options = draft.options;
  if (options.serverName.length > 253 ||
      options.serverName.contains(RegExp(r'[\s/\\\x00]')) ||
      options.host.length > 512 ||
      options.host.contains(RegExp(r'[\r\n\x00]')) ||
      options.path.length > 2048 ||
      options.path.contains(RegExp(r'[\r\n\x00]')) ||
      options.serviceName.length > 256 ||
      options.serviceName.contains(RegExp(r'[\r\n\x00]'))) {
    throw const NodeException('TLS 或传输参数格式无效');
  }
  if (!['tcp', 'ws', 'grpc', 'quic'].contains(options.transport) ||
      !tlsFingerprints.contains(options.fingerprint)) {
    throw const NodeException('暂不支持此传输方式或 TLS 指纹');
  }
  final hysteria = draft.protocol == NodeProtocol.hysteria2;
  final tuic = draft.protocol == NodeProtocol.tuic;
  if (draft.protocol.usesQuic &&
      (!draft.tls ||
          options.transport != 'quic' ||
          options.fingerprint.isNotEmpty)) {
    throw const NodeException('Hysteria2 和 TUIC 使用 QUIC 与 TLS，不支持附加传输或 TLS 指纹');
  }
  if (options.certificateSha256.isNotEmpty && !draft.protocol.usesQuic) {
    throw const NodeException('此证书指纹选项仅用于 Hysteria2 和 TUIC');
  }
  normalizeCertificateSha256(options.certificateSha256);
  if (hysteria) {
    if (!draft.tls ||
        options.transport != 'quic' ||
        options.fingerprint.isNotEmpty ||
        draft.username.isNotEmpty) {
      throw const NodeException('Hysteria2 使用 QUIC 和 TLS，不支持附加传输或 TLS 指纹');
    }
    if (!['', 'salamander'].contains(options.obfs) ||
        options.obfs.isEmpty && draft.obfsPassword.isNotEmpty ||
        options.obfs.isNotEmpty &&
            !preservingSecret &&
            draft.obfsPassword.isEmpty) {
      throw const NodeException('Salamander 混淆需要填写独立的混淆密码');
    }
    if (options.upMbps < 0 ||
        options.downMbps < 0 ||
        options.upMbps > maxHysteriaBandwidthMbps ||
        options.downMbps > maxHysteriaBandwidthMbps) {
      throw const NodeException('上传和下载带宽应为 0–1000000 Mbps，0 表示自动');
    }
    parseHysteriaPorts(options.serverPorts.join(','));
    if (options.hopIntervalSeconds != 0 &&
        (options.serverPorts.isEmpty ||
            options.hopIntervalSeconds < 5 ||
            options.hopIntervalSeconds > 86400)) {
      throw const NodeException('端口跳跃间隔应为 5–86400 秒，并填写跳跃端口');
    }
  } else if (options.transport == 'quic' && !tuic ||
      options.obfs.isNotEmpty ||
      draft.obfsPassword.isNotEmpty ||
      options.upMbps != 0 ||
      options.downMbps != 0 ||
      options.serverPorts.isNotEmpty ||
      options.hopIntervalSeconds != 0) {
    throw const NodeException('混淆、带宽和端口跳跃选项仅用于 Hysteria2');
  }
  if (tuic) {
    if (!tuicCongestionControls.contains(options.congestionControl) ||
        !['native', 'quic'].contains(options.udpRelayMode) ||
        options.udpOverStream && options.udpRelayMode != 'native' ||
        options.heartbeatMillis < 1000 ||
        options.heartbeatMillis > 3600000) {
      throw const NodeException('TUIC 拥塞控制、UDP 中继或心跳间隔无效');
    }
    if (!preservingSecret && !isValidNodeUuid(draft.username)) {
      throw const NodeException('请输入有效的 TUIC UUID');
    }
  } else if (options.congestionControl != 'cubic' ||
      options.udpRelayMode != 'native' ||
      options.udpOverStream ||
      options.zeroRttHandshake ||
      options.heartbeatMillis != 10000 ||
      options.disableSni) {
    throw const NodeException('TUIC 选项与协议不匹配');
  }
  if (draft.protocol == NodeProtocol.vmess) {
    if (!vmessSecurityMethods.contains(options.vmessSecurity) ||
        options.alterId < 0 ||
        options.alterId > 65535) {
      throw const NodeException('VMess 加密方式或 Alter ID 无效');
    }
  } else if (options.vmessSecurity != 'auto' ||
      options.alterId != 0 ||
      options.globalPadding ||
      options.authenticatedLength) {
    throw const NodeException('VMess 选项与协议不匹配');
  }
  if (!udpPacketEncodings.contains(options.packetEncoding) ||
      options.packetEncoding.isNotEmpty &&
          ![NodeProtocol.vmess, NodeProtocol.vless].contains(draft.protocol)) {
    throw const NodeException('UDP 包编码无效或与协议不匹配');
  }
  if (options.transport != 'tcp' &&
      (draft.protocol == NodeProtocol.http ||
          draft.protocol == NodeProtocol.socks5 ||
          draft.protocol == NodeProtocol.shadowsocks)) {
    throw const NodeException('此协议不支持附加传输，请使用原生 TCP');
  }
  if (options.transport == 'ws' && !options.path.startsWith('/')) {
    throw const NodeException('WebSocket 路径应以 / 开头');
  }
  if (options.alpn.length > 8 ||
      options.alpn.any((v) =>
          v.isEmpty || v.length > 64 || v.contains(RegExp(r'[\r\n\x00]')))) {
    throw const NodeException('ALPN 参数无效');
  }
  if (options.realityShortId.isNotEmpty && options.realityPublicKey.isEmpty) {
    throw const NodeException('填写 Reality Short ID 时也需要公钥');
  }
  if (draft.protocol == NodeProtocol.trojan && !draft.tls) {
    throw const NodeException('Trojan 需要启用 TLS');
  }
  if (draft.tls &&
      (draft.protocol == NodeProtocol.socks5 ||
          draft.protocol == NodeProtocol.shadowsocks)) {
    throw const NodeException('此协议不支持通用 TLS 选项');
  }
  if (draft.protocol == NodeProtocol.shadowsocks &&
      !shadowsocksMethods.contains(options.method)) {
    throw const NodeException('暂不支持此 Shadowsocks 加密方式');
  }
  final needsSecret = draft.protocol == NodeProtocol.shadowsocks ||
      draft.protocol == NodeProtocol.vless ||
      draft.protocol == NodeProtocol.vmess ||
      draft.protocol == NodeProtocol.trojan ||
      draft.protocol == NodeProtocol.hysteria2;
  if (needsSecret && !preservingSecret && draft.password.isEmpty) {
    throw const NodeException('请填写协议密码或 UUID');
  }
  if ([NodeProtocol.vless, NodeProtocol.vmess].contains(draft.protocol) &&
      !preservingSecret &&
      !isValidNodeUuid(draft.password)) {
    throw NodeException('请输入有效的 ${draft.protocol.label} UUID');
  }
  if (draft.protocol == NodeProtocol.shadowsocks &&
      options.method.startsWith('2022-') &&
      !preservingSecret) {
    final length = options.method == '2022-blake3-aes-128-gcm' ? 16 : 32;
    try {
      if (draft.password
          .split(':')
          .any((part) => base64.decode(part).length != length)) {
        throw const FormatException();
      }
    } on FormatException {
      throw const NodeException('此 Shadowsocks 2022 密钥格式或长度无效');
    }
  }
  if (options.flow.isNotEmpty &&
      (draft.protocol != NodeProtocol.vless ||
          !draft.tls ||
          options.flow != 'xtls-rprx-vision' ||
          options.transport != 'tcp')) {
    throw const NodeException('Vision 仅用于 VLESS + TLS 的原生 TCP 连接');
  }
  if (options.realityPublicKey.isNotEmpty) {
    if (draft.protocol != NodeProtocol.vless ||
        !draft.tls ||
        options.fingerprint.isEmpty) {
      throw const NodeException('Reality 需要 VLESS、TLS 和 TLS 指纹');
    }
    try {
      if (base64Url
              .decode(base64Url.normalize(options.realityPublicKey))
              .length !=
          32) {
        throw const FormatException();
      }
    } on FormatException {
      throw const NodeException('Reality 公钥格式无效');
    }
    if (!RegExp(r'^(?:[0-9a-fA-F]{2}){0,8}$')
        .hasMatch(options.realityShortId)) {
      throw const NodeException('Reality Short ID 应为最多 16 位十六进制字符');
    }
  }
}
