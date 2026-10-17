import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../application/chains/chain_providers.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../application/nodes/node_display_info.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/widgets/empty_state.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../domain/chains/proxy_chain.dart';
import '../../../domain/nodes/proxy_node.dart';
import 'chain_node_picker.dart';

class ChainPage extends ConsumerWidget {
  const ChainPage({super.key});

  Widget _library(BuildContext context, WidgetRef ref, List<ProxyChain> chains,
      ChainEditorState state) {
    final controller = ref.read(chainEditorProvider.notifier);
    return PopupMenuButton<String>(
        key: const ValueKey('chain-library'),
        enabled: !state.busy,
        tooltip: '打开或管理代理链',
        icon: const RainlinkIcon(RainlinkGlyph.more, size: 18),
        itemBuilder: (_) => [
              const PopupMenuItem(value: 'new', child: Text('新建代理链')),
              if (chains.isNotEmpty) const PopupMenuDivider(),
              for (final chain in chains)
                PopupMenuItem(
                    value: 'open:${chain.id}',
                    child: Row(children: [
                      RainlinkIcon(
                          chain.id == state.draft.id
                              ? RainlinkGlyph.check
                              : RainlinkGlyph.link,
                          size: 16),
                      const SizedBox(width: 12),
                      Flexible(
                          child:
                              Text(chain.name, overflow: TextOverflow.ellipsis))
                    ])),
              if (state.draft.revision > 0) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(value: 'delete', child: Text('删除当前代理链'))
              ],
            ],
        onSelected: (action) async {
          if (action == 'delete') {
            final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                        title: const Text('删除代理链？'),
                        content: Text('删除「${state.draft.name}」，其中的节点会保留。'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消')),
                          FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('删除'))
                        ]));
            if (confirmed == true && context.mounted) await controller.delete();
          } else {
            final id = action.startsWith('open:') ? action.substring(5) : null;
            if (id == state.draft.id) return;
            if (await _discard(context, ref) && context.mounted) {
              controller
                  .load(chains.where((chain) => chain.id == id).firstOrNull);
            }
          }
        });
  }

  Future<bool> _discard(BuildContext context, WidgetRef ref) async {
    final state = ref.read(chainEditorProvider);
    if (state.saving) return false;
    if (state.testing) {
      await ref.read(chainEditorProvider.notifier).cancel();
      if (!context.mounted) return false;
    }
    if (!state.dirty) return true;
    return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('放弃未保存的修改？'),
                    content: const Text('已保存的代理链不会改变。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('继续编辑')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('放弃修改'))
                    ])) ??
        false;
  }

  Future<void> _pick(BuildContext context, WidgetRef ref, List<ProxyNode> nodes,
      [int? index]) async {
    final state = ref.read(chainEditorProvider);
    final id = await showChainNodePicker(context,
        nodes: nodes, hopIds: state.draft.hopIds, replaceIndex: index);
    if (id == null || !context.mounted) return;
    final ids = [...state.draft.hopIds];
    if (index == null) {
      ids.add(id);
    } else {
      ids[index] = id;
    }
    ref.read(chainEditorProvider.notifier).setHops(ids);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chainEditorProvider);
    final controller = ref.read(chainEditorProvider.notifier);
    final nodesState = ref.watch(nodesProvider);
    final nodes = nodesState.valueOrNull ?? [];
    final chainsState = ref.watch(chainsProvider);
    final chains = chainsState.valueOrNull ?? [];
    final colors = RainlinkColors.of(context);
    final byId = {for (final node in nodes) node.id: node};
    final ids = state.draft.hopIds;
    final resolved = ids.map((id) => byId[id]).whereType<ProxyNode>().toList();
    final currentFingerprint = ChainSnapshot(state.draft, resolved).fingerprint;
    final validTest = resolved.length == ids.length &&
        state.test?.fingerprint == currentFingerprint;
    final mobile = AppLayout.current == AppLayout.mobile;
    final message = state.error.isNotEmpty ? state.error : state.notice;
    final controls = SurfaceCard(
        padding: EdgeInsets.all(RainlinkDensity.of(context).toolbarGap + 4),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('按顺序转发，最后一跳作为出口。',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  key: const ValueKey('chain-test'),
                  style: mobile
                      ? OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44))
                      : null,
                  onPressed: state.saving || ids.length < 2
                      ? null
                      : state.testing
                          ? controller.cancel
                          : () => controller.test(nodes),
                  icon: RainlinkIcon(
                      state.testing ? RainlinkGlyph.close : RainlinkGlyph.speed,
                      size: 16),
                  label: Text(state.testing ? '取消测试' : '测试链路')),
              const SizedBox(height: 12),
              FilledButton.icon(
                  key: const ValueKey('chain-save'),
                  style: mobile
                      ? FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44))
                      : null,
                  onPressed: state.busy || ids.length < 2
                      ? null
                      : () => controller.save(nodes),
                  icon: const RainlinkIcon(RainlinkGlyph.check, size: 16),
                  label: Text(state.saving ? '正在保存…' : '保存并选中')),
              const SizedBox(height: 12),
              Text('保存后仅更新选择，连接开关与代理模式均在概览。',
                  style: Theme.of(context).textTheme.bodySmall),
              if (state.testing) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text('正在逐段测试，最多约 40 秒',
                    style: Theme.of(context).textTheme.bodySmall)
              ],
              if (state.test != null && !validTest) ...[
                const SizedBox(height: 12),
                Text('路径或节点已更改，请重新测试', style: TextStyle(color: colors.warning))
              ],
              if (message.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(message,
                    key: const ValueKey('chain-feedback'),
                    style: TextStyle(
                        color: state.error.isEmpty
                            ? colors.primary
                            : colors.error))
              ],
              if (validTest && state.test != null) ...[
                const SizedBox(height: 8),
                Text('测试时间 ${_time(state.test!.checkedAt)} · 测试只反映当时的可达性',
                    style: Theme.of(context).textTheme.bodySmall)
              ],
            ]));
    final editor =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (chainsState.hasError)
        Text('代理链读取失败，请检查本地数据', style: TextStyle(color: colors.error)),
      TextFormField(
          key: ValueKey('chain-name-${state.draft.id}'),
          initialValue: state.draft.name,
          enabled: !state.busy,
          maxLength: 64,
          onChanged: controller.rename,
          decoration: InputDecoration(
              labelText: '链名称',
              counterText: '',
              suffixIcon: _library(context, ref, chains, state))),
      const SizedBox(height: 12),
      SurfaceCard(
          color: colors.raised,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Text(
              '本机 → ${ids.isEmpty ? '添加入口与出口节点' : ids.map((id) => byId[id] == null ? '节点已删除' : NodeDisplayInfo.fromName(byId[id]!.name).name).join(' → ')} → 目标',
              key: const ValueKey('chain-path'),
              style: Theme.of(context).textTheme.bodySmall)),
      const SizedBox(height: 12),
      if (nodesState.isLoading)
        const Center(child: CircularProgressIndicator())
      else if (nodes.isEmpty)
        SurfaceCard(
            child: EmptyState(
                icon: RainlinkGlyph.link,
                title: '还没有可用的链路节点',
                description: nodesState.hasError
                    ? '节点读取失败，请重试。'
                    : '请先添加订阅或单个节点，再编排入口与出口。'))
      else ...[
        AnimatedSize(
            duration: Duration(
                milliseconds:
                    MediaQuery.of(context).disableAnimations ? 0 : 220),
            alignment: Alignment.topCenter,
            child: Column(children: [
              for (var i = 0; i < ids.length; i++)
                Padding(
                    key: ValueKey('chain-hop-${ids[i]}'),
                    padding: EdgeInsets.only(
                        bottom: RainlinkDensity.of(context).sectionGap),
                    child: _HopCard(
                        index: i,
                        total: ids.length,
                        node: byId[ids[i]],
                        mobile: mobile,
                        test: validTest
                            ? state.test?.hops
                                .where((hop) => hop.hop == i + 1)
                                .firstOrNull
                            : null,
                        onReplace: state.busy
                            ? null
                            : () => _pick(context, ref, nodes, i),
                        onMove: (delta) {
                          final next = [...ids];
                          final id = next.removeAt(i);
                          next.insert(i + delta, id);
                          controller.setHops(next);
                        },
                        onRemove: state.busy
                            ? null
                            : () => controller.setHops([...ids]..removeAt(i)),
                        busy: state.busy)),
            ])),
        OutlinedButton.icon(
            key: const ValueKey('chain-add-hop'),
            style: mobile
                ? OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44))
                : null,
            onPressed: state.busy || ids.length >= maxChainHops
                ? null
                : () => _pick(context, ref, nodes),
            icon: const RainlinkIcon(RainlinkGlyph.plus, size: 18),
            label: Text(ids.length >= maxChainHops ? '最多 5 个跳点' : '添加跳点')),
      ],
    ]);
    return PageFrame(
      title: '代理链编排',
      description: '编排入口与出口，保存后在概览连接。',
      leading: IconButton.outlined(
        key: const ValueKey('back-to-nodes'),
        tooltip: '返回节点',
        onPressed: state.saving
            ? null
            : () async {
                if (await _discard(context, ref) && context.mounted) {
                  context.go('/nodes');
                }
              },
        style: IconButton.styleFrom(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        icon: const RainlinkIcon(RainlinkGlyph.back, size: 18),
      ),
      child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 720 &&
                  !mobile
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 2, child: editor),
                  const SizedBox(width: 24),
                  Expanded(
                      child: Padding(
                          padding: const EdgeInsets.only(top: 116),
                          child: controls))
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [editor, const SizedBox(height: 16), controls])),
    );
  }
}

