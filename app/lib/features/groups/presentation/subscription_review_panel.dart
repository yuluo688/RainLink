import 'package:flutter/material.dart';

import '../../../design_system/theme/rainlink_colors.dart';
import '../../../design_system/widgets/rainlink_icon.dart';
import '../../../domain/groups/subscription_issue.dart';

/// Shared by the existing import and details dialogs; never receives the URL.
class SubscriptionReviewPanel extends StatefulWidget {
  const SubscriptionReviewPanel({
    required this.issues,
    required this.skippedNodes,
    this.availableNodes,
    this.pending = false,
    super.key,
  });
  final List<SubscriptionIssue> issues;
  final int skippedNodes;
  final int? availableNodes;
  final bool pending;

  @override
  State<SubscriptionReviewPanel> createState() =>
      _SubscriptionReviewPanelState();
}

class _SubscriptionReviewPanelState extends State<SubscriptionReviewPanel> {
  bool _expanded = false;
  static const _previewLimit = 3;

  @override
  Widget build(BuildContext context) {
    final colors = RainlinkColors.of(context);
    final theme = Theme.of(context);
    Widget issue(SubscriptionIssue issue) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 68,
              child: Text(issue.label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: 8),
          Expanded(child: Text(issue.reason, style: theme.textTheme.bodySmall)),
        ]));
    return Container(
      key: const ValueKey('subscription-compatibility'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: colors.raised,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          RainlinkIcon(RainlinkGlyph.profile,
              size: 16,
              color: widget.pending ? colors.warning : colors.secondary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(widget.pending ? '导入前确认' : '兼容信息',
                  style: theme.textTheme.titleSmall)),
        ]),
        const SizedBox(height: 8),
        Text(
            [
              if (widget.availableNodes case final count?) '可导入 $count 个节点',
              if (widget.skippedNodes > 0) '未导入 ${widget.skippedNodes} 项',
              if (widget.availableNodes == null && widget.skippedNodes == 0)
                '仅导入节点，其他配置未应用',
            ].join(' · '),
            style: theme.textTheme.bodyMedium),
        if (widget.pending) ...[
          const SizedBox(height: 4),
          Text('确认后仅保存可用节点。订阅内的其他配置不会应用。', style: theme.textTheme.bodySmall),
        ],
        if (_expanded && widget.issues.length > _previewLimit)
          SizedBox(
              height: 200,
              child: ListView.builder(
                  primary: false,
                  itemCount: widget.issues.length,
                  itemBuilder: (_, index) => issue(widget.issues[index])))
        else
          for (final value in widget.issues.take(_previewLimit)) issue(value),
        if (widget.issues.isEmpty && widget.skippedNodes > 0)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('此来源未提供逐项原因，可确认导入已识别的节点。',
                  style: theme.textTheme.bodySmall)),
        if (widget.issues.length > _previewLimit)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  key: const ValueKey('toggle-compatibility-issues'),
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded
                      ? '收起原因'
                      : '查看全部 ${widget.issues.length} 项原因'))),
      ]),
    );
  }
}
