import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../application/connection/session_controller.dart';
import '../../../../application/telemetry/connections_controller.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/telemetry_controls.dart';

class OverviewRecentConnection extends ConsumerStatefulWidget {
  const OverviewRecentConnection({super.key});

  @override
  ConsumerState<OverviewRecentConnection> createState() =>
      _OverviewRecentConnectionState();
}

class _OverviewRecentConnectionState
    extends ConsumerState<OverviewRecentConnection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The shared controller may already exist when navigating from Connections.
    // Schedule after build because setting foreground can update its state.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(connectionsControllerProvider.notifier)
            .setForeground(
              WidgetsBinding.instance.lifecycleState == null ||
                  WidgetsBinding.instance.lifecycleState ==
                      AppLifecycleState.resumed,
            );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(connectionsControllerProvider.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(
      sessionControllerProvider.select((session) => session.connected),
    );
    final view = ref.watch(connectionsControllerProvider);
    final recent = view.recent;
    final detail =
        !connected
            ? '连接后查看实际网络请求'
            : view.error.isNotEmpty
            ? '读取失败，打开连接页重试'
            : recent == null
            ? view.loading
                ? '正在读取连接…'
                : '等待网络请求'
            : '${recent.destination} · ${recent.direct ? '直连' : '代理'} · ${telemetryTime(recent.startedAt)}';
    final hint =
        recent == null
            ? detail
            : '本次会话最近观测的请求。${view.paused ? '视图已暂停。' : ''}\n$detail';
    return Row(
      key: const ValueKey('overview-recent-connection'),
      children: [
        Text('最近连接', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 12),
        Expanded(
          child: Tooltip(
            message: hint,
            child: Text(
              detail,
              key: const ValueKey('overview-recent-detail'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
        const SizedBox(width: 12),
        TextButton.icon(
          key: const ValueKey('overview-all-connections'),
          onPressed: () => context.go('/connections'),
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const RainlinkIcon(RainlinkGlyph.connections, size: 14),
          label: Text(view.paused ? '查看快照' : '查看全部'),
        ),
      ],
    );
  }
}
