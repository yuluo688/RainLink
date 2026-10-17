import 'package:flutter/material.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../domain/connection/traffic_history.dart';

class TrafficRanking extends StatelessWidget {
  const TrafficRanking(
      {required this.view,
      required this.loading,
      required this.error,
      super.key});
  final TrafficPeriodView view;
  final bool loading;
  final bool error;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('使用排行', style: text.titleMedium),
            const Spacer(),
            Tooltip(
                message:
                    '持续使用全局或直连模式的会话按目标统计。规则模式、切换模式后的会话及旧版数据记为未归属，不推测应用或节点用量。',
                child: Text('归属说明', style: text.bodySmall)),
          ]),
          const SizedBox(height: 8),
          Expanded(
              child: error || loading || view.ranking.isEmpty
                  ? Center(
                      child: Text(
                          error
                              ? '流量记录读取失败，请重新打开此页面'
                              : loading
                                  ? '正在读取流量记录…'
                                  : '暂无流量记录',
                          style: text.bodySmall))
                  : ListView.separated(
                      itemCount: view.ranking.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = view.ranking[index];
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                Expanded(
                                    child: Text(
                                        '${index + 1}  ${item.target.name}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.bodySmall)),
                                const SizedBox(width: 12),
                                Text(formatBytes(item.total),
                                    style: text.bodySmall)
                              ]),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                  value: (item.total / view.report.total)
                                      .clamp(0, 1),
                                  minHeight: 3,
                                  borderRadius: BorderRadius.circular(2)),
                            ]);
                      })),
        ]));
  }
}
