import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/platform/qr/qr_camera_session.dart';

const qrUuid = 'a6db2f50-361a-4294-8bce-1df5f356764f';
final qrNodeLinks = <NodeProtocol, String>{
  NodeProtocol.http:
      'https://fixture-user:p%40ss%3Aword@proxy.example.test:8443?'
      'sni=edge.example.test&alpn=h2&fp=chrome#HTTP',
  NodeProtocol.socks5:
      'socks5://fixture-user:p%40ss@proxy.example.test:1080#SOCKS',
  NodeProtocol.shadowsocks:
      'ss://${base64Url.encode(utf8.encode('aes-256-gcm:p@ss:word'))}'
      '@proxy.example.test:8388#Shadowsocks',
  NodeProtocol.vless:
      'vless://$qrUuid@proxy.example.test:443?security=reality'
      '&sni=edge.example.test&fp=chrome&sid=01ab&flow=xtls-rprx-vision'
      '&pbk=${base64Url.encode(List.filled(32, 1)).replaceAll('=', '')}#VLESS',
  NodeProtocol.vmess:
      'vmess://${base64Url.encode(utf8.encode(jsonEncode({'v': '2', 'ps': 'VMess', 'add': 'proxy.example.test', 'port': '443', 'id': qrUuid, 'aid': '0', 'net': 'ws', 'type': 'none', 'tls': 'tls', 'path': '/ws', 'host': 'edge.example.test', 'scy': 'chacha20-poly1305', 'fp': 'chrome', 'alpn': 'h2,http/1.1', 'globalPadding': true, 'authenticatedLength': true, 'packetEncoding': 'xudp'})))}',
  NodeProtocol.trojan:
      'trojan://p%40ss@proxy.example.test:443?'
      'sni=edge.example.test&type=grpc&serviceName=rainlink#Trojan',
  NodeProtocol.hysteria2:
      'hy2://p%40ss@proxy.example.test:8443?'
      'sni=edge.example.test&obfs=salamander&obfs-password=m%2Bix&'
      'mport=20000-30000,8443&hop-interval=30&pinSHA256=${List.filled(32, 'ab').join()}#Hysteria2',
  NodeProtocol.tuic:
      'tuic://$qrUuid:p%40ss%3Aword@proxy.example.test:8443?'
      'sni=edge.example.test&alpn=h3&congestion_control=bbr&udp_over_stream=1&'
      'heartbeat=1500ms&reduce_rtt=true&pinSHA256=${List.filled(32, 'ab').join()}#TUIC',
};

class FixtureQrCamera extends QrCameraSession {
  FixtureQrCamera({this.initialStatus = QrCameraStatus.scanning});
  final QrCameraStatus initialStatus;
  final _codes = StreamController<List<String>>.broadcast();
  final activity = <bool>[];
  int closes = 0;
  int retries = 0;
  bool closed = false;
  Future<void>? closeGate;
  @override
  Stream<List<String>> get codes => _codes.stream;
  void capture(List<String> codes) => _codes.add(codes);
  @override
  Widget buildPreview() => const ColoredBox(color: Color(0xFF202326));
  @override
  Future<void> setActive(bool active) async {
    activity.add(active);
    value = active ? initialStatus : QrCameraStatus.paused;
  }

  @override
  Future<void> retry() async {
    retries++;
    value = QrCameraStatus.scanning;
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    closes++;
    await closeGate;
    await _codes.close();
    super.dispose();
  }
}