String _time(DateTime at) =>
    '${at.month}/${at.day} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

class _HopCard extends StatelessWidget {
  const _HopCard(
      {required this.index,
      required this.total,
      required this.node,
      required this.mobile,
      required this.busy,
      required this.onReplace,
      required this.onMove,
      required this.onRemove,
      this.test});
  final int index;
  final int total;
  final ProxyNode? node;
  final bool mobile;
  final bool busy;
  final VoidCallback? onReplace;
  final void Function(int) onMove;
  final VoidCallback? onRemove;
  final ChainHopTest? test;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final role = index == 0
        ? '入口'
        : index == total - 1
            ? '出口'
            : '中继';
    Widget move(RainlinkGlyph icon, String label, int delta) {
      final action = busy || index + delta < 0 || index + delta >= total
          ? null
          : () => onMove(delta);
      return mobile
          ? IconButton(
              tooltip: label,
              onPressed: action,
              icon: RainlinkIcon(icon, size: 16))
          : TextButton.icon(
              onPressed: action,
              style: TextButton.styleFrom(foregroundColor: colors.secondary),
              icon: RainlinkIcon(icon, size: 16),
              label: Text(label));
    }

    return SurfaceCard(
        padding: EdgeInsets.all(RainlinkDensity.of(context).toolbarGap),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text('$role · 第 ${index + 1} 跳',
                    style: Theme.of(context).textTheme.bodySmall)),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: colors.raised,
                    borderRadius: BorderRadius.circular(6)),
                child: Text(node?.protocol.label ?? '失效',
                    style: Theme.of(context).textTheme.bodySmall))
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: Text(
                    node == null
                        ? '节点已删除，请更换'
                        : NodeDisplayInfo.fromName(node!.name).name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge)),
            const SizedBox(width: 8),
            Text(
                test == null
                    ? '未测试'
                    : test!.passed
                        ? '${test!.latency} ms'
                        : '未通过',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: test?.passed == true
                        ? colors.primary
                        : test == null
                            ? colors.muted
                            : colors.error))
          ]),
          const SizedBox(height: 12),
          Wrap(
              spacing: mobile ? 4 : 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: mobile ? 88 : 120,
                    child: OutlinedButton(
                        style: mobile
                            ? OutlinedButton.styleFrom(
                                minimumSize: const Size(88, 44))
                            : null,
                        onPressed: onReplace,
                        child: const Text('更换'))),
                move(RainlinkGlyph.upload, '上移', -1),
                move(RainlinkGlyph.download, '下移', 1),
                mobile
                    ? IconButton(
                        tooltip: '移除跳点',
                        onPressed: onRemove,
                        style: TextButton.styleFrom(
                            foregroundColor: colors.secondary),
                        icon: const RainlinkIcon(RainlinkGlyph.close, size: 16))
                    : TextButton.icon(
                        onPressed: onRemove,
                        style: TextButton.styleFrom(
                            foregroundColor: colors.secondary),
                        icon: const RainlinkIcon(RainlinkGlyph.close, size: 16),
                        label: const Text('移除')),
              ]),
        ]));
  }
}
