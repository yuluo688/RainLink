import 'package:flutter/material.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../domain/connection/traffic_repository.dart';

class TrafficSummary extends StatelessWidget {
  const TrafficSummary(
      {required this.report,
      required this.unavailable,
      required this.dense,
      required this.mobile,
      super.key});
  final TrafficReport report;
  final bool unavailable;
  final bool dense;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    String value(int bytes) => unavailable ? '—' : formatBytes(bytes);
    final text = Theme.of(context).textTheme;
    if (mobile) {
      return SurfaceCard(
          color: RainlinkColors.of(context).primarySurface,
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('总流量 · 当前周期', style: text.bodySmall),
            const SizedBox(height: 10),
            Text(value(report.total),
                key: const ValueKey('traffic-total'),
                style: text.headlineMedium),
            const SizedBox(height: 10),
            Text('↓ ${value(report.download)}   ↑ ${value(report.upload)}',
                style: text.bodySmall),
          ]));
    }
    final items = [
      ('总流量', report.total, '当前周期'),
      ('已下载', report.download, '当前周期 · 下载'),
      ('已上传', report.upload, '当前周期 · 上传'),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      Widget card((String, int, String) item) => SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.$1, style: text.bodySmall),
                Text(value(item.$2),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.headlineMedium
                        ?.copyWith(fontSize: 26, height: 1.1)),
                Text(item.$3, style: text.bodySmall),
              ]));
      if (constraints.maxWidth < 560) {
        return Column(children: [
          for (final item in items)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(height: 110, child: card(item)))
        ]);
      }
      return SizedBox(
          height: dense ? 88 : 114,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: card(items[i])),
            ]
          ]));
    });
  }
}
