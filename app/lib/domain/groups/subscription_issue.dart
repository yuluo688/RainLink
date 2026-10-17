import '../nodes/proxy_node.dart';

enum SubscriptionIssueKind { unsupported, invalid, notice, configuration }

/// Carries safe diagnostics, without retaining the subscription URL or secrets.
class SubscriptionContentException extends NodeException {
  SubscriptionContentException(
      {required this.skippedNodes, required List<SubscriptionIssue> issues})
      : issues = List.unmodifiable(issues),
        super('没有可用节点：$skippedNodes 项使用了不支持的协议、传输或无效参数');
  final int skippedNodes;
  final List<SubscriptionIssue> issues;
}

/// Diagnostics identify an item by position, never by its URI or credentials.
class SubscriptionIssue {
  const SubscriptionIssue(
      {required this.kind, required this.reason, this.item});
  final SubscriptionIssueKind kind;
  final String reason;
  final int? item;
  bool get requiresReview => kind != SubscriptionIssueKind.notice;
  String get label => item == null ? '配置内容' : '第 $item 项';

  Map<String, Object?> toJson() =>
      {'kind': kind.name, 'reason': reason, if (item != null) 'item': item};

  static SubscriptionIssue? fromJson(Object? value) {
    if (value is! Map<String, Object?>) return null;
    final kind = SubscriptionIssueKind.values
        .where((kind) => kind.name == value['kind'])
        .firstOrNull;
    final reason = value['reason'];
    final item = value['item'];
    if (kind == null ||
        reason is! String ||
        reason.isEmpty ||
        reason.length > 160 ||
        reason.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        item != null && (item is! int || item < 1 || item > 2000)) {
      return null;
    }
    return SubscriptionIssue(kind: kind, reason: reason, item: item as int?);
  }
}
