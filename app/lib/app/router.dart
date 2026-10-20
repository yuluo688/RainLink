import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../design_system/widgets/rainlink_page_transition.dart';
import '../features/chain/presentation/chain_page.dart';
import '../features/connections/presentation/connections_page.dart';
import '../features/groups/presentation/groups_page.dart';
import '../features/logs/presentation/logs_page.dart';
import '../features/nodes/presentation/nodes_page.dart';
import '../features/overview/presentation/overview_page.dart';
import '../features/rules/presentation/rules_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../features/settings/presentation/settings_section.dart';
import '../features/traffic/presentation/traffic_page.dart';
import 'navigation/rainlink_shell.dart';

GoRouter createRouter({String initialLocation = '/overview'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/', redirect: (context, state) => '/overview'),
    ShellRoute(
      builder:
          (context, state, child) =>
              RainlinkShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/overview',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const OverviewPage()),
        ),
        GoRoute(
          path: '/nodes',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const NodesPage()),
        ),
        GoRoute(
          path: '/groups',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const GroupsPage()),
        ),
        GoRoute(
          path: '/rules',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const RulesPage()),
        ),
        GoRoute(
          path: '/connections',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const ConnectionsPage()),
        ),
        GoRoute(
          path: '/traffic',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const TrafficPage()),
        ),
        GoRoute(
          path: '/logs',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const LogsPage()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder:
              (context, state) => _contentPage(
                context,
                state,
                SettingsPage(
                  initialSection:
                      SettingsSection.values
                          .where(
                            (section) =>
                                section.name ==
                                state.uri.queryParameters['section'],
                          )
                          .firstOrNull,
                ),
              ),
        ),
        GoRoute(
          path: '/chain',
          pageBuilder:
              (context, state) =>
                  _contentPage(context, state, const ChainPage()),
        ),
      ],
    ),
  ],
  errorBuilder:
      (context, state) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('页面不存在'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/overview'),
                child: const Text('返回概览'),
              ),
            ],
          ),
        ),
      ),
);

CustomTransitionPage<void> _contentPage(
  BuildContext context,
  GoRouterState state,
  Widget child,
) {
  final duration =
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : RainlinkPageTransition.duration;
  return CustomTransitionPage<void>(
    key: state.pageKey,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    child: child,
    transitionsBuilder:
        (context, animation, secondaryAnimation, child) =>
            RainlinkPageTransition(animation: animation, child: child),
  );
}
