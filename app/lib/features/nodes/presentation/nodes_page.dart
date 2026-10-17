import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/layout/desktop_collection_layout.dart';
import '../../../design_system/layout/mobile_collection_layout.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/empty_state.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../application/nodes/node_probe_controller.dart';
import '../../../application/groups/group_providers.dart';
import '../../../application/chains/chain_providers.dart';
import '../../../domain/nodes/proxy_node.dart';

import 'desktop_node_toolbar.dart';
import 'mobile_node_toolbar.dart';
import 'node_editor_dialog.dart';
import '../../../application/nodes/node_display_info.dart';
import 'widgets/node_row.dart';

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = ref.watch(nodesProvider);
    final listFilter = ref.watch(nodeListFilterProvider);
    final selected = ref.watch(selectedNodeIdProvider).valueOrNull;
    final selectedChain = ref.watch(selectedChainProvider);
    final query = _search.text.trim().toLowerCase();
    final keywords = query.split(RegExp(r'\s+'));
    final groups = ref.watch(groupsProvider).valueOrNull ?? [];
    final groupNames = {for (final group in groups) group.id: group.name};
    final requestedFilter = ref.watch(nodeGroupFilterProvider);
    final filter =
        requestedFilter == '' || groupNames.containsKey(requestedFilter)
            ? requestedFilter
            : null;
    final visible = (nodes.valueOrNull ?? <ProxyNode>[]).where((node) {
      if (listFilter == NodeListFilter.hidden ? !node.hidden : node.hidden) {
        return false;
      }
      if (listFilter == NodeListFilter.favorites && !node.favorite) {
        return false;
      }
      if (filter != null &&
          (filter == '' ? node.groupId != null : node.groupId != filter)) {
        return false;
      }
      if (query.isEmpty) return true;
      final info = NodeDisplayInfo.fromName(node.name);
      final searchText =
          '${node.name} ${node.sourceName} ${info.regionCode ?? ''} ${info.location ?? ''} '
                  '${node.protocol.label} ${node.server} ${groupNames[node.groupId] ?? '未分组'}'
              .toLowerCase();
      return keywords.every(searchText.contains);
    }).toList();
    final Widget content;
    if (nodes.hasError) {
      content = EmptyState(
          icon: RainlinkGlyph.nodes,
          title: '节点读取失败',
          description: '无法读取本地节点，请重试。');
    } else if (nodes.isLoading) {
      content = const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()));
    } else if (visible.isEmpty) {
      content = EmptyState(
          icon: RainlinkGlyph.nodes,
          title: query.isNotEmpty
              ? '没有匹配的节点'
              : switch (listFilter) {
                  NodeListFilter.favorites => '暂无收藏节点',
                  NodeListFilter.hidden => '没有已隐藏的节点',
                  NodeListFilter.all => '还没有节点',
                },
          description: query.isEmpty && listFilter == NodeListFilter.all
              ? '点击「添加」导入订阅或添加单个节点，也可以切换分组。'
              : listFilter == NodeListFilter.favorites && query.isEmpty
                  ? '点击节点右侧的星标，或切换到其他分组。'
                  : '试试其他名称、协议、地区或分组筛选。');
    } else {
      content = ListView.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) => SizedBox(
              height: AppLayout.current == AppLayout.mobile
                  ? RainlinkDensity.of(context).listGap
                  : 0),
          itemBuilder: (context, index) => NodeRow(
              key: ValueKey(visible[index].id),
              node: visible[index],
              selected: visible[index].id == selected,
              groupName: groupNames[visible[index].groupId] ?? '未分组'));
    }
    final toolbar = switch (AppLayout.current) {
      AppLayout.desktop => DesktopNodeToolbar(
          nodes: visible,
          controller: _search,
          onSearchChanged: (_) => setState(() {}),
          onClear: () => setState(_search.clear)),
      AppLayout.mobile => MobileNodeToolbar(
          nodes: visible,
          controller: _search,
          onSearchChanged: (_) => setState(() {}),
          onClear: () => setState(_search.clear)),
    };
    final error = ref.watch(nodeProbeProvider.select((state) => state.error));
    final tools =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      toolbar,
      if (error.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, style: Theme.of(context).textTheme.bodySmall)),
    ]);
    return PageFrame(
      scrollable: visible.isEmpty,
      title: '节点',
      description: selectedChain == null
          ? '管理连接节点。选择目标后，在概览中开始连接。'
          : '已选择代理链「${selectedChain.name}」。连接开关在概览。',
      actions: [
        FilledButton.icon(
          key: const ValueKey('add-node'),
          onPressed: () => showNodeEditor(context),
          icon: const RainlinkIcon(RainlinkGlyph.plus, size: 18),
          label: const Text('添加'),
        ),
      ],
      child: switch (AppLayout.current) {
        AppLayout.desktop => DesktopCollectionLayout(
            columns: const ['节点与地区', '协议', '延迟', '操作'],
            columnFlexes: nodeColumnFlexes,
            toolbar: tools,
            emptyState: content,
            expandContent: visible.isNotEmpty),
        AppLayout.mobile => MobileCollectionLayout(
            toolbar: tools,
            emptyState: content,
            framed: visible.isEmpty,
            expandContent: visible.isNotEmpty),
      },
    );
  }
}
