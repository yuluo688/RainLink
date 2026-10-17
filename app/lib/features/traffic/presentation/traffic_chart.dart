import 'package:flutter/material.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/widgets/rainlink_line_chart.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../domain/connection/traffic_history.dart';
import '../../../domain/connection/traffic_repository.dart';

class TrafficChart extends StatefulWidget {
  const TrafficChart(
      {required this.view, required this.period, required this.now, super.key});
  final TrafficPeriodView view;
  final TrafficPeriod period;
  final DateTime now;
  @override
  State<TrafficChart> createState() => _TrafficChartState();
}

class _TrafficChartState extends State<TrafficChart> {
  int? _selected;
  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final today = widget.period == TrafficPeriod.today;
    final text = Theme.of(context).textTheme;
    final colors = RainlinkColors.of(context);
    const uploadColor = Color(0xFFA4AEFA);
    final count = today
        ? (widget.now.hour * 60 + widget.now.minute) ~/ trafficBucketMinutes + 1
        : view.report.days.length;
    final bySlot = {for (final bucket in view.buckets) bucket.slot: bucket};
    final down = <double?>[], up = <double?>[], labels = <String>[];
    for (var i = 0; i < count; i++) {
      if (today) {
        down.add(bySlot[i]?.download.toDouble());
        up.add(bySlot[i]?.upload.toDouble());
        labels.add(TrafficBucket(day: '', slot: i).label);
      } else {
        final day = view.report.days[i];
        final observed = view.observedDays.contains(trafficDayKey(day.day));
        down.add(observed ? day.download.toDouble() : null);
        up.add(observed ? day.upload.toDouble() : null);
        labels.add('${day.day.month}/${day.day.day}');
      }
    }
    final selected = _selected;
    final index = selected?.clamp(0, count - 1);
    var detail = today ? '15 分钟用量 · 无记录时段留空' : '每日用量';
    if (index != null) {
      final downloaded = down[index], uploaded = up[index];
      detail =
          '${labels[index]}  ${downloaded == null || uploaded == null ? '无记录' : '↓ ${formatBytes(downloaded.round())}   ↑ ${formatBytes(uploaded.round())}'}';
    }
    final maximum = [...down, ...up]
        .whereType<double>()
        .fold<double>(0, (a, b) => a > b ? a : b);
    return SurfaceCard(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('流量趋势', style: text.titleMedium),
            const Spacer(),
            Text(maximum > 0 ? formatBytes(maximum.ceil()) : 'B',
                style: text.bodySmall)
          ]),
          const SizedBox(height: 8),
          Text(detail,
              key: const ValueKey('traffic-chart-detail'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall),
          const SizedBox(height: 8),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            void select(double x) {
              final next = (x / constraints.maxWidth * (count - 1))
                  .round()
                  .clamp(0, count - 1);
              if (next != _selected) setState(() => _selected = next);
            }

            return Semantics(
                label: '流量趋势，$detail',
                child: MouseRegion(
                    onHover: (event) => select(event.localPosition.dx),
                    onExit: (_) => setState(() => _selected = null),
                    child: GestureDetector(
                        key: const ValueKey('traffic-chart-plot'),
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) =>
                            select(details.localPosition.dx),
                        child: RainlinkLineChart(
                            series: [
                              RainlinkChartSeries(down, colors.primary),
                              RainlinkChartSeries(up, uploadColor)
                            ],
                            selectedIndex: index,
                            emptyLabel: view.report.total > 0
                                ? '当前用量没有时段记录'
                                : '连接后开始记录用量'))));
          })),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(labels.first, style: text.bodySmall),
            Text(labels.last, style: text.bodySmall)
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Text('● 下载',
                style: text.bodySmall?.copyWith(color: colors.primary)),
            const SizedBox(width: 16),
            Text('● 上传', style: text.bodySmall?.copyWith(color: uploadColor))
          ]),
        ]));
  }
}
