import '../nodes/proxy_node.dart';
import 'node_group.dart';

const subscriptionReviewLifetime = Duration(minutes: 10);

/// This short-lived object holds the fetched document in memory until a decision.
/// It must never be logged or serialized: its source and nodes contain secrets.
class SubscriptionReview {
  SubscriptionReview({
    required this.source,
    required SubscriptionDocument document,
    required this.createdAt,
    this.groupId,
    this.groupRevision,
  }) : document = SubscriptionDocument(
            name: document.name,
            nodes: List.unmodifiable(document.nodes.map((node) => NodeDraft(
                name: node.name,
                protocol: node.protocol,
                server: node.server,
                port: node.port,
                tls: node.tls,
                authenticate: node.authenticate,
                username: node.username,
                password: node.password,
                obfsPassword: node.obfsPassword,
                options: NodeOptions.fromJson({
                  ...node.options.toJson(),
                  'alpn': List<String>.unmodifiable(node.options.alpn),
                  'serverPorts':
                      List<String>.unmodifiable(node.options.serverPorts),
                })))),
            uploaded: document.uploaded,
            downloaded: document.downloaded,
            total: document.total,
            expiresAt: document.expiresAt,
            intervalHours: document.intervalHours,
            skippedNodes: document.skippedNodes,
            issues: List.unmodifiable(document.issues));
  final Uri source;
  final SubscriptionDocument document;
  final DateTime createdAt;
  final String? groupId;
  final int? groupRevision;
}

class SubscriptionReviewRequired extends NodeException {
  SubscriptionReviewRequired(this.review) : super('订阅包含不兼容内容，请查看后确认；原有节点保持不变');
  final SubscriptionReview review;
}

abstract interface class SubscriptionReviewRepository {
  Future<String> acceptReview(
      SubscriptionReview review, SubscriptionCancellation cancellation,
      {bool autoUpdate = true});
}
