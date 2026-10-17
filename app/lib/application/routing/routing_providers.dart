import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/routing/route_rules.dart';
import '../../domain/routing/routing_plan.dart';
import '../nodes/node_providers.dart';
import '../groups/group_providers.dart';
import '../chains/chain_providers.dart';

final routeRepositoryProvider =
    Provider<RouteRuleRepository>((ref) => const _UnavailableRules());
final routingResolverProvider = Provider<RoutingResolver?>((ref) => null);
final routeRulesProvider = StreamProvider<RouteRuleSet>(
    (ref) => ref.watch(routeRepositoryProvider).watch());

final routingPlanProvider = FutureProvider<RoutingPlan?>((ref) async {
  ref.watch(routeRulesProvider);
  ref.watch(nodesProvider);
  ref.watch(groupsProvider);
  ref.watch(chainsProvider);
  final node = ref.watch(selectedNodeProvider);
  final chain = ref.watch(selectedChainProvider);
  final resolver = ref.watch(routingResolverProvider);
  if ((node == null && chain == null) || resolver == null) return null;
  return resolver.resolve(chain == null ? node : null, chain: chain);
});

class RulesEditState {
  const RulesEditState({this.saving = false, this.error = ''});
  final bool saving;
  final String error;
}

final rulesControllerProvider =
    StateNotifierProvider<RulesController, RulesEditState>(
        (ref) => RulesController(ref.watch(routeRepositoryProvider)));

class RulesController extends StateNotifier<RulesEditState> {
  RulesController(this.repository) : super(const RulesEditState());
  final RouteRuleRepository repository;

  Future<bool> save(RouteRuleSet draft) async {
    if (state.saving) return false;
    state = const RulesEditState(saving: true);
    try {
      await repository.save(draft);
      if (mounted) state = const RulesEditState();
      return true;
    } on Exception catch (error) {
      if (mounted) state = RulesEditState(error: error.toString());
      return false;
    }
  }

  Future<bool> upsert(RouteRuleSet current, RouteRule rule) {
    final rules = [...current.rules];
    final index = rules.indexWhere((item) => item.id == rule.id);
    if (index < 0) {
      rules.insert(rules.length - 1, rule);
    } else {
      rules[index] = rule;
    }
    return save(RouteRuleSet(revision: current.revision, rules: rules));
  }

  Future<bool> remove(RouteRuleSet current, String id) => save(RouteRuleSet(
      revision: current.revision,
      rules: current.rules.where((rule) => rule.id != id).toList()));

  Future<bool> toggle(RouteRuleSet current, RouteRule rule) =>
      upsert(current, rule.copyWith(enabled: !rule.enabled));

  Future<bool> move(RouteRuleSet current, String id, int delta) async {
    final rules = [...current.rules];
    final index = rules.indexWhere((rule) => rule.id == id);
    final destination = index + delta;
    if (index < 0 ||
        destination < 0 ||
        destination >= rules.length - 1 ||
        rules[index].kind == RouteRuleKind.match ||
        delta.abs() != 1) {
      return false;
    }
    final rule = rules.removeAt(index);
    rules.insert(destination, rule);
    return save(RouteRuleSet(revision: current.revision, rules: rules));
  }
}

class _UnavailableRules implements RouteRuleRepository {
  const _UnavailableRules();
  @override
  Stream<RouteRuleSet> watch() => Stream.value(RouteRuleSet.defaults());
  @override
  Future<RouteRuleSet> load() async => RouteRuleSet.defaults();
  @override
  Future<void> save(RouteRuleSet draft) async =>
      throw const RoutingException('规则存储尚未初始化');
}
