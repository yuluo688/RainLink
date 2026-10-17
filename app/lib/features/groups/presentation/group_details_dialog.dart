import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/groups/group_providers.dart';
import '../../../domain/groups/node_group.dart';
import '../../../domain/groups/subscription_issue.dart';
import '../../../domain/groups/subscription_review.dart';
import '../../../domain/nodes/proxy_node.dart';
import '../../../design_system/widgets/rainlink_switch.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/layout/app_layout.dart';
import 'subscription_review_panel.dart';

String groupBytes(int? bytes) {
  if (bytes == null) return '未提供';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  var value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(1)} ${units[index]}';
}

String groupDate(DateTime? date, {bool time = false}) {
  if (date == null) return '未提供';
  final local = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${pad(local.month)}-${pad(local.day)}${time ? ' ${pad(local.hour)}:${pad(local.minute)}' : ''}';
}

Future<void> showGroupDetails(BuildContext context, NodeGroup group,
        {SubscriptionReview? review, SubscriptionContentException? failure}) =>
    showDialog<void>(
        context: context,
        useSafeArea: AppLayout.current == AppLayout.desktop,
        builder: (_) => _GroupDetailsDialog(
            initial: group, review: review, failure: failure));

class _GroupDetailsDialog extends ConsumerStatefulWidget {
  const _GroupDetailsDialog({required this.initial, this.review, this.failure});
  final NodeGroup initial;
  final SubscriptionReview? review;
  final SubscriptionContentException? failure;
  @override
  ConsumerState<_GroupDetailsDialog> createState() =>
      _GroupDetailsDialogState();
}

class _GroupDetailsDialogState extends ConsumerState<_GroupDetailsDialog> {
  String? _error;
  bool _saving = false;
  SubscriptionReview? _review;
  SubscriptionContentException? _contentFailure;
  SubscriptionCancellation _cancellation = SubscriptionCancellation();

  @override
  void initState() {
    super.initState();
    _review = widget.review;
    _contentFailure = widget.failure;
    _error = widget.failure?.message;
  }

  @override
  void dispose() {
    _cancellation.cancel();
    super.dispose();
  }

