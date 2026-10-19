// Isolated visual-test data. Never imported by the production entrypoint.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rainlink/application/connection/session_controller.dart';
import 'package:rainlink/application/connection/connection_providers.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/application/groups/group_providers.dart';
import 'package:rainlink/application/nodes/node_providers.dart';
import 'package:rainlink/application/preferences/theme_controller.dart';
import 'package:rainlink/domain/connection/connection_models.dart';
import 'package:rainlink/domain/connection/traffic_repository.dart';
import 'package:rainlink/domain/connection/traffic_history.dart';
import 'package:rainlink/domain/core/core_status.dart';
import 'package:rainlink/domain/core/session_gateway.dart';
import 'package:rainlink/domain/groups/node_group.dart';
import 'package:rainlink/domain/nodes/proxy_node.dart';
import 'package:rainlink/domain/preferences/app_preferences.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';

import 'memory_preferences.dart';

const visualNodes = [
  ProxyNode(
      id: 'visual-jp',
      name: '🇯🇵东京 · 樱花',
      protocol: NodeProtocol.vless,
      server: 'jp.example.test',
      port: 443,
      groupId: 'visual-main'),
  ProxyNode(
      id: 'visual-sg',
      name: '🇸🇬新加坡 · 滨海湾',
      protocol: NodeProtocol.trojan,
      server: 'sg.example.test',
      port: 443,
      groupId: 'visual-main'),
  ProxyNode(
      id: 'visual-us',
      name: '🇺🇸洛杉矶 · 西海岸',
      protocol: NodeProtocol.shadowsocks,
      server: 'us.example.test',
      port: 443,
      groupId: 'visual-main'),
  ProxyNode(
      id: 'visual-http',
      name: '开发测试 HTTP',
      protocol: NodeProtocol.http,
      server: 'local.example.test',
      port: 8080),
];

class _VisualSession extends SessionController {
  _VisualSession(String ip, {bool mobileTunnel = false})
      : super(const UnavailableCoreGateway('视觉测试'), onMode: (_) {}) {
    final now = DateTime.now();
    state = SessionView(
      phase: ConnectionPhase.connected, systemProxy: !mobileTunnel,
      tun: mobileTunnel,
      active: const ActiveConnectionSnapshot(
          sessionId: 'visual',
          target:
              ProxyTarget(id: 'visual-jp', name: '🇯🇵东京 · 樱花', revision: 1),
          mode: ProxyMode.rule,
          configRevision: 'visual'),
      // Documentation IP; fixture screenshots are identified in the report.
      telemetry: SessionTelemetry(
          ip: ip,
          country: 'Japan',
          countryCode: 'jp',
          latency: 24,
          download: 13421772,
          upload: 1468006),
      latencies: const [
        24,
        26,
        25,
        27,
        24,
        28,
        25,
        26,
        24,
        25,
        27,
        24,
        26,
        25,
        24
      ],
      speeds: [
        for (var i = 0; i < 30; i++)
          TrafficRateSample(
            at: now.subtract(Duration(seconds: (29 - i) * 2)),
            download: (4 + i % 7) * 1024 * 1024,
            upload: (1 + i % 3) * 512 * 1024,
          )
      ],
    );
  }
}

List<Override> visualOverrides(
    {AppTheme theme = AppTheme.dark,
    List<ProxyNode> nodes = visualNodes,
    bool connected = true,
    bool mobileTunnel = false,
    String ip = '203.0.113.24'}) {
  final now = DateTime.now();
  final days = [
    for (var i = 5; i >= 0; i--)
      TrafficDay(
          day: DateTime(now.year, now.month, now.day - i),
          upload: 587202560,
          download: 8439610736 - i * 1073741824)
  ];
  final bucketCount = (now.hour * 60 + now.minute) ~/ trafficBucketMinutes + 1;
  return [
    preferencesRepositoryProvider.overrideWithValue(MemoryPreferences()),
    initialThemeProvider.overrideWithValue(theme),
    coreGatewayProvider.overrideWithValue(const UnavailableCoreGateway('视觉测试')),
    requiredTunnelProvider.overrideWithValue(mobileTunnel),
    coreStatusProvider.overrideWith((ref) async => CoreStatus(
        hostAvailable: true,
        message: 'sing-box 1.12.25 · 核心就绪',
        coreVersion: '1.12.25',
        capabilities: CoreCapabilities(
            connect: true,
            systemProxy: !mobileTunnel,
            tun: mobileTunnel,
            requiresTun: mobileTunnel))),
    nodesProvider.overrideWith((ref) => Stream.value(nodes)),
    selectedNodeIdProvider.overrideWith((ref) => Stream.value('visual-jp')),
    groupsProvider.overrideWith((ref) => Stream.value([
          NodeGroup(
              id: 'visual-main',
              name: '主订阅',
              kind: GroupKind.subscription,
              uploaded: 587202560,
              downloaded: 8439610736,
              total: 107374182400,
              updatedAt: now,
              expiresAt: now.add(const Duration(days: 30))),
        ])),
    sessionControllerProvider.overrideWith((ref) => connected
        ? _VisualSession(ip, mobileTunnel: mobileTunnel)
        : SessionController(const UnavailableCoreGateway('视觉测试'),
            onMode: (_) {})),
    dailyTrafficProvider.overrideWith((ref) => Stream.value(
        const DailyTraffic(upload: 587202560, download: 8439610736))),
    trafficHistoryProvider.overrideWith((ref) => Stream.value(days)),
    trafficArchiveProvider
        .overrideWith((ref, period) => Stream.value(TrafficArchive(
              days: days,
              buckets: [
                for (var i = 0; i < bucketCount; i++)
                  TrafficBucket(
                      day: trafficDayKey(now),
                      slot: i,
                      upload: (1 + i % 3) * 512 * 1024,
                      download: (4 + i % 7) * 1024 * 1024)
              ],
              usage: [
                for (final day in days)
                  TrafficUsage(
                      day: trafficDayKey(day.day),
                      target: const TrafficAttribution(
                          id: 'visual-jp', name: '东京 · 樱花', kind: 'node'),
                      upload: day.upload ~/ 2,
                      download: day.download ~/ 2)
              ],
            ))),
  ];
}
