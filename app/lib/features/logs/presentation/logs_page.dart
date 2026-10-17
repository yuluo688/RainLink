import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/telemetry/core_log_collector.dart';
import '../../../design_system/layout/desktop_collection_layout.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../design_system/widgets/telemetry_controls.dart';
import '../../../domain/core/core_telemetry.dart';
import '../../../domain/export/data_export.dart';
import '../../../platform/export/file_data_export_service.dart';

const _columns = [17, 10, 73];

class LogsPage extends ConsumerStatefulWidget {
  const LogsPage({super.key});
  @override
  ConsumerState<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends ConsumerState<LogsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  CoreLogLevel? _level;
  List<CoreLogEntry>? _frozen;
  bool _exporting = false;
  bool _clearing = false;
  bool _follow = true;
  String? _lastEntry;
  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('清空日志'),
                content: const Text('删除本机已保存的全部日志？此操作不会中断网络连接。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清空'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ref.read(coreLogCollectorProvider.notifier).clear();
      if (mounted) {
        setState(() {
          if (_frozen != null) _frozen = [];
        });
      }
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('清空失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _export(List<CoreLogEntry> entries) async {
    setState(() => _exporting = true);
    try {
      final path = await ref.read(dataExportServiceProvider).save(
          suggestedName:
              'RainLink-日志-${DateTime.now().millisecondsSinceEpoch}.csv',
          content: logsCsv(entries));
      if (mounted && path != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已导出 ${entries.length} 条日志')));
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

  void _scrollToLatest() {
    if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(coreLogsProvider);
    final collection = ref.watch(coreLogCollectorProvider);
    final all = _frozen ?? logs.valueOrNull ?? <CoreLogEntry>[];
    final visible = all
        .where((entry) =>
            (_level == null || entry.level == _level) &&
            entry.matches(_search.text))
        .toList();
    ref.listen(coreLogsProvider, (previous, next) {
      final last = next.valueOrNull?.lastOrNull?.id;
      if (last != _lastEntry && _frozen == null && _follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scrollToLatest();
        });
      }
      _lastEntry = last;
    });
    final toolbar = TelemetryToolbar(
        search: TelemetrySearchField(
            controller: _search,
            label: '搜索日志',
            hint: '搜索事件或关键词',
            onChanged: (_) => setState(() {})),
        controls: [
          RainlinkSegmentedControl<CoreLogLevel?>(
              segments: const [
                RainlinkSegment(value: null, label: '全部'),
                RainlinkSegment(value: CoreLogLevel.info, label: '信息'),
                RainlinkSegment(value: CoreLogLevel.warning, label: '警告'),
                RainlinkSegment(value: CoreLogLevel.error, label: '错误')
              ],
              selected: _level,
              onChanged: (value) => setState(() => _level = value)),
          OutlinedButton(
              onPressed: () => setState(() {
                    _frozen = _frozen == null
                        ? List.of(logs.valueOrNull ?? [])
                        : null;
                  }),
              child: Text(_frozen == null ? '暂停' : '继续')),
          OutlinedButton(
              onPressed: all.isEmpty || _clearing ? null : _clear,
              child: Text(_clearing ? '清空中…' : '清空')),
          OutlinedButton.icon(
              onPressed:
                  visible.isEmpty || _exporting ? null : () => _export(visible),
              icon: const RainlinkIcon(RainlinkGlyph.download, size: 16),
              label: Text(_exporting ? '导出中…' : '导出')),
        ]);
    final mobile = AppLayout.current == AppLayout.mobile;
    final logList = DesktopCollectionLayout(
        columns: mobile ? const [] : const ['时间', '级别', '事件'],
        columnFlexes: _columns,
        expandContent: true,
        emptyState: logs.isLoading
            ? const Center(child: CircularProgressIndicator())
            : visible.isEmpty
                ? TelemetryEmptyState(
                    glyph: RainlinkGlyph.terminal,
                    title: all.isEmpty ? '暂无日志' : '没有匹配的日志',
                    description: all.isEmpty ? '连接后显示真实核心事件。' : '试试其他关键词或日志级别。')
                : NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      final following = _scroll.position.extentAfter < 40;
                      if (following != _follow) {
                        setState(() => _follow = following);
                      }
                      return false;
                    },
                    child: SelectionArea(
                        child: ListView.builder(
                            controller: _scroll,
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _LogRow(entry: visible[index])))));
    return PageFrame(
        title: '日志',
        description: '安静清晰的控制台，呈现关键细节。',
        scrollable: mobile,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          toolbar,
          const SizedBox(height: 12),
          if (logs.hasError || collection.error.isNotEmpty)
            TelemetryNotice(
                message: logs.hasError ? '无法读取已保存日志，请重试' : collection.error,
                error: true,
                onRetry: () {
                  ref.invalidate(coreLogsProvider);
                  ref.read(coreLogCollectorProvider.notifier).collect();
                }),
          if (collection.dropped)
            const TelemetryNotice(message: '采集间隔内日志超过核心缓存容量，部分较早记录未保存。'),
          if (_frozen != null)
            const TelemetryNotice(message: '已暂停视图 · 核心日志仍在采集'),
          if (mobile)
            SizedBox(
                height: (MediaQuery.sizeOf(context).height / 2).clamp(240, 480),
                child: logList)
          else
            Expanded(child: logList),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text('日志保留 7 天 · 最多 5,000 条 · 自动隐藏认证信息',
                    style: Theme.of(context).textTheme.bodySmall)),
            TextButton(
                onPressed: () {
                  setState(() => _follow = true);
                  _scrollToLatest();
                },
                child: const Text('滚动至最新'))
          ]),
        ]));
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});
  final CoreLogEntry entry;
  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final levelColor = switch (entry.level) {
      CoreLogLevel.error => colors.error,
      CoreLogLevel.warning => colors.warning,
      _ => colors.secondary
    };
    final time =
        '${telemetryTime(entry.at)}.${entry.at.millisecond.toString().padLeft(3, '0')}';
    final cells = <Widget>[
      Tooltip(
          message: entry.at.toIso8601String(),
          child: Text(time,
              maxLines: 1,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontFamily: 'Roboto Mono'))),
      Text(entry.level.label, style: TextStyle(color: levelColor)),
      Tooltip(
          message:
              '${entry.source == 'core' ? '网络核心' : '宿主'} · ${entry.message}',
          child: Text(entry.message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium)),
    ];
    return Container(
        constraints:
            BoxConstraints(minHeight: RainlinkDensity.of(context).rowHeight),
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: RainlinkDensity.of(context).logPadding),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border))),
        child: AppLayout.current == AppLayout.mobile
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [Expanded(child: cells[0]), cells[1]]),
                const SizedBox(height: 6),
                cells[2],
              ])
            : Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                for (var index = 0; index < cells.length; index++)
                  Expanded(
                      flex: _columns[index],
                      child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: cells[index]))
              ]));
  }
}
