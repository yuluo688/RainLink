import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../connection/session_controller.dart';
import '../chains/chain_providers.dart';
import '../nodes/node_providers.dart';
import 'routing_providers.dart';

final routingPendingProvider = Provider<bool>((ref) {
  final active =
      ref.watch(sessionControllerProvider.select((view) => view.active));
  if (active == null) return false;
  final chain = ref.watch(selectedChainProvider);
  final node = ref.watch(selectedNodeProvider);
  if ((chain?.id ?? node?.id) != active.target.id ||
      (chain == null ? 'node' : 'chain') != active.target.kind ||
      (chain?.revision ?? node?.revision) != active.target.revision) {
    return true;
  }
  final rules = ref.watch(routeRulesProvider);
  if (rules.hasError) return true;
  if (rules.valueOrNull?.revision != active.ruleRevision) return true;
  final resolved = ref.watch(routingPlanProvider);
  if (resolved.hasError) return true;
  final plan = resolved.valueOrNull;
  if (plan == null) return false;
  return !plan.matchesBindings(active.routeBindings);
});
