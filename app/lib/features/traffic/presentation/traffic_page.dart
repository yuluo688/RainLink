import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/connection/session_controller.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../domain/connection/traffic_history.dart';
import '../../../domain/connection/traffic_repository.dart';
import '../../../domain/export/data_export.dart';
import '../../../platform/export/file_data_export_service.dart';
import 'traffic_chart.dart';
import 'traffic_summary.dart';
import 'traffic_ranking.dart';

class TrafficPage extends ConsumerStatefulWidget {
  const TrafficPage({super.key});
  @override
  ConsumerState<TrafficPage> createState() => _TrafficPageState();
}

class _TrafficPageState extends ConsumerState<TrafficPage> {
  TrafficPeriod _period = TrafficPeriod.today;
  bool _exporting = false;

  Future<void> _export(TrafficPeriodView view) async {
    setState(() => _exporting = true);
    try {
      final path = await ref
          .read(dataExportServiceProvider)
          .save(
            suggestedName:
                'RainLink-流量-${trafficDayKey(view.report.days.first.day)}-${trafficDayKey(view.report.days.last.day)}.csv',
            content: trafficCsv(view),
          );
      if (mounted && path != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已导出当前周期流量')));
      }
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('导出失败，请检查保存位置和磁盘空间')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(trafficArchiveProvider(_period));
    // This stream advances the calendar even while disconnected at midnight.
    ref.watch(dailyTrafficProvider);
    final now = DateTime.now();
    final archive = history.valueOrNull ?? const TrafficArchive();
    final view = archive.forPeriod(_period, now);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = AppLayout.current == AppLayout.desktop;
        final fitted =
            desktop &&
            constraints.maxWidth >= 780 &&
            constraints.maxHeight >= 576 &&
            MediaQuery.textScalerOf(context).scale(14) <= 16;
        final compact = constraints.maxHeight < 740;
        final chart = TrafficChart(
          key: ValueKey(_period),
          view: view,
          period: _period,
          now: now,
        );
        final ranking = TrafficRanking(
          view: view,
          loading: history.isLoading,
          error: history.hasError,
        );
        final exporting = OutlinedButton.icon(
          key: const ValueKey('export-traffic'),
          onPressed:
              _exporting || !history.hasValue || archive.days.isEmpty
                  ? null
                  : () => _export(view),
          icon: const RainlinkIcon(RainlinkGlyph.download, size: 16),
          label: Text(
            _exporting
                ? '导出中…'
                : desktop
                ? '导出 CSV'
                : '导出',
          ),
        );
        return PageFrame(
          title: '流量',
          description: '看清流量，掌握用量。',
          scrollable: !fitted,
          padding:
              fitted && compact
                  ? const EdgeInsets.symmetric(horizontal: 20, vertical: 16)
                  : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RainlinkSegmentedControl<TrafficPeriod>(
                        segments: const [
                          RainlinkSegment(
                            value: TrafficPeriod.today,
                            label: '今日',
                          ),
                          RainlinkSegment(
                            value: TrafficPeriod.week,
                            label: '本周',
                          ),
                          RainlinkSegment(
                            value: TrafficPeriod.month,
                            label: '本月',
                          ),
                        ],
                        selected: _period,
                        onChanged: (value) => setState(() => _period = value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (desktop)
                    exporting
                  else
                    Tooltip(
                      message: '导出当前周期 CSV',
                      child: IconButton(
                        key: const ValueKey('export-traffic-mobile'),
                        onPressed:
                            _exporting ||
                                    !history.hasValue ||
                                    archive.days.isEmpty
                                ? null
                                : () => _export(view),
                        icon: const RainlinkIcon(
                          RainlinkGlyph.download,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TrafficSummary(
                report: view.report,
                unavailable: !history.hasValue,
                dense: compact,
                mobile: !desktop,
              ),
              const SizedBox(height: 12),
              if (fitted && compact)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: chart),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: ranking),
                    ],
                  ),
                )
              else if (fitted) ...[
                Expanded(flex: 3, child: chart),
                const SizedBox(height: 12),
                Expanded(flex: 2, child: ranking),
              ] else ...[
                SizedBox(height: 250, child: chart),
                const SizedBox(height: 12),
                SizedBox(height: 230, child: ranking),
              ],
            ],
          ),
        );
      },
    );
  }
}
