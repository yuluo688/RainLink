import 'node_group.dart';

const subscriptionExpiryWarning = Duration(days: 3);

enum SubscriptionExpiryStage { soon, expired }

/// A receipt belongs to one subscription term, independent of node updates.
class SubscriptionExpiryAlert {
  const SubscriptionExpiryAlert({
    required this.groupId,
    required this.expiresAt,
    required this.stage,
  });
  final String groupId;
  final DateTime expiresAt;
  final SubscriptionExpiryStage stage;

  bool covers(SubscriptionExpiryAlert other) =>
      groupId == other.groupId &&
      expiresAt.isAtSameMomentAs(other.expiresAt) &&
      stage.index >= other.stage.index;
}

List<SubscriptionExpiryAlert> pendingSubscriptionExpiryAlerts(
    List<NodeGroup> groups,
    Map<String, SubscriptionExpiryAlert> receipts,
    DateTime now) {
  final pending = <SubscriptionExpiryAlert>[];
  for (final group in groups) {
    final expiry = group.expiresAt;
    if (group.kind != GroupKind.subscription || expiry == null) continue;
    final remaining = expiry.difference(now);
    if (remaining > subscriptionExpiryWarning) continue;
    final alert = SubscriptionExpiryAlert(
        groupId: group.id,
        expiresAt: expiry.toUtc(),
        stage: remaining <= Duration.zero
            ? SubscriptionExpiryStage.expired
            : SubscriptionExpiryStage.soon);
    if (receipts[group.id]?.covers(alert) != true) pending.add(alert);
  }
  return pending;
}

abstract interface class SubscriptionExpiryStore {
  Future<Map<String, SubscriptionExpiryAlert>> load();

  /// Merge receipts and prune deleted subscriptions in a single transaction.
  Future<void> record(List<SubscriptionExpiryAlert> alerts,
      {required Set<String> validGroupIds});
}
