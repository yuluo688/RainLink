import 'package:flutter/material.dart';

import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/theme/rainlink_density.dart';
import 'widgets/overview_cards.dart';

class DesktopOverview extends StatelessWidget {
  const DesktopOverview({super.key});

  static const _minimumFittedWidth = 780.0;
  static const _minimumFittedHeight = 576.0;
  static const _maximumFittedBodySize = 16.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // Narrow screens and enlarged text keep natural scrolling so every
      // control remains reachable without shrinking text or clipping content.
      final fitViewport = constraints.maxWidth >= _minimumFittedWidth &&
          constraints.maxHeight >= _minimumFittedHeight &&
          MediaQuery.textScalerOf(context).scale(14) <= _maximumFittedBodySize;
      return PageFrame(
        title: '概览',
        description: '选择连接目标，管理连接状态与代理模式。',
        scrollable: !fitViewport,
        padding: fitViewport
            ? EdgeInsets.symmetric(
                horizontal: constraints.maxHeight < 740 ? 20 : 36,
                vertical: constraints.maxHeight < 740 ? 16 : 24)
            : null,
        child: fitViewport
            ? const _DesktopOverview()
            : const _ScrollableDesktopOverview(),
      );
    });
  }
}

class _DesktopOverview extends StatelessWidget {
  const _DesktopOverview();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 640;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: compact
                ? RainlinkDensity.of(context).compact
                    ? 112
                    : 120
                : 164,
            child: OverviewConnectionCard(dense: compact),
          ),
          const SizedBox(height: 8),
          OverviewNetworkControlsCard(desktop: true, dense: compact),
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? 64 : 88,
            child: const OverviewOutletCard(),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: compact ? 68 : 86,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child:
                        OverviewMetricCard(label: '今日流量', detail: '等待核心提供统计')),
                SizedBox(width: 8),
                Expanded(
                    child: OverviewMetricCard(label: '下载速度', detail: '上传速度 —')),
                SizedBox(width: 8),
                Expanded(
                    child: OverviewMetricCard(label: '网络质量', detail: '暂无探测结果')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Expanded(
                    flex: 2, child: OverviewLatencyCard(expand: true)),
                const SizedBox(width: 8),
                Expanded(child: OverviewNodeHealthCard(dense: compact)),
              ],
            ),
          ),
        ],
      );
    });
  }
}

class _ScrollableDesktopOverview extends StatelessWidget {
  const _ScrollableDesktopOverview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OverviewConnectionCard(),
        SizedBox(height: 12),
        OverviewNetworkControlsCard(),
        SizedBox(height: 12),
        OverviewOutletCard(),
        SizedBox(height: 12),
        OverviewMetricCard(label: '今日流量', detail: '等待核心提供统计'),
        SizedBox(height: 8),
        OverviewMetricCard(label: '下载速度', detail: '上传速度 —'),
        SizedBox(height: 8),
        OverviewMetricCard(label: '网络质量', detail: '暂无探测结果'),
        SizedBox(height: 12),
        OverviewLatencyCard(),
      ],
    );
  }
}
