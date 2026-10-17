import '../nodes/proxy_node.dart';
import 'subscription_issue.dart';

enum GroupKind { manual, subscription }

class NodeGroup {
  const NodeGroup(
      {required this.id,
      required this.name,
      required this.kind,
      this.uploaded,
      this.downloaded,
      this.total,
      this.expiresAt,
      this.updatedAt,
      this.attemptedAt,
      this.updateError = '',
      this.skippedNodes = 0,
      this.issues = const [],
      this.autoUpdate = true,
      this.intervalHours = 24,
      this.revision = 1});
  final String id;
  final String name;
  final GroupKind kind;
  final int? uploaded;
  final int? downloaded;
  final int? total;
  final DateTime? expiresAt;
  final DateTime? updatedAt;
  final DateTime? attemptedAt;
  final String updateError;
  final int skippedNodes;
  final List<SubscriptionIssue> issues;
  final bool autoUpdate;
  final int intervalHours;
  final int revision;
  int? get used {
    final upload = uploaded;
    final download = downloaded;
    if (upload == null ||
        download == null ||
        upload > 0x7fffffffffffffff - download) {
      return null;
    }
    return upload + download;
  }

  bool isDue(DateTime now) =>
      kind == GroupKind.subscription &&
      autoUpdate &&
      (attemptedAt == null ||
          !now.isBefore(attemptedAt!.add(Duration(hours: intervalHours))));
}

/// Cancellation closes the owned HTTP client and is checked before a DB commit.
class SubscriptionCancellation {
  bool _cancelled = false;
  void Function()? _abort;
  bool get isCancelled => _cancelled;
  void bind(void Function()? abort) {
    _abort = abort;
    if (_cancelled) abort?.call();
  }

  void cancel() {
    _cancelled = true;
    _abort?.call();
  }

  void check() {
    if (_cancelled) throw const SubscriptionCancelled();
  }
}

class SubscriptionCancelled extends NodeException {
  const SubscriptionCancelled() : super('订阅操作已取消');
}

class SubscriptionDocument {
  const SubscriptionDocument(
      {required this.name,
      required this.nodes,
      this.uploaded,
      this.downloaded,
      this.total,
      this.expiresAt,
      this.intervalHours = 24,
      this.skippedNodes = 0,
      this.issues = const []});
  final String name;
  final List<NodeDraft> nodes;
  final int? uploaded;
  final int? downloaded;
  final int? total;
  final DateTime? expiresAt;
  final int intervalHours;
  final int skippedNodes;
  final List<SubscriptionIssue> issues;
  bool get requiresReview =>
      issues.any((issue) => issue.requiresReview) ||
      skippedNodes > issues.where((issue) => issue.item != null).length;
}

abstract interface class SubscriptionFetcher {
  Future<SubscriptionDocument> fetch(
      Uri url, SubscriptionCancellation cancellation);
}

abstract interface class GroupRepository {
  Stream<List<NodeGroup>> watchGroups();
  Future<String> importUrl(String url, SubscriptionCancellation cancellation,
      {bool autoUpdate = true});
  Future<void> refresh(String id, SubscriptionCancellation cancellation);
  Future<String> createManual(String name);
  Future<void> rename(NodeGroup group, String name);
  Future<void> setAutoUpdate(NodeGroup group, bool enabled);
  Future<void> select(String? groupId);
  Future<void> moveUngrouped(String nodeId, String groupId);
  Future<void> delete(String id);
}