  Future<void> _auto(NodeGroup group, bool enabled) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(groupRepositoryProvider).setAutoUpdate(group, enabled);
      if (mounted) setState(() => _review = null);
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _error = e is NodeException ? e.message : '无法保存更新设置');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _refresh(String id) async {
    setState(() {
      _error = null;
      _contentFailure = null;
    });
    try {
      final controller = ref.read(subscriptionControllerProvider.notifier);
      final review = _review;
      _cancellation = SubscriptionCancellation();
      if (review == null) {
        await controller.refresh(id, cancellation: _cancellation);
      } else {
        await controller.acceptReview(review, cancellation: _cancellation);
      }
      if (mounted) setState(() => _review = null);
    } on SubscriptionReviewRequired catch (e) {
      if (mounted) setState(() => _review = e.review);
    } on Exception catch (e) {
      if (mounted) {
        setState(() {
          _error = e is NodeException ? e.message : '订阅更新失败';
          _review = null;
          _contentFailure = e is SubscriptionContentException ? e : null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider).valueOrNull;
    final group = groups == null
        ? widget.initial
        : groups.where((g) => g.id == widget.initial.id).firstOrNull;
    final busy =
        ref.watch(subscriptionControllerProvider).contains(widget.initial.id);
    final usageSummary = switch ((group?.used, group?.total)) {
      (final used?, final total?) =>
        '${groupBytes(used)} / ${groupBytes(total)}',
      (final used?, null) => '已用 ${groupBytes(used)}',
      (null, final total?) => '总量 ${groupBytes(total)}',
      _ => null,
    };
    final mobile = AppLayout.current == AppLayout.mobile;
    final colors = RainlinkColors.of(context);
    Widget row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 88,
              child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ]));
    return AlertDialog(
      alignment: mobile ? Alignment.bottomCenter : Alignment.center,
      insetPadding: mobile
          ? EdgeInsets.fromLTRB(
              20, MediaQuery.viewPaddingOf(context).top + 20, 20, 0)
          : const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.border)),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      actionsPadding: EdgeInsets.fromLTRB(16, 12, 16,
          16 + (mobile ? MediaQuery.viewPaddingOf(context).bottom : 0)),
      title: Row(children: [
        SizedBox(
            width: 40,
            height: 40,
            child: IconButton(
                tooltip: '返回',
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: colors.border))),
                icon: const RainlinkIcon(RainlinkGlyph.back, size: 18))),
        const SizedBox(width: 8),
        Expanded(
            child: Text(group?.name ?? '分组已删除',
                style: Theme.of(context).textTheme.titleLarge)),
      ]),
      content: SizedBox(
          width: 488,
          child: SingleChildScrollView(
              child: group == null
                  ? const Text('此分组已不存在。')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          if (group.kind == GroupKind.subscription) ...[
                            const Text('套餐流量'),
                            const SizedBox(height: 8),
                            if (usageSummary != null)
                              Text(usageSummary,
                                  style:
                                      Theme.of(context).textTheme.headlineSmall)
                            else if (group.uploaded == null &&
                                group.downloaded == null)
                              Text('服务商未提供流量信息',
                                  style: Theme.of(context).textTheme.bodySmall),
                            if (group.used != null && (group.total ?? 0) > 0)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: LinearProgressIndicator(
                                      value: (group.used! / group.total!)
                                          .clamp(0.0, 1.0),
                                      borderRadius: BorderRadius.circular(4))),
                            Wrap(spacing: 8, runSpacing: 4, children: [
                              if ((group.used, group.total)
                                  case (final used?, final total?))
                                Text(
                                    '剩余 ${groupBytes((total - used).clamp(0, total))}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              if (group.downloaded != null)
                                Text('↓ ${groupBytes(group.downloaded)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                              if (group.uploaded != null)
                                Text('↑ ${groupBytes(group.uploaded)}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ]),
                            const SizedBox(height: 8),
                            row('到期时间', groupDate(group.expiresAt)),
                            row('上次成功', groupDate(group.updatedAt, time: true)),
                            if (group.updateError.isNotEmpty || _review != null)
                              row('最近尝试',
                                  groupDate(group.attemptedAt, time: true)),
                            Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    const Text('自动更新'),
                                    Text('应用运行时，每 ${group.intervalHours} 小时检查',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall),
                                  ])),
                              RainlinkSwitch(
                                  label: '自动更新',
                                  value: group.autoUpdate,
                                  onChanged: _saving || busy
                                      ? null
                                      : (v) => _auto(group, v))
                            ]),
                            if (_review case final review?)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: SubscriptionReviewPanel(
                                      key: ObjectKey(review),
                                      issues: review.document.issues,
                                      skippedNodes:
                                          review.document.skippedNodes,
                                      availableNodes:
                                          review.document.nodes.length,
                                      pending: true))
                            else if (_contentFailure case final failure?)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: SubscriptionReviewPanel(
                                      issues: failure.issues,
                                      skippedNodes: failure.skippedNodes,
                                      availableNodes: 0))
                            else if (group.issues.isNotEmpty ||
                                group.skippedNodes > 0)
                              Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: SubscriptionReviewPanel(
                                      issues: group.issues,
                                      skippedNodes: group.skippedNodes)),
                            if (group.updateError.isNotEmpty &&
                                _review == null &&
                                _error == null)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      '${group.updateError}\n已保留上次可用节点。',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                          ] else
                            row('来源', '手动分组'),
                          if (_error case final error?)
                            Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(error,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                        ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        if (group?.kind == GroupKind.subscription)
          FilledButton(
              onPressed: busy
                  ? () => ref
                      .read(subscriptionControllerProvider.notifier)
                      .cancel(widget.initial.id)
                  : () => _refresh(widget.initial.id),
              child: Text(busy
                  ? '取消更新'
                  : _review == null
                      ? '更新订阅'
                      : '确认更新')),
      ],
    );
  }
}

Future<String?> showGroupNameDialog(BuildContext context, {String? initial}) =>
    showDialog<String>(
        context: context, builder: (_) => _GroupNameDialog(initial: initial));

class _GroupNameDialog extends StatefulWidget {
  const _GroupNameDialog({this.initial});
  final String? initial;
  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController controller;
  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.initial == null ? '新建分组' : '重命名分组'),
          content: SizedBox(
              width: 360,
              child: TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 128,
                  decoration: const InputDecoration(labelText: '分组名称'),
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) Navigator.pop(context, v);
                  })),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () {
                  if (controller.text.trim().isNotEmpty) {
                    Navigator.pop(context, controller.text);
                  }
                },
                child: const Text('保存'))
          ]);
}
