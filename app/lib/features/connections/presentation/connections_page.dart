import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/connection/traffic_format.dart';
import '../../../application/telemetry/connections_controller.dart';
import '../../../design_system/layout/desktop_collection_layout.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../design_system/widgets/telemetry_controls.dart';
import '../../../domain/core/core_telemetry.dart';
import '../../../domain/export/data_export.dart';
import '../../../platform/export/file_data_export_service.dart';

const _columns = [30, 16, 21, 10, 13, 10];

enum _ConnectionFilter { all, proxy, direct }

class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});
  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  var _filter = _ConnectionFilter.all;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(connectionsControllerProvider.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  Future<void> _export(
      ConnectionsSnapshot snapshot, List<CoreConnection> entries) async {
    setState(() => _exporting = true);
    try {
      final path = await ref.read(dataExportServiceProvider).save(
          suggestedName:
              'RainLink-连接-${DateTime.now().millisecondsSinceEpoch}.csv',
          content: connectionsCsv(snapshot, entries));
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出 ${entries.length} 条连接')));
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导出失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _closeAll() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('关闭全部连接'),
                content: const Text('将关闭当前会话的所有网络请求。应用可能会自动重新建立连接。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('关闭全部'))
                ]));
    if (confirmed == true && mounted) {
      await ref.read(connectionsControllerProvider.notifier).closeConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(connectionsControllerProvider);
    final controller = ref.read(connectionsControllerProvider.notifier);
    final snapshot = view.snapshot;
    final entries = (snapshot?.entries ?? const <CoreConnection>[])
        .where((entry) =>
            entry.matches(_search.text) &&
            switch (_filter) {
              _ConnectionFilter.all => true,
              _ConnectionFilter.proxy => !entry.direct,
              _ConnectionFilter.direct => entry.direct,
            })
        .toList();
    final toolbar = TelemetryToolbar(
        search: TelemetrySearchField(
            controller: _search,
            label: '连接筛选',
            hint: '搜索域名、进程或规则',
            onChanged: (_) => setState(() {})),
        controls: [
          RainlinkSegmentedControl(
              segments: const [
                RainlinkSegment(value: _ConnectionFilter.all, label: '全部'),
                RainlinkSegment(value: _ConnectionFilter.proxy, label: '代理'),
                RainlinkSegment(value: _ConnectionFilter.direct, label: '直连')
              ],
              selected: _filter,
              onChanged: (value) => setState(() => _filter = value)),
          OutlinedButton(
              onPressed: controller.togglePaused,
              child: Text(view.paused ? '继续刷新' : '暂停刷新')),
          OutlinedButton.icon(
              onPressed:
                  snapshot == null || snapshot.entries.isEmpty || view.closing
                      ? null
                      : _closeAll,
              icon: const RainlinkIcon(RainlinkGlyph.close, size: 16),
              label: const Text('关闭全部')),
          OutlinedButton.icon(
              onPressed: snapshot == null || entries.isEmpty || _exporting
                  ? null
                  : () => _export(snapshot, entries),
              icon: const RainlinkIcon(RainlinkGlyph.download, size: 16),
              label: Text(_exporting ? '导出中…' : '导出')),
        ]);
    final mobile = AppLayout.current == AppLayout.mobile;
    final collection = DesktopCollectionLayout(
      columns:
          mobile ? const [] : const ['目标地址', '进程', '匹配规则', '出站', '流量', '操作'],
      columnFlexes: _columns,
      expandContent: true,
      emptyState: view.loading
          ? const Center(child: CircularProgressIndicator())
          : entries.isEmpty
              ? TelemetryEmptyState(
                  glyph: RainlinkGlyph.connections,
                  title: snapshot == null ? '尚未连接' : '暂无匹配连接',
                  description: snapshot == null
                      ? '在概览开始连接后，这里会显示实际网络请求。'
                      : '尝试调整筛选，或等待应用发起新请求。')
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) => _ConnectionRow(
                      entry: entries[index],
                      at: snapshot?.at ?? DateTime.now(),
                      busy: view.closing,
                      onClose: () =>
                          controller.closeConnection(entries[index].id))),
    );
    return PageFrame(
        title: '连接',
        description: '看清每一条连接的去向。',
        scrollable: mobile,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ConnectionMetrics(snapshot: snapshot),
          const SizedBox(height: 12),
          toolbar,
          const SizedBox(height: 12),
          if (view.error.isNotEmpty)
            TelemetryNotice(
                message: view.error, error: true, onRetry: controller.refresh),
          if (view.paused)
            TelemetryNotice(
                message:
                    '已暂停视图 · 网络继续运行${snapshot == null ? '' : ' · ${telemetryTime(snapshot.at)} 的快照'}'),
          if (mobile)
            SizedBox(
                height: (MediaQuery.sizeOf(context).height / 2).clamp(240, 480),
                child: collection)
          else
            Expanded(child: collection),
          const SizedBox(height: 8),
          Text(
              '显示 ${entries.length} 条${snapshot == null ? '' : ' / ${snapshot.entries.length} 条'} · 进程无法识别时显示未知',
              style: Theme.of(context).textTheme.bodySmall),
        ]));
  }
}

