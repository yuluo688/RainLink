import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/core/core_providers.dart';
import '../../application/nodes/node_display_info.dart';
import '../../application/connection/session_controller.dart';
import '../../application/connection/traffic_format.dart';
import '../../design_system/theme/rainlink_colors.dart';
import '../../design_system/widgets/brand_mark.dart';
import '../../design_system/widgets/desktop_window_chrome.dart';
import '../../design_system/widgets/rainlink_icon.dart';
import '../../platform/window/desktop_window.dart';
import '../build_info.g.dart';
import 'app_destination.dart';

class DesktopShell extends StatelessWidget {
  const DesktopShell({required this.selected, required this.child, super.key});

  final AppDestination selected;
  final Widget child;

  static const _digitKeys = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
  ];
  static final _shortcuts = Map<ShortcutActivator, Intent>.unmodifiable({
    for (final modifier in [
      LogicalKeyboardKey.control,
      LogicalKeyboardKey.meta,
    ])
      for (final destination in AppDestination.values)
        LogicalKeySet(modifier, _digitKeys[destination.index]):
            _NavigateIntent(destination.path),
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final sidebarWidth = constraints.maxWidth >= 1440
          ? 248.0
          : constraints.maxWidth >= 1100
              ? 216.0
              : 72.0;
      return Shortcuts(
        shortcuts: _shortcuts,
        child: Actions(
          actions: {
            _NavigateIntent:
                CallbackAction<_NavigateIntent>(onInvoke: (intent) {
              context.go(intent.path);
              return null;
            }),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Row(
                children: [
                  _Sidebar(width: sidebarWidth, selected: selected),
                  Expanded(
                    child: Column(
                      children: [
                        _StatusBar(
                            selected: selected, compact: sidebarWidth == 72),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _NavigateIntent extends Intent {
  const _NavigateIntent(this.path);
  final String path;
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.width, required this.selected});

  final double width;
  final AppDestination selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RainlinkColors.of(context);
    final compact = width == 72;
    final core = ref.watch(coreStatusProvider).valueOrNull;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          DesktopWindowDragArea(
            child: Container(
              height: compact ? desktopHeaderHeight : 96,
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 15 : 20, vertical: 0),
              child: Row(
                children: [
                  BrandMark(size: compact ? 32 : 40),
                  if (!compact) ...[
                    const SizedBox(width: 12),
                    Expanded(
                        child: Text('RainLink',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontSize: 22))),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 20 : 7),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 20),
              children: [
                for (final destination in AppDestination.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Tooltip(
                      message: compact ? destination.label : '',
                      child: Material(
                        color: selected == destination
                            ? colors.primarySurface
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        child: InkWell(
                          key: ValueKey('nav-${destination.name}'),
                          borderRadius: BorderRadius.circular(9),
                          onTap: () => context.go(destination.path),
                          child: Semantics(
                            selected: selected == destination,
                            button: true,
                            label: compact ? destination.label : null,
                            child: SizedBox(
                              height: compact ? 44 : 40,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12),
                                child: Row(
                                  mainAxisAlignment: compact
                                      ? MainAxisAlignment.center
                                      : MainAxisAlignment.start,
                                  children: [
                                    RainlinkIcon(destination.icon,
                                        size: 18,
                                        color: selected == destination
                                            ? colors.primary
                                            : colors.secondary),
                                    if (!compact) ...[
                                      const SizedBox(width: 12),
                                      Expanded(
                                          child: Text(destination.label,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  height: 19 / 13,
                                                  color: selected == destination
                                                      ? colors.primary
                                                      : colors.secondary))),
                                      Text('${destination.index + 1}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: compact
                ? Tooltip(
                    message: core?.message ?? '正在检查核心',
                    child: RainlinkIcon(RainlinkGlyph.terminal,
                        size: 18, color: colors.muted))
                : Row(children: [
                    Expanded(
                        child: Text('RainLink $rainlinkVersion',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall)),
                    Tooltip(
                        message: core?.message ?? '正在检查核心',
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: colors.primarySurface,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                                core?.hostAvailable == true ? '核心就绪' : '核心离线',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: colors.primary, fontSize: 11)))),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _StatusBar extends ConsumerWidget {
  const _StatusBar({required this.selected, required this.compact});
  final AppDestination selected;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RainlinkColors.of(context);
    final message = ref.watch(coreStatusProvider.select((status) => status.when(
          data: (value) => value.message,
          loading: () => '正在检查核心服务',
          error: (error, stackTrace) => '宿主连接失败',
        )));
    final session = ref.watch(sessionControllerProvider);
    final status = session.connected
        ? NodeDisplayInfo.fromName(session.active?.target.name ?? '').name
        : session.working
            ? '正在更新连接…'
            : message;
    return Container(
      key: const ValueKey('desktop-status-bar'),
      height: desktopHeaderHeight,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: DesktopWindowDragArea(
              key: const ValueKey('window-status-drag-area'),
              child: Padding(
                padding: EdgeInsets.only(
                    left: compact ? 20 : 36,
                    right: usesCustomWindowChrome ? 20 : 36),
                child: Row(children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color:
                              session.connected ? colors.primary : colors.muted,
                          shape: BoxShape.circle)),
                  const SizedBox(width: 10),
                  Text(session.statusLabel,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: session.connected
                              ? colors.primary
                              : colors.secondary)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall)),
                  if (session.connected && !compact) ...[
                    if (session.telemetry?.latency != null)
                      Text('${session.telemetry?.latency} ms',
                          style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 16),
                    Text('↓ ${formatBytes(session.telemetry?.download ?? 0)}/s',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 16),
                    Text('↑ ${formatBytes(session.telemetry?.upload ?? 0)}/s',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(width: 28),
                  ],
                  const SizedBox(width: 12),
                  RainlinkIcon(selected.icon, size: 16),
                  const SizedBox(width: 8),
                  Text(selected.label,
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
            ),
          ),
          if (usesCustomWindowChrome) const DesktopWindowControls(),
        ],
      ),
    );
  }
}
