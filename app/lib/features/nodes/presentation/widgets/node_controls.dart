import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../application/groups/group_providers.dart';
import '../../../../application/nodes/node_providers.dart';
import '../../../../application/nodes/node_probe_controller.dart';
import '../../../../domain/nodes/proxy_node.dart';

import '../../../../design_system/widgets/rainlink_icon.dart';

class NodeSearchField extends StatelessWidget {
  const NodeSearchField(
      {required this.controller,
      required this.onSearchChanged,
      required this.onClear,
      super.key});

  final TextEditingController controller;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TextField(
        key: const ValueKey('node-search'),
        controller: controller,
        onChanged: onSearchChanged,
        style: Theme.of(context).textTheme.labelLarge,
        decoration: InputDecoration(
          hintText: '搜索名称、协议或地区',
          prefixIcon: const Padding(
              padding: EdgeInsets.all(12),
              child: RainlinkIcon(RainlinkGlyph.search, size: 18)),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 42, minHeight: 42),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  onPressed: onClear,
                  icon: const RainlinkIcon(RainlinkGlyph.close, size: 16)),
        ),
      );
}

class NodeTools extends ConsumerWidget {
  const NodeTools({required this.nodes, super.key});
  final List<ProxyNode> nodes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final probe = ref.watch(nodeProbeProvider);
    final supported = ref.watch(nodeTesterProvider) is! UnavailableNodeTester;
    final controller = ref.read(nodeProbeProvider.notifier);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton.icon(
        onPressed: () => context.go('/chain'),
        icon: const RainlinkIcon(RainlinkGlyph.link, size: 18),
        label: const Text('代理链'),
      ),
      const SizedBox(width: 8),
      Tooltip(
          message:
              !supported ? '当前平台的节点测速尚未接入' : '测试当前筛选的节点到 HTTPS 测试站的延迟，不切换连接',
          child: OutlinedButton.icon(
              key: const ValueKey('probe-visible-nodes'),
              onPressed: probe.cancelling
                  ? null
                  : probe.running
                      ? controller.cancel
                      : !supported || nodes.every((node) => node.hidden)
                          ? null
                          : () => controller.run(nodes),
              icon: RainlinkIcon(
                  probe.running ? RainlinkGlyph.close : RainlinkGlyph.speed,
                  size: 18),
              label: Text(probe.running
                  ? '取消 ${probe.completed}/${probe.total}'
                  : '测速'))),
    ]);
  }
}

class NodeGroupFilter extends ConsumerWidget {
  const NodeGroupFilter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).valueOrNull ?? [];
    final filter = ref.watch(nodeGroupFilterProvider);
    final listFilter = ref.watch(nodeListFilterProvider);
    final groupName = filter == ''
        ? '未分组'
        : groups.where((g) => g.id == filter).firstOrNull?.name ?? '全部分组';
    final name = switch (listFilter) {
      NodeListFilter.all => groupName,
      NodeListFilter.favorites => '$groupName · 收藏',
      NodeListFilter.hidden => '$groupName · 已隐藏',
    };
    return PopupMenuButton<String>(
        key: const ValueKey('node-group-filter'),
        tooltip: '筛选分组',
        onSelected: (id) {
          if (id.startsWith('@view:')) {
            ref.read(nodeListFilterProvider.notifier).state =
                NodeListFilter.values.byName(id.substring(6));
          } else {
            ref.read(nodeGroupFilterProvider.notifier).state =
                id == '@all' ? null : id;
          }
        },
        itemBuilder: (_) => [
              const PopupMenuItem(value: '@all', child: Text('全部分组')),
              const PopupMenuItem(value: '', child: Text('未分组')),
              for (final group in groups)
                PopupMenuItem(value: group.id, child: Text(group.name)),
              const PopupMenuDivider(),
              for (final entry in {
                NodeListFilter.all: '全部节点',
                NodeListFilter.favorites: '仅收藏',
                NodeListFilter.hidden: '已隐藏',
              }.entries)
                CheckedPopupMenuItem(
                    value: '@view:${entry.key.name}',
                    checked: listFilter == entry.key,
                    child: Text(entry.value)),
            ],
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const RainlinkIcon(RainlinkGlyph.folder, size: 18),
              const SizedBox(width: 8),
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge)),
              const SizedBox(width: 6),
              const RainlinkIcon(RainlinkGlyph.chevronDown, size: 14),
            ])));
  }
}
