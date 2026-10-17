import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rainlink/application/routing/routing_providers.dart';
import 'package:rainlink/application/core/core_providers.dart';
import 'package:rainlink/platform/core/unavailable_core_gateway.dart';
import 'package:rainlink/design_system/theme/rainlink_theme.dart';
import 'package:rainlink/domain/routing/route_rules.dart';
import 'package:rainlink/features/rules/presentation/rules_page.dart';
import 'package:rainlink/features/rules/presentation/rule_editor_dialog.dart';

class _Rules implements RouteRuleRepository {
  var current = RouteRuleSet(revision: 0, rules: [
    const RouteRule(
        id: 'github',
        kind: RouteRuleKind.domainSuffix,
        value: 'github.com',
        target: RouteTarget(RouteTargetKind.proxy)),
    const RouteRule(
        id: 'local',
        kind: RouteRuleKind.ipCidr,
        value: '192.168.0.0/16',
        target: RouteTarget(RouteTargetKind.direct)),
    const RouteRule(
        id: 'fallback',
        kind: RouteRuleKind.match,
        value: '',
        target: RouteTarget(RouteTargetKind.proxy)),
  ]);
  final changes = StreamController<RouteRuleSet>.broadcast();
  Exception? failure;
  @override
  Stream<RouteRuleSet> watch() async* {
    yield current;
    yield* changes.stream;
  }

  @override
  Future<RouteRuleSet> load() async => current;
  @override
  Future<void> save(RouteRuleSet draft) async {
    final validated = draft.validated();
    if (failure case final error?) throw error;
    if (current.revision != draft.revision) {
      throw const RoutingException('规则已变更');
    }
    current =
        RouteRuleSet(revision: current.revision + 1, rules: validated.rules);
    changes.add(current);
  }
}

Future<_Rules> _pump(WidgetTester tester,
    {Size size = const Size(960, 640), double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final repository = _Rules();
  addTearDown(repository.changes.close);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        routeRepositoryProvider.overrideWithValue(repository),
        coreGatewayProvider
            .overrideWithValue(const UnavailableCoreGateway('test'))
      ],
      child: MaterialApp(
          theme: buildRainlinkTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: const Scaffold(body: RulesPage()))));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets(
      'filters and adding a normalized rule use real controller commands',
      (tester) async {
    final repository = await _pump(tester);
    await tester.tap(find.text('域名'));
    await tester.pumpAndSettle();
    expect(find.text('github.com'), findsOneWidget);
    expect(find.text('192.168.0.0/16'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('add-rule')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('rule-value')), ' OpenAI.COM. ');
    await tester.tap(find.byKey(const ValueKey('save-rule')));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditorDialog), findsNothing);
    expect(repository.current.rules[2].value, 'openai.com');
    expect(repository.current.rules.last.kind, RouteRuleKind.match);
    expect(find.text('openai.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'failed core validation leaves draft open and saved rules unchanged',
      (tester) async {
    final repository = await _pump(tester);
    repository.failure = const RoutingException('核心未通过规则校验，原规则已保留');
    await tester.tap(find.byKey(const ValueKey('add-rule')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('rule-value')), 'https://bad.test');
    await tester.tap(find.byKey(const ValueKey('save-rule')));
    await tester.pumpAndSettle();
    expect(repository.current.revision, 0);
    await tester.enterText(
        find.byKey(const ValueKey('rule-value')), 'valid.test');
    await tester.tap(find.byKey(const ValueKey('save-rule')));
    await tester.pumpAndSettle();
    expect(find.byType(RuleEditorDialog), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(RuleEditorDialog),
            matching: find.text('核心未通过规则校验，原规则已保留')),
        findsOneWidget);
    expect(repository.current.rules, hasLength(3));
    repository.failure = null;
    await tester.tap(find.byKey(const ValueKey('save-rule')));
    await tester.pumpAndSettle();
    expect(repository.current.revision, 1);
    expect(find.byType(RuleEditorDialog), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'rule menu moves and disables without changing the final fallback',
      (tester) async {
    final repository = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('rule-menu-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上移'));
    await tester.pumpAndSettle();
    expect(repository.current.rules.first.id, 'local');
    await tester.tap(find.byKey(const ValueKey('rule-menu-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('停用规则'));
    await tester.pumpAndSettle();
    expect(repository.current.rules.first.enabled, isFalse);
    expect(find.byKey(const ValueKey('rule-menu-fallback')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('rule-menu-local')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(repository.current.rules, hasLength(3));
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repository.current.rules.map((rule) => rule.id),
        ['github', 'fallback']);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final platform in [TargetPlatform.windows, TargetPlatform.android]) {
    testWidgets('rules and modal fit $platform with large text',
        (tester) async {
      await _pump(tester,
          size: platform == TargetPlatform.windows
              ? const Size(760, 640)
              : const Size(393, 852),
          scale: 1.5);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('add-rule')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // A raised mobile keyboard must keep the scrollable form and actions usable.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    }, variant: TargetPlatformVariant.only(platform));
  }
}
