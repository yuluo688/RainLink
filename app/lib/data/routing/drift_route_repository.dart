import 'dart:convert';
import '../../domain/routing/route_rules.dart';
import '../database/app_database.dart';
import '../chains/chain_records.dart';

const routeRulesKey = 'routing.rules';

class DriftRouteRepository implements RouteRuleRepository {
  DriftRouteRepository(this.database, this.validator);
  final AppDatabase database;
  final RouteRuleValidator validator;

  RouteRuleSet _decode(String? value) {
    if (value == null) return RouteRuleSet.defaults();
    try {
      final Object? json = jsonDecode(value);
      if (json is Map<String, Object?>) return RouteRuleSet.fromJson(json);
    } on FormatException {
      throw const RoutingException('已保存的规则损坏，请检查本地数据');
    }
    throw const RoutingException('已保存的规则格式无效');
  }

  @override
  Stream<RouteRuleSet> watch() => (database.select(database.preferences)
        ..where((row) => row.key.equals(routeRulesKey)))
      .watchSingleOrNull()
      .map((row) => _decode(row?.value));

  @override
  Future<RouteRuleSet> load() async =>
      _decode((await (database.select(database.preferences)
                ..where((row) => row.key.equals(routeRulesKey)))
              .getSingleOrNull())
          ?.value);

  @override
  Future<void> save(RouteRuleSet draft) async {
    final rules = draft.validated();
    // Validate without touching the running core. Recheck DB references after
    // the async boundary so deletion/subscription refresh cannot race a commit.
    await validator.validateRules(rules);
    await database.transaction(() async {
      final current = await load();
      if (current.revision != rules.revision) {
        throw const RoutingException('规则已被修改，请刷新后重试');
      }
      for (final rule in rules.rules.where((rule) => rule.enabled)) {
        final target = rule.target;
        if (target.kind == RouteTargetKind.chain) {
          final chain = (await loadChains(database))
              .where((chain) => chain.id == target.id)
              .firstOrNull;
          if (chain == null) {
            throw const RoutingException('规则引用的代理链已删除，请重新选择出站');
          }
          await resolveChain(database, chain);
        }
        if (target.kind == RouteTargetKind.group &&
            await (database.select(database.nodeGroups)
                      ..where((row) => row.id.equals(target.id)))
                    .getSingleOrNull() ==
                null) {
          throw const RoutingException('规则引用的分组已被删除，请重新选择出站');
        }
        if (target.kind == RouteTargetKind.node &&
            await (database.select(database.nodes)
                      ..where((row) => row.id.equals(target.id)))
                    .getSingleOrNull() ==
                null) {
          throw const RoutingException('规则引用的节点已被删除，请重新选择出站');
        }
      }
      await database.into(database.preferences).insertOnConflictUpdate(
          PreferencesCompanion.insert(
              key: routeRulesKey,
              value: jsonEncode(RouteRuleSet(
                      revision: current.revision + 1, rules: rules.rules)
                  .toJson())));
    });
  }
}
