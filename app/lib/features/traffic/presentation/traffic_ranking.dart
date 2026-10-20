import 'package:flutter/material.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../domain/connection/traffic_history.dart';

class TrafficRanking extends StatefulWidget {
  const TrafficRanking({
    required this.view,
    required this.loading,
    required this.error,
    super.key,
  });
  final TrafficPeriodView view;
  final bool loading;
  final bool error;
  @override
  State<TrafficRanking> createState() => _TrafficRankingState();
}

class _TrafficRankingState extends State<TrafficRanking> {
  bool _applications = true;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final view = widget.view;
    final ranking = _applications ? view.applicationRanking : view.ranking;
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Tooltip(
                message:
                    '按实际出站和应用分别统计，包含已结束连接。两个排行各自对应总流量，不能相加。历史数据、无法识别或超过容量的部分保留为未归属；中断前未采集的用量无法补录。',
                child: Text('使用排行', style: text.titleMedium),
              ),
              const Spacer(),
              RainlinkSegmentedControl<bool>(
                key: const ValueKey('traffic-ranking-dimension'),
                segments: const [
                  RainlinkSegment(value: false, label: '出站'),
                  RainlinkSegment(value: true, label: '应用'),
                ],
                selected: _applications,
                onChanged: (value) => setState(() => _applications = value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child:
                widget.error || widget.loading || ranking.isEmpty
                    ? Center(
                      child: Text(
                        widget.error
                            ? '流量记录读取失败，请重新打开此页面'
                            : widget.loading
                            ? '正在读取流量记录…'
                            : '暂无流量记录',
                        style: text.bodySmall,
                      ),
                    )
                    : ListView.separated(
                      itemCount: ranking.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = ranking[index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${index + 1}  ${item.target.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  formatBytes(item.total),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (item.total / view.report.total).clamp(
                                0,
                                1,
                              ),
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ],
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
