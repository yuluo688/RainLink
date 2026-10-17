import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../application/nodes/node_latency.dart';
import '../../../../application/nodes/node_providers.dart';
import '../../../../application/nodes/node_probe_controller.dart';
import '../../../../design_system/layout/app_layout.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/theme/rainlink_density.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../domain/nodes/proxy_node.dart';
import '../move_node_dialog.dart';
import '../node_alias_dialog.dart';
import '../node_editor_dialog.dart';
import 'node_identity.dart';

const nodeColumnFlexes = [57, 16, 10, 17];

class NodeRow extends ConsumerStatefulWidget {
  const NodeRow(
      {required this.node,
      required this.selected,
      required this.groupName,
      super.key});
  final ProxyNode node;
  final bool selected;
  final String groupName;
  @override
  ConsumerState<NodeRow> createState() => _NodeRowState();
}

class _NodeRowState extends ConsumerState<NodeRow> {
  bool _busy = false;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text(error is NodeException ? error.message : '节点操作失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(String action) async {
    final node = widget.node;
    switch (action) {
      case 'favorite':
        await _perform(() => ref
            .read(nodeOverridesRepositoryProvider)
            .setFavorite(node.id, !node.favorite));
        return;
      case 'probe':
        await ref.read(nodeProbeProvider.notifier).run([node]);
        return;
      case 'move':
        await _perform(() => moveNodeDialog(context, ref, node));
        return;
      case 'source':
        await showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('订阅节点'),
                    content: Text(
                        '来自「${widget.groupName}」\n原名：${node.sourceName}\n订阅维护连接参数，本地别名、收藏和隐藏在更新后保留。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('知道了'))
                    ]));
        return;
      case 'alias':
        await showNodeAliasDialog(context, node);
        return;
      case 'edit':
        await showNodeEditor(context, node: node);
        return;
      case 'restore':
        await _perform(() => ref
            .read(nodeOverridesRepositoryProvider)
            .setHidden(node.id, false));
        return;
      case 'hide':
      case 'delete':
        final hiding = action == 'hide';
        final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: Text(hiding ? '隐藏节点' : '删除节点'),
                    content: Text(hiding
                        ? '隐藏「${node.name}」？可在分组筛选的「已隐藏」中恢复。当前连接和已有规则、代理链继续可用。'
                        : '删除「${node.name}」？正在使用的连接会保留到断开。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(hiding ? '隐藏' : '删除')),
                    ]));
        if (confirm != true || !mounted) return;
        await _perform(() => hiding
            ? ref.read(nodeOverridesRepositoryProvider).setHidden(node.id, true)
            : ref.read(nodeRepositoryProvider).delete(node.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final desktop = AppLayout.current == AppLayout.desktop;
    final density = RainlinkDensity.of(context);
    final colors = RainlinkColors.of(context);
    final text = Theme.of(context).textTheme;
    final health = ref.watch(nodeLatencyProvider(node));
    final pending = health.pending;
    final latency = health.latency;
    final checkedAt = health.checkedAt;
    final probing =
        ref.watch(nodeProbeProvider.select((state) => state.running));
    final supported = ref.watch(nodeTesterProvider) is! UnavailableNodeTester;
    final favorite = SizedBox(
        width: desktop ? 32 : 44,
        height: desktop ? 32 : 44,
        child: Semantics(
            toggled: node.favorite,
            child: IconButton(
                key: ValueKey('node-favorite-${node.id}'),
                padding: EdgeInsets.zero,
                tooltip: node.favorite ? '取消收藏' : '收藏节点',
                onPressed: _busy
                    ? null
                    : () => _perform(() => ref
                        .read(nodeOverridesRepositoryProvider)
                        .setFavorite(node.id, !node.favorite)),
                icon: RainlinkIcon(RainlinkGlyph.star,
                    size: 17,
                    color:
                        node.favorite ? colors.primary : colors.secondary))));
    final menu = SizedBox(
        width: desktop ? 32 : 44,
        height: desktop ? 32 : 44,
        child: PopupMenuButton<String>(
            key: ValueKey('node-menu-${node.id}'),
            enabled: !_busy,
            tooltip: '节点操作',
            padding: EdgeInsets.zero,
            icon: const RainlinkIcon(RainlinkGlyph.more, size: 18),
            onSelected: _menu,
            itemBuilder: (_) => [
                  PopupMenuItem(
                      value: 'favorite',
                      child: Text(node.favorite ? '取消收藏' : '收藏节点')),
                  if (!node.hidden)
                    PopupMenuItem(
                        value: 'probe',
                        enabled: supported && !probing,
                        child: const Text('测试延迟')),
                  if (node.subscriptionManaged) ...[
                    const PopupMenuItem(value: 'source', child: Text('查看来源')),
                    const PopupMenuItem(value: 'alias', child: Text('本地别名')),
                    PopupMenuItem(
                        value: node.hidden ? 'restore' : 'hide',
                        child: Text(node.hidden ? '恢复显示' : '隐藏节点')),
                  ] else ...[
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (node.groupId == null)
                      const PopupMenuItem(value: 'move', child: Text('移入分组')),
                    const PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ]));
    final latencyWidget = Tooltip(
        message: pending
            ? '正在独立测试，不切换当前连接'
            : health.failed
                ? health.error
                : checkedAt == null
                    ? latency == null
                        ? '尚无独立测速结果'
                        : '当前连接的检测延迟'
                    : '测试于 ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(checkedAt))}',
        child: Text(
            pending
                ? '测速中'
                : health.failed
                    ? '失败'
                    : latency == null
                        ? (desktop ? '未探测' : '未测')
                        : '$latency ms',
            key: ValueKey('node-latency-${node.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(
                color: health.failed && !pending
                    ? colors.error
                    : latency == null
                        ? colors.muted
                        : colors.primary)));
    final selected = SizedBox(
        width: 18,
        child: widget.selected
            ? RainlinkIcon(RainlinkGlyph.check, size: 18, color: colors.primary)
            : null);
    return Material(
        color: widget.selected
            ? colors.primarySurface
            : desktop
                ? Colors.transparent
                : colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(desktop ? 0 : 12),
            side: BorderSide(
                color: widget.selected
                    ? colors.primary
                    : desktop
                        ? Colors.transparent
                        : colors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            key: ValueKey('node-${node.id}'),
            onTap: _busy || node.hidden
                ? null
                : () => _perform(
                    () => ref.read(nodeRepositoryProvider).select(node.id)),
            child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: density.rowHeight),
                child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: desktop ? 16 : 12,
                        vertical: density.nodePadding),
                    child: Row(children: [
                      Expanded(
                          flex: nodeColumnFlexes[0],
                          child: Padding(
                              padding: EdgeInsets.only(right: desktop ? 16 : 0),
                              child: NodeIdentity(
                                  node: node, showProtocol: !desktop))),
                      if (desktop) ...[
                        Expanded(
                            flex: nodeColumnFlexes[1],
                            child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 120),
                                    margin: const EdgeInsets.only(right: 8),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: colors.raised,
                                        borderRadius: BorderRadius.circular(5)),
                                    child: Text(node.protocol.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: text.bodySmall?.copyWith(
                                            color: colors.secondary))))),
                        Expanded(
                            flex: nodeColumnFlexes[2], child: latencyWidget),
                        Expanded(
                            flex: nodeColumnFlexes[3],
                            child: LayoutBuilder(
                                builder: (context, constraints) =>
                                    Row(children: [
                                      if (constraints.maxWidth >= 90) favorite,
                                      menu,
                                      const SizedBox(width: 8),
                                      selected
                                    ]))),
                      ] else ...[
                        const SizedBox(width: 4),
                        SizedBox(width: 45, child: latencyWidget),
                        selected,
                        favorite,
                        menu,
                      ],
                    ])))));
  }
}
