import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/connection/connection_providers.dart';
import '../../../application/connection/session_controller.dart';
import '../../../application/groups/group_providers.dart';
import '../../../application/chains/chain_providers.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../application/routing/routing_pending.dart';
import '../../../application/routing/routing_providers.dart';
import '../../../application/routing/route_target_info.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/layout/desktop_collection_layout.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../design_system/widgets/telemetry_controls.dart';
import '../../../domain/connection/connection_models.dart';
import '../../../domain/routing/route_rules.dart';
import 'rule_editor_dialog.dart';

enum _Filter { all, domain, ip }

enum _RuleAction { toggle, up, down, delete }

const _columns = [22, 36, 24, 18];

class RulesPage extends ConsumerStatefulWidget {
  const RulesPage({super.key});
  @override
  ConsumerState<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends ConsumerState<RulesPage> {
  var _filter = _Filter.all;

  Future<void> _act(
      _RuleAction action, RouteRuleSet set, RouteRule rule) async {
    if (action == _RuleAction.delete) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('删除规则'),
                  content: Text('删除「${rule.value}」后，请求将继续匹配后面的规则。'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('删除'))
                  ]));
      if (confirmed != true || !mounted) return;
    }
    final controller = ref.read(rulesControllerProvider.notifier);
    await switch (action) {
      _RuleAction.toggle => controller.toggle(set, rule),
      _RuleAction.up => controller.move(set, rule.id, -1),
      _RuleAction.down => controller.move(set, rule.id, 1),
      _RuleAction.delete => controller.remove(set, rule.id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(routeRulesProvider);
    final edit = ref.watch(rulesControllerProvider);
    final rules = state.valueOrNull;
    final groups = ref.watch(groupsProvider).valueOrNull ?? [];
    final nodes = ref.watch(nodesProvider).valueOrNull ?? [];
    final chains = ref.watch(chainsProvider).valueOrNull ?? [];
    final session = ref.watch(sessionControllerProvider);
    final pending = ref.watch(routingPendingProvider);
    final ProxyMode mode =
        session.active?.mode ?? ref.watch<ProxyMode>(proxyModeProvider);
    final modeName = switch (mode) {
      ProxyMode.rule => '规则',
      ProxyMode.global => '全局',
      ProxyMode.direct => '直连'
    };
    final entries = (rules?.rules ?? const <RouteRule>[])
        .where((rule) => switch (_filter) {
              _Filter.all => true,
              _Filter.domain => [
                  RouteRuleKind.domain,
                  RouteRuleKind.domainSuffix
                ].contains(rule.kind),
              _Filter.ip => rule.kind == RouteRuleKind.ipCidr,
            })
        .toList();
    final mobile = AppLayout.current == AppLayout.mobile;
    return PageFrame(
        title: '分流规则',
        description: '代理模式在概览设置，这里管理分流规则与优先级。',
        scrollable: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                RainlinkSegmentedControl(
                    segments: const [
                      RainlinkSegment(value: _Filter.all, label: '全部'),
                      RainlinkSegment(value: _Filter.domain, label: '域名'),
                      RainlinkSegment(value: _Filter.ip, label: 'IP')
                    ],
                    selected: _filter,
                    onChanged: (value) => setState(() => _filter = value)),
                FilledButton.icon(
                    key: const ValueKey('add-rule'),
                    onPressed: rules == null ||
                            edit.saving ||
                            rules.rules.length >= RouteRuleSet.maxRules
                        ? null
                        : () => showRuleEditor(context, rules),
                    icon: const RainlinkIcon(RainlinkGlyph.plus, size: 16),
                    label: const Text('添加规则')),
              ]),
          const SizedBox(height: 14),
          Text(
              '当前为$modeName模式 · 从上到下匹配${mode == ProxyMode.rule ? '' : ' · 自定义规则仅在规则模式生效'}',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 10),
          if (session.active != null && pending)
            const TelemetryNotice(message: '规则或出站已变更，断开重连后应用。'),
          if (state.hasError || edit.error.isNotEmpty)
            TelemetryNotice(
                message: state.hasError ? '${state.error}' : edit.error,
                error: true,
                onRetry: state.hasError
                    ? () => ref.invalidate(routeRulesProvider)
                    : null),
          Flexible(
              child: SizedBox(
                  height: entries.isEmpty
                      ? 200
                      : (entries.length *
                                  (mobile
                                      ? RainlinkDensity.of(context).rowHeight +
                                          28
                                      : RainlinkDensity.of(context).rowHeight) +
                              (mobile
                                  ? 2
                                  : 22 +
                                      RainlinkDensity.of(context)
                                              .tableHeaderPadding *
                                          2)) *
                          (MediaQuery.textScalerOf(context).scale(13) / 13),
                  child: DesktopCollectionLayout(
                      columns:
                          mobile ? const [] : const ['类型', '匹配条件', '出站', '操作'],
                      columnFlexes: _columns,
                      expandContent: true,
                      emptyState: state.isLoading && rules == null
                          ? const Center(child: CircularProgressIndicator())
                          : entries.isEmpty
                              ? const TelemetryEmptyState(
                                  glyph: RainlinkGlyph.rules,
                                  title: '暂无此类规则',
                                  description: '添加规则，或切换筛选查看其他类型。')
                              : ListView.builder(
                                  itemCount: entries.length,
                                  itemBuilder: (context, index) {
                                    final rule = entries[index];
                                    final position =
                                        rules?.rules.indexOf(rule) ?? -1;
                                    return _RuleRow(
                                        rule: rule,
                                        index: position,
                                        total: rules?.rules.length ?? 0,
                                        mobile: mobile,
                                        busy: edit.saving,
                                        target: routeTargetLabel(
                                            rule.target, groups, nodes, chains),
                                        missing: routeTargetMissing(
                                            rule.target, groups, nodes, chains),
                                        onEdit: () {
                                          if (rules != null) {
                                            showRuleEditor(
                                                context, rules, rule);
                                          }
                                        },
                                        onAction: (action) {
                                          if (rules != null) {
                                            _act(action, rules, rule);
                                          }
                                        });
                                  })))),
          const SizedBox(height: 8),
          Text(
              '显示 ${entries.length} 条 / ${rules?.rules.length ?? 0} 条 · 兜底规则固定在最后',
              style: Theme.of(context).textTheme.bodySmall),
        ]));
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow(
      {required this.rule,
      required this.index,
      required this.total,
      required this.mobile,
      required this.busy,
      required this.target,
      required this.missing,
      required this.onEdit,
      required this.onAction});
  final RouteRule rule;
  final int index;
  final int total;
  final bool mobile;
  final bool busy;
  final String target;
  final bool missing;
  final VoidCallback onEdit;
  final ValueChanged<_RuleAction> onAction;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final fallback = rule.kind == RouteRuleKind.match;
    final actions = Row(mainAxisSize: MainAxisSize.min, children: [
      TextButton(onPressed: busy ? null : onEdit, child: const Text('编辑')),
      if (!fallback)
        PopupMenuButton<_RuleAction>(
            key: ValueKey('rule-menu-${rule.id}'),
            tooltip: '规则操作',
            enabled: !busy,
            onSelected: onAction,
            icon: const RainlinkIcon(RainlinkGlyph.more, size: 16),
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: _RuleAction.toggle,
                      child: Text(rule.enabled ? '停用规则' : '启用规则')),
                  PopupMenuItem(
                      value: _RuleAction.up,
                      enabled: index > 0,
                      child: const Text('上移')),
                  PopupMenuItem(
                      value: _RuleAction.down,
                      enabled: index < total - 2,
                      child: const Text('下移')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                      value: _RuleAction.delete, child: Text('删除')),
                ]),
    ]);
    final value = fallback ? '所有其他请求' : rule.value;
    final type = Text('${rule.kind.wireName}${rule.enabled ? '' : ' · 已停用'}',
        maxLines: mobile ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: rule.enabled ? colors.text : colors.muted,
            fontSize: mobile ? 11 : 12));
    final match = Tooltip(
        message: value,
        child: Text(value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: rule.enabled ? colors.secondary : colors.muted)));
    final outbound = Tooltip(
        message: target,
        child: Text(target,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                TextStyle(color: missing ? colors.error : colors.secondary)));
    return Container(
        key: ValueKey('rule-${rule.id}'),
        constraints:
            BoxConstraints(minHeight: RainlinkDensity.of(context).rowHeight),
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: RainlinkDensity.of(context).rowPadding),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.border))),
        child: mobile
            ? Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      match,
                      const SizedBox(height: 4),
                      type,
                      const SizedBox(height: 4),
                      outbound
                    ])),
                actions
              ])
            : Row(children: [
                Expanded(flex: _columns[0], child: type),
                Expanded(
                    flex: _columns[1],
                    child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: match)),
                Expanded(
                    flex: _columns[2],
                    child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: outbound)),
                Expanded(
                    flex: _columns[3],
                    child:
                        Align(alignment: Alignment.centerLeft, child: actions)),
              ]));
  }
}
