import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../application/groups/group_providers.dart';
import '../../../application/nodes/node_providers.dart';
import '../../../domain/groups/node_group.dart';
import '../../../domain/groups/subscription_issue.dart';
import '../../../domain/groups/subscription_review.dart';
import '../../../domain/nodes/proxy_node.dart';
import '../../../design_system/layout/app_layout.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/theme/rainlink_density.dart';
import '../../../design_system/widgets/empty_state.dart';
import '../../../design_system/widgets/page_frame.dart';
import '../../../design_system/widgets/surface_card.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../nodes/presentation/node_editor_dialog.dart';
import 'group_details_dialog.dart';

void _message(BuildContext context, Object error) {
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error is NodeException ? error.message : '分组操作失败，请重试')));
  }
}

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});
  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final repository = ref.read(groupRepositoryProvider);
    final name = await showGroupNameDialog(context);
    if (name == null) return;
    try {
      await repository.createManual(name);
    } on Exception catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider);
    final nodes =
        ref.watch(availableNodesProvider).valueOrNull ?? <ProxyNode>[];
    final data = groups.valueOrNull ?? <NodeGroup>[];
    final ungrouped = nodes.where((n) => n.groupId == null).length;
    final nonempty = data.isNotEmpty || ungrouped > 0;
    return PageFrame(
      title: '分组',
      description: '选择分组，在概览连接。订阅自动成组，单个节点默认未分组。',
      scrollable: !nonempty,
      actions: [
        TextButton(
            onPressed: () => _create(context, ref), child: const Text('新建分组')),
        FilledButton.icon(
            onPressed: () => showNodeEditor(context, subscription: true),
            icon: const RainlinkIcon(RainlinkGlyph.plus, size: 18),
            label: const Text('添加订阅')),
      ],
      child: groups.hasError
          ? EmptyState(
              icon: RainlinkGlyph.folder,
              title: '分组读取失败',
              description: '无法读取本地分组，请重试。')
          : groups.isLoading
              ? const Center(child: CircularProgressIndicator())
              : !nonempty
                  ? EmptyState(
                      icon: RainlinkGlyph.folder,
                      title: '还没有分组',
                      description: '导入订阅会自动创建分组，也可以新建分组后移入未分组节点。')
                  : Align(
                      alignment: Alignment.topCenter,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: data.length + (ungrouped > 0 ? 1 : 0),
                        separatorBuilder: (context, _) => SizedBox(
                            height: RainlinkDensity.of(context).listGap),
                        itemBuilder: (context, index) {
                          final group = ungrouped > 0 && index == 0
                              ? null
                              : data[index - (ungrouped > 0 ? 1 : 0)];
                          final count = group == null
                              ? ungrouped
                              : nodes
                                  .where((n) => n.groupId == group.id)
                                  .length;
                          return _GroupRow(group: group, count: count);
                        },
                      )),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  const _GroupRow({required this.group, required this.count});
  final NodeGroup? group;
  final int count;
  Future<void> _select(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupRepositoryProvider).select(group?.id);
    } on Exception catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  Future<void> _action(
      BuildContext context, WidgetRef ref, String action) async {
    final current = group;
    final repository = ref.read(groupRepositoryProvider);
    final operations = ref.read(subscriptionControllerProvider.notifier);
    if (action == 'browse') {
      ref.read(nodeGroupFilterProvider.notifier).state = current?.id ?? '';
      context.go('/nodes');
      return;
    }
    if (current == null) return;
    if (action == 'details') {
      await showGroupDetails(context, current);
      return;
    }
    try {
      if (action == 'update') {
        await operations.refresh(current.id);
        return;
      }
      if (action == 'cancel') {
        operations.cancel(current.id);
        return;
      }
      if (action == 'rename') {
        final name = await showGroupNameDialog(context, initial: current.name);
        if (name != null) {
          await repository.rename(current, name);
        }
        return;
      }
      if (action == 'delete') {
        final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('删除分组'),
                    content: Text(
                        '删除「${current.name}」及其订阅节点？手动移入的节点会回到未分组，正在使用的连接保留到断开。'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('取消')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('删除'))
                    ]));
        if (confirmed == true) {
          operations.cancel(current.id);
          await repository.delete(current.id);
        }
      }
    } on SubscriptionReviewRequired catch (error) {
      if (context.mounted) {
        await showGroupDetails(context, current, review: error.review);
      }
    } on SubscriptionContentException catch (error) {
      if (context.mounted) {
        await showGroupDetails(context, current, failure: error);
      }
    } on Exception catch (error) {
      if (context.mounted) _message(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final current = group;
    final selectedNode = ref.watch(selectedNodeProvider);
    final selected =
        selectedNode != null && selectedNode.groupId == current?.id;
    final busy =
        ref.watch(subscriptionControllerProvider).contains(current?.id);
    final isSubscription = current?.kind == GroupKind.subscription;
    final subtitle = current == null ? '手动添加的节点' : '手动分组';
    final menu = PopupMenuButton<String>(
        tooltip: '分组操作',
        icon: const RainlinkIcon(RainlinkGlyph.more, size: 18),
        onSelected: (action) => _action(context, ref, action),
        itemBuilder: (_) => [
              const PopupMenuItem(value: 'browse', child: Text('查看节点')),
              if (current != null) ...[
                const PopupMenuItem(value: 'details', child: Text('分组详情')),
                if (isSubscription)
                  PopupMenuItem(
                      value: busy ? 'cancel' : 'update',
                      child: Text(busy ? '取消更新' : '更新订阅')),
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                const PopupMenuItem(value: 'delete', child: Text('删除分组')),
              ],
            ]);
    final colors = RainlinkColors.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final desktop =
          AppLayout.current == AppLayout.desktop && constraints.maxWidth >= 680;
      final used = current?.used;
      final total = current?.total;
      return SurfaceCard(
          padding: EdgeInsets.zero,
          color: selected ? colors.primarySurface : null,
          borderColor: selected ? colors.primary : null,
          child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                key: ValueKey('group-${current?.id ?? 'ungrouped'}'),
                borderRadius: BorderRadius.circular(12),
                onTap: count == 0 ? null : () => _select(context, ref),
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minHeight: (desktop ? 70 : 62) +
                            (RainlinkDensity.of(context).compact ? 0 : 8)),
                    child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: RainlinkDensity.of(context).rowPadding),
                        child: Row(children: [
                          Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                  color: colors.primarySurface,
                                  borderRadius: BorderRadius.circular(8)),
                              alignment: Alignment.center,
                              child: RainlinkIcon(
                                  isSubscription
                                      ? RainlinkGlyph.profile
                                      : RainlinkGlyph.folder,
                                  size: 18,
                                  color: colors.primary)),
                          const SizedBox(width: 12),
                          Expanded(
                              flex: 4,
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(children: [
                                      Flexible(
                                          child: Text(current?.name ?? '未分组',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  theme.textTheme.labelLarge)),
                                      if (!desktop && isSubscription) ...[
                                        const SizedBox(width: 8),
                                        Text('$count 个节点',
                                            style: theme.textTheme.bodySmall),
                                      ],
                                    ]),
                                    const SizedBox(height: 4),
                                    if (!desktop && isSubscription)
                                      Wrap(
                                          spacing: 8,
                                          runSpacing: 2,
                                          children: [
                                            Text(
                                                used == null
                                                    ? total == null
                                                        ? '流量未提供'
                                                        : '总量 ${groupBytes(total)}'
                                                    : total == null
                                                        ? '已用 ${groupBytes(used)}'
                                                        : '${groupBytes(used)} / ${groupBytes(total)}',
                                                key: ValueKey(
                                                    'group-usage-${current?.id}'),
                                                style:
                                                    theme.textTheme.bodySmall),
                                            Text(
                                                current?.expiresAt == null
                                                    ? '到期未提供'
                                                    : '${groupDate(current?.expiresAt)} 到期',
                                                key: ValueKey(
                                                    'group-expiry-${current?.id}'),
                                                style:
                                                    theme.textTheme.bodySmall),
                                          ]),
                                    if (desktop ||
                                        !isSubscription ||
                                        busy ||
                                        current?.updateError.isNotEmpty == true)
                                      Text(
                                          busy
                                              ? '正在更新…'
                                              : current?.updateError
                                                          .isNotEmpty ==
                                                      true
                                                  ? '更新失败 · 已保留旧节点'
                                                  : desktop
                                                      ? '$count 个节点 · ${isSubscription ? (current?.autoUpdate == true ? '订阅自动更新' : '订阅手动更新') : current == null ? '手动添加' : '手动分组'}'
                                                      : '$count 个节点 · $subtitle',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: current?.updateError
                                                              .isNotEmpty ==
                                                          true
                                                      ? theme.colorScheme.error
                                                      : null)),
                                  ])),
                          if (desktop) ...[
                            const SizedBox(width: 24),
                            Expanded(
                                flex: 4,
                                child: isSubscription
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                            Text(
                                                used == null
                                                    ? '服务未提供流量信息'
                                                    : '已用 ${groupBytes(used)} / ${groupBytes(total)}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.bodySmall),
                                            if (used != null &&
                                                total != null &&
                                                total > 0) ...[
                                              const SizedBox(height: 6),
                                              LinearProgressIndicator(
                                                  value: (used / total)
                                                      .clamp(0, 1),
                                                  minHeight: 3,
                                                  color: used >= total
                                                      ? colors.error
                                                      : colors.primary,
                                                  backgroundColor:
                                                      colors.border,
                                                  borderRadius:
                                                      BorderRadius.circular(2)),
                                            ],
                                          ])
                                    : const SizedBox.shrink()),
                            const SizedBox(width: 24),
                            Expanded(
                                flex: 3,
                                child: isSubscription
                                    ? Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                            Text(
                                                current?.expiresAt == null
                                                    ? '有效期未提供'
                                                    : '${groupDate(current?.expiresAt)} 到期',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.bodySmall),
                                            const SizedBox(height: 3),
                                            Text(
                                                total == null || used == null
                                                    ? '以服务提供方为准'
                                                    : '剩余 ${groupBytes((total - used).clamp(0, total))}',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style:
                                                    theme.textTheme.bodySmall),
                                          ])
                                    : const SizedBox.shrink()),
                          ],
                          if (selected)
                            const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: RainlinkIcon(RainlinkGlyph.check,
                                    size: 18)),
                          SizedBox(width: 44, height: 44, child: menu),
                          if (desktop)
                            TextButton.icon(
                                onPressed: () =>
                                    _action(context, ref, 'browse'),
                                icon: const RainlinkIcon(
                                    RainlinkGlyph.chevronRight,
                                    size: 16),
                                label: const Text('节点')),
                        ]))),
              )));
    });
  }
}
