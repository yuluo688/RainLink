import 'dart:io';

enum RouteRuleKind {
  domain('DOMAIN', '完整域名'),
  domainSuffix('DOMAIN-SUFFIX', '域名后缀'),
  ipCidr('IP-CIDR', 'IP 网段'),
  match('MATCH', '兜底规则');

  const RouteRuleKind(this.wireName, this.label);
  final String wireName;
  final String label;
}

enum RouteTargetKind { proxy, direct, reject, node, group, chain }

class RouteTarget {
  const RouteTarget(this.kind, [this.id = '']);
  final RouteTargetKind kind;
  final String id;
  String get key => switch (kind) {
        RouteTargetKind.node ||
        RouteTargetKind.group ||
        RouteTargetKind.chain =>
          '${kind.name}:$id',
        _ => kind.name,
      };

  factory RouteTarget.parse(String value) {
    for (final kind in RouteTargetKind.values) {
      if (value == kind.name &&
          kind != RouteTargetKind.node &&
          kind != RouteTargetKind.chain &&
          kind != RouteTargetKind.group) {
        return RouteTarget(kind);
      }
      if ((kind == RouteTargetKind.node ||
              kind == RouteTargetKind.group ||
              kind == RouteTargetKind.chain) &&
          value.startsWith('${kind.name}:')) {
        final id = value.substring(kind.name.length + 1);
        if (RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
          return RouteTarget(kind, id);
        }
      }
    }
    throw const RoutingException('规则的出站目标无效');
  }
}

class RouteRule {
  const RouteRule({
    required this.id,
    required this.kind,
    required this.value,
    required this.target,
    this.enabled = true,
  });
  final String id;
  final RouteRuleKind kind;
  final String value;
  final RouteTarget target;
  final bool enabled;

  RouteRule copyWith({bool? enabled}) => RouteRule(
      id: id,
      kind: kind,
      value: value,
      target: target,
      enabled: enabled ?? this.enabled);

  RouteRule normalized() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
      throw const RoutingException('规则标识无效');
    }
    RouteTarget.parse(target.key);
    return RouteRule(
        id: id,
        kind: kind,
        value: normalizeRuleValue(kind, value),
        target: target,
        enabled: enabled);
  }

  Map<String, Object> toJson() => {
        'id': id,
        'type': kind.wireName,
        'value': value,
        'target': target.key,
        'enabled': enabled,
      };

  factory RouteRule.fromJson(Map<String, Object?> json) {
    if (json
        case {
          'id': String id,
          'type': String type,
          'value': String value,
          'target': String target,
          'enabled': bool enabled
        }) {
      final kinds = RouteRuleKind.values.where((kind) => kind.wireName == type);
      if (kinds.isNotEmpty) {
        return RouteRule(
                id: id,
                kind: kinds.first,
                value: value,
                target: RouteTarget.parse(target),
                enabled: enabled)
            .normalized();
      }
    }
    throw const RoutingException('已保存的规则格式无效');
  }
}

class RouteRuleSet {
  RouteRuleSet({required this.revision, required List<RouteRule> rules})
      : rules = List.unmodifiable(rules);
  final int revision;
  final List<RouteRule> rules;
  static const maxRules = 256;
  static const maxTargets = 32;

  factory RouteRuleSet.defaults() => RouteRuleSet(revision: 0, rules: [
        for (final (index, cidr) in const [
          '192.168.0.0/16',
          '10.0.0.0/8',
          '172.16.0.0/12',
          '127.0.0.0/8',
          '169.254.0.0/16',
          '::1/128',
          'fc00::/7',
          'fe80::/10',
        ].indexed)
          RouteRule(
              id: 'local-$index',
              kind: RouteRuleKind.ipCidr,
              value: cidr,
              target: const RouteTarget(RouteTargetKind.direct)),
        const RouteRule(
            id: 'fallback',
            kind: RouteRuleKind.match,
            value: '',
            target: RouteTarget(RouteTargetKind.proxy)),
      ]);

  RouteRuleSet validated() {
    if (revision < 0 || rules.isEmpty || rules.length > maxRules) {
      throw const RoutingException('规则数量须在 1–256 条之间');
    }
    final normalized = rules.map((rule) => rule.normalized()).toList();
    if (normalized.map((rule) => rule.id).toSet().length != rules.length) {
      throw const RoutingException('规则标识重复');
    }
    final fallbacks =
        normalized.where((rule) => rule.kind == RouteRuleKind.match);
    if (fallbacks.length != 1 ||
        normalized.last.kind != RouteRuleKind.match ||
        !normalized.last.enabled) {
      throw const RoutingException('须保留一条已启用的兜底规则，并放在最后');
    }
    if (normalized
            .where((rule) =>
                rule.enabled &&
                [
                  RouteTargetKind.group,
                  RouteTargetKind.node,
                  RouteTargetKind.chain
                ].contains(rule.target.kind))
            .map((rule) => rule.target.key)
            .toSet()
            .length >
        maxTargets) {
      throw const RoutingException('独立出站目标最多 32 个');
    }
    return RouteRuleSet(revision: revision, rules: normalized);
  }

  Map<String, Object> toJson() => {
        'revision': revision,
        'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
      };

  factory RouteRuleSet.fromJson(Map<String, Object?> json) {
    if (json case {'revision': int revision, 'rules': List<Object?> rules}) {
      return RouteRuleSet(
              revision: revision,
              rules: rules.map((value) {
                if (value is! Map<String, Object?>) {
                  throw const RoutingException('已保存的规则格式无效');
                }
                return RouteRule.fromJson(value);
              }).toList())
          .validated();
    }
    throw const RoutingException('已保存的规则格式无效');
  }
}

String normalizeRuleValue(RouteRuleKind kind, String input) {
  final value = input.trim().toLowerCase();
  if (kind == RouteRuleKind.match) {
    if (value.isNotEmpty) throw const RoutingException('兜底规则不需要匹配条件');
    return '';
  }
  if (kind == RouteRuleKind.ipCidr) {
    final parts = value.split('/');
    final address = InternetAddress.tryParse(parts.first);
    final prefix = parts.length == 2 ? int.tryParse(parts.last) : null;
    if (address == null ||
        parts.length != 2 ||
        prefix == null ||
        prefix < 0 ||
        prefix > address.rawAddress.length * 8 ||
        value.contains('%')) {
      throw const RoutingException(
          '请输入有效 CIDR，例如 192.168.0.0/16 或 2001:db8::/32');
    }
    final bytes = address.rawAddress;
    for (var index = 0; index < bytes.length; index++) {
      final bits = (prefix - index * 8).clamp(0, 8);
      bytes[index] &= (0xff << (8 - bits)) & 0xff;
    }
    return '${InternetAddress.fromRawAddress(bytes).address}/$prefix';
  }
  final domain =
      value.endsWith('.') ? value.substring(0, value.length - 1) : value;
  if (domain.isEmpty ||
      domain.length > 253 ||
      InternetAddress.tryParse(domain) != null ||
      domain.split('.').any((part) =>
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(part))) {
    throw const RoutingException('请输入域名，不含协议、路径或通配符；国际域名请使用 Punycode');
  }
  return domain;
}

abstract interface class RouteRuleRepository {
  Stream<RouteRuleSet> watch();
  Future<RouteRuleSet> load();
  Future<void> save(RouteRuleSet draft);
}

abstract interface class RouteRuleValidator {
  Future<void> validateRules(RouteRuleSet rules);
}

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;
  @override
  String toString() => message;
}