class _ConnectionMetrics extends StatelessWidget {
  const _ConnectionMetrics({required this.snapshot});
  final ConnectionsSnapshot? snapshot;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 1000;
        final metrics = [
          (
            '活跃连接',
            snapshot == null ? '—' : '${snapshot?.entries.length}',
            '每秒刷新'
          ),
          (
            '代理 / 直连',
            snapshot == null
                ? '— / —'
                : '${snapshot?.proxyCount} / ${snapshot?.directCount}',
            '当前活跃连接'
          ),
          (
            '累计传输',
            snapshot == null
                ? '—'
                : formatBytes((snapshot?.uploadTotal ?? 0) +
                    (snapshot?.downloadTotal ?? 0)),
            '本次会话'
          ),
        ];
        return Row(children: [
          for (var index = 0; index < metrics.length; index++) ...[
            if (index > 0) const SizedBox(width: 12),
            Expanded(
                child: SurfaceCard(
                    padding: EdgeInsets.all(compact ? 14 : 16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(metrics[index].$1,
                              style: Theme.of(context).textTheme.bodySmall),
                          const SizedBox(height: 8),
                          FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(metrics[index].$2,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontSize: compact ? 24 : 28))),
                          if (!compact) ...[
                            const SizedBox(height: 6),
                            Text(metrics[index].$3,
                                style: Theme.of(context).textTheme.bodySmall)
                          ],
                        ]))),
          ]
        ]);
      });
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow(
      {required this.entry,
      required this.at,
      required this.busy,
      required this.onClose});
  final CoreConnection entry;
  final DateTime at;
  final bool busy;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final cells = <Widget>[
      Tooltip(
          message:
              '${entry.network.toUpperCase()} · ${entry.destination}\n持续 ${telemetryDuration(at.difference(entry.startedAt))}',
          child: Text(entry.destination,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      Text(entry.process.isEmpty ? '未知' : entry.process,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      Tooltip(
          message: entry.rule,
          child: Text(entry.rule.isEmpty ? '默认规则' : entry.rule,
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      Text(entry.direct ? '直连' : '代理',
          style: TextStyle(
              color: entry.direct ? colors.secondary : colors.primary)),
      Tooltip(
          message:
              '上传 ${formatBytes(entry.upload)} / 下载 ${formatBytes(entry.download)}',
          child: Text(formatBytes(entry.upload + entry.download),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
      Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
              tooltip: '关闭 ${entry.destination}',
              onPressed: busy ? null : onClose,
              icon: const RainlinkIcon(RainlinkGlyph.close, size: 16))),
    ];
    return Container(
        constraints:
            BoxConstraints(minHeight: RainlinkDensity.of(context).rowHeight),
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: RainlinkDensity.of(context).rowPadding),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border))),
        child: DefaultTextStyle(
            style: Theme.of(context).textTheme.bodyMedium ?? const TextStyle(),
            child: AppLayout.current == AppLayout.mobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        Row(children: [Expanded(child: cells[0]), cells[5]]),
                        Wrap(spacing: 12, runSpacing: 4, children: [
                          cells[1],
                          cells[3],
                          cells[4],
                        ]),
                        const SizedBox(height: 4),
                        cells[2],
                      ])
                : Row(children: [
                    for (var index = 0; index < cells.length; index++)
                      Expanded(
                          flex: _columns[index],
                          child: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: cells[index]))
                  ])));
  }
}
