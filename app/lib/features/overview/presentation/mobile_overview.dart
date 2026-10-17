import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/connection/session_controller.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/surface_card.dart';
import 'widgets/overview_cards.dart';

class MobileOverview extends StatelessWidget {
  const MobileOverview({super.key});

  @override
  Widget build(BuildContext context) => PageFrame(
        title: 'RainLink',
        description: '概览 · 管理连接与代理模式',
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        showMobileNavigationButton: false,
        actions: [
          IconButton(
              tooltip: '打开设置',
              onPressed: () => context.go('/settings'),
              icon: const RainlinkIcon(RainlinkGlyph.settings, size: 20)),
        ],
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OverviewConnectionCard(dense: true, mobile: true),
            SizedBox(height: 12),
            OverviewNetworkControlsCard(mobile: true),
            SizedBox(height: 12),
            OverviewOutletCard(mobile: true),
            SizedBox(height: 12),
            _MobileTrafficSummary(),
          ],
        ),
      );
}

class _MobileTrafficSummary extends ConsumerWidget {
  const _MobileTrafficSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final telemetry = ref.watch(
        sessionControllerProvider.select((session) => session.telemetry));
    final traffic = ref.watch(dailyTrafficProvider).valueOrNull;
    final text = Theme.of(context).textTheme;
    Widget speed(String label, int? bytes) =>
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final formatted = bytes == null ? null : formatBytes(bytes);
          final parts = formatted?.split(' ');
          return SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(label, style: text.bodySmall),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(parts?.first ?? '—',
                                  textAlign: TextAlign.right,
                                  style: text.titleLarge
                                      ?.copyWith(fontSize: 20, height: 1.2))),
                        ]),
                    const SizedBox(height: 2),
                    Text(parts == null ? '等待数据' : '${parts.last}/s',
                        style: text.bodySmall),
                  ]));
        }));
    return Column(
        key: const ValueKey('mobile-traffic-summary'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            speed('下载', telemetry?.download),
            const SizedBox(width: 8),
            speed('上传', telemetry?.upload),
          ]),
          const SizedBox(height: 12),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('今日流量', style: text.bodyMedium),
                Text(traffic == null ? '—' : formatBytes(traffic.total),
                    style:
                        text.titleLarge?.copyWith(fontSize: 20, height: 1.2)),
              ]),
          const SizedBox(height: 4),
          Text(
              traffic == null
                  ? '等待流量统计'
                  : '↓ ${formatBytes(traffic.download)}　↑ ${formatBytes(traffic.upload)}',
              style: text.bodySmall),
        ]);
  }
}
