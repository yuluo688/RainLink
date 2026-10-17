import 'package:rainlink/domain/routing/route_rules.dart';

// Documentation-only data used to compare layout with Figma.
RouteRuleSet routingFixtureRules() => RouteRuleSet(revision: 0, rules: [
      for (final (index, domain) in ['github.com', 'openai.com'].indexed)
        RouteRule(
            id: 'domain-$index',
            kind: RouteRuleKind.domainSuffix,
            value: domain,
            target: const RouteTarget(RouteTargetKind.group, 'visual-main')),
      for (final (index, cidr) in ['192.168.0.0/16', '10.0.0.0/8'].indexed)
        RouteRule(
            id: 'cidr-$index',
            kind: RouteRuleKind.ipCidr,
            value: cidr,
            target: const RouteTarget(RouteTargetKind.direct)),
      const RouteRule(
          id: 'fallback',
          kind: RouteRuleKind.match,
          value: '',
          target: RouteTarget(RouteTargetKind.group, 'visual-main')),
    ]);
