import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../application/connection/connection_providers.dart';
import '../../../../application/core/core_providers.dart';
import '../../../../application/connection/session_controller.dart';
import '../../../../application/nodes/node_providers.dart';
import '../../../../application/nodes/node_latency.dart';
import '../../../../application/chains/chain_providers.dart';
import '../../../../application/nodes/node_display_info.dart';
import '../../../../application/groups/group_providers.dart';
import '../../../../application/connection/traffic_format.dart';
import '../../../../application/routing/routing_pending.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/rainlink_segmented_control.dart';
import '../../../../design_system/widgets/rainlink_switch.dart';
import '../../../../design_system/widgets/rainlink_line_chart.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/connection/connection_models.dart';

class OverviewConnectionCard extends ConsumerWidget {
  const OverviewConnectionCard(
      {this.dense = false, this.mobile = false, super.key});

  final bool dense;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final node = ref.watch(selectedNodeProvider);
    final chain = ref.watch(selectedChainProvider);
    final available =
        ref.watch(coreStatusProvider).valueOrNull?.capabilities.connect ??
            false;
    final controller = ref.read(sessionControllerProvider.notifier);
    final active = session.active;
    final pending = active != null &&
        ((chain?.id ?? node?.id) != active.target.id ||
            (chain == null ? 'node' : 'chain') != active.target.kind ||
            (chain?.revision ?? node?.revision) != active.target.revision ||
            ref.watch(routingPendingProvider));
    final description = session.error.isNotEmpty
        ? session.error
        : pending
            ? '选择或规则已更改，断开重连后应用。'
            : session.connected
                ? session.tun
                    ? (session.systemProxy ? '系统代理与 TUN 已启用' : 'TUN 模式已启用')
                    : (session.systemProxy ? '系统代理已启用' : '核心运行中，系统代理未开启')
                : node != null || chain != null
                    ? '在此连接后生效。'
                    : '添加订阅或节点后，从这里开始连接。';
    final colors = RainlinkColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final nodes = ref.watch(availableNodesProvider).valueOrNull ?? [];
    final groups = ref.watch(groupsProvider).valueOrNull ?? [];
    final target = active == null
        ? node
        : nodes.where((item) => item.id == active.target.id).firstOrNull;
    final group =
        groups.where((item) => item.id == target?.groupId).firstOrNull;
    final isChain =
        active?.target.kind == 'chain' || active == null && chain != null;
    final nodeName = active?.target.name ?? chain?.name ?? node?.name;
    final displayName =
        nodeName == null ? null : NodeDisplayInfo.fromName(nodeName).name;
    final title =
        isChain ? nodeName ?? '代理链' : group?.name ?? displayName ?? '尚未选择连接目标';
    final hopCount = active == null
        ? chain?.hopIds.length
        : active.routeBindings.keys
            .where((key) => key.startsWith('proxy/hop/'))
            .length;
    final targetDescription = isChain
        ? '代理链 · $hopCount 跳，按编排顺序转发'
        : group == null
            ? target?.protocol.label ?? description
            : displayName ?? description;
    final VoidCallback? onConnect = session.phase == ConnectionPhase.starting
        ? controller.disconnect
        : session.working
            ? null
            : session.connected ||
                    active != null ||
                    session.phase == ConnectionPhase.failed
                ? controller.disconnect
                : available && (node != null || chain != null)
                    ? () => chain != null
                        ? controller.connectChain(
                            chain, ref.read(proxyModeProvider))
                        : controller.connect(node!, ref.read(proxyModeProvider))
                    : null;
    final connectLabel = session.phase == ConnectionPhase.starting
        ? '取消连接'
        : session.phase == ConnectionPhase.stopping
            ? '正在断开…'
            : session.connected || active != null
                ? '断开连接'
                : session.phase == ConnectionPhase.failed
                    ? '恢复并断开'
                    : '开始连接';
    final connectButton = Tooltip(
      message: available
          ? (node == null && chain == null ? '请先选择节点或代理链' : description)
          : '请先接入可用的网络核心',
      child: FilledButton.icon(
        key: const ValueKey('connect-button'),
        onPressed: onConnect,
        icon: const RainlinkIcon(RainlinkGlyph.power, size: 16),
        label: Text(connectLabel),
      ),
    );
    final selectButton = TextButton.icon(
      style:
          mobile ? TextButton.styleFrom(minimumSize: const Size(0, 44)) : null,
      onPressed: () => context.go(isChain
          ? '/chain'
          : group == null
              ? '/nodes'
              : '/groups'),
      icon: const RainlinkIcon(RainlinkGlyph.connections, size: 16),
      label: Text(mobile
          ? '选择'
          : isChain
              ? '编辑代理链'
              : group == null
                  ? '选择节点'
                  : '选择分组'),
    );
    if (mobile) {
      final latency = session.telemetry?.latency;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SurfaceCard(
            key: const ValueKey('overview-connection-card'),
            color: session.connected ? colors.primarySurface : null,
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              IconButton.filled(
                  key: const ValueKey('connect-button'),
                  tooltip: connectLabel,
                  onPressed: onConnect,
                  style: IconButton.styleFrom(
                      minimumSize: const Size(72, 72),
                      maximumSize: const Size(72, 72),
                      backgroundColor: colors.primary,
                      foregroundColor: colors.onPrimary),
                  icon: const RainlinkIcon(RainlinkGlyph.power, size: 28)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(session.statusLabel,
                        style: textTheme.headlineMedium
                            ?.copyWith(fontSize: 24, height: 1.3)),
                    if (session.error.isNotEmpty || pending)
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall)
                    else
                      InkWell(
                          onTap: session.connected
                              ? () => context.go('/connections')
                              : null,
                          borderRadius: BorderRadius.circular(4),
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 44),
                              child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                      session.connected
                                          ? '连接详情 ›'
                                          : '选择目标后，点按连接',
                                      style: textTheme.bodySmall)))),
                  ])),
            ])),
        const SizedBox(height: 12),
        SurfaceCard(
            key: const ValueKey('overview-target-card'),
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium)),
                    selectButton,
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(
                        child: Text(targetDescription,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall)),
                    const SizedBox(width: 8),
                    Text(latency == null ? '— ms' : '$latency ms',
                        style: textTheme.bodySmall
                            ?.copyWith(color: colors.primary)),
                  ]),
                ])),
      ]);
    }
    return SurfaceCard(
      key: const ValueKey('overview-connection-card'),
      color: session.connected ? colors.primarySurface : null,
      padding: EdgeInsets.symmetric(
          horizontal: dense ? 20 : 28, vertical: dense ? 12 : 16),
      child: LayoutBuilder(builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 560;
        final details = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: session.connected ? colors.primary : colors.muted,
                      shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(session.statusLabel,
                  style: textTheme.bodySmall?.copyWith(
                      color:
                          session.connected ? colors.primary : colors.muted)),
              if (session.telemetry?.latency != null) ...[
                const SizedBox(width: 12),
                Text('${session.telemetry?.latency} ms',
                    style: textTheme.bodySmall),
              ],
            ]),
            SizedBox(height: dense ? 4 : 8),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.headlineMedium
                    ?.copyWith(fontSize: dense ? 22 : 28, height: 1.3)),
            const SizedBox(height: 4),
            Tooltip(
                message: description,
                child: Text(
                    session.error.isNotEmpty || pending
                        ? description
                        : targetDescription,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall)),
          ],
        );
        if (horizontal) {
          return Row(
              crossAxisAlignment:
                  dense ? CrossAxisAlignment.center : CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 24),
                Align(
                    alignment: Alignment.centerRight,
                    widthFactor: 1,
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          connectButton,
                          if (!dense) const SizedBox(height: 8),
                          selectButton
                        ])),
              ]);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            details,
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 280) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    selectButton,
                    const SizedBox(height: 8),
                    connectButton
                  ],
                );
              }
              return Row(children: [
                selectButton,
                const Spacer(),
                connectButton,
              ]);
            }),
          ],
        );
      }),
    );
  }
}

class OverviewNetworkControlsCard extends ConsumerWidget {
  const OverviewNetworkControlsCard(
      {this.desktop = false,
      this.dense = false,
      this.mobile = false,
      super.key});
  final bool desktop;
  final bool dense;
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RainlinkColors.of(context);
    final requiresTun = ref.watch(requiredTunnelProvider);
    const capture = Row(children: [
      Expanded(child: _CapabilitySwitch(label: '系统代理')),
      SizedBox(width: 24),
      Expanded(child: _CapabilitySwitch(label: 'TUN 模式')),
    ]);
    if (desktop) {
      final captureCard = SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(height: dense ? 48 : 54, child: capture));
      final modeCard = SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SizedBox(
              height: dense ? 48 : 54, child: const _ProxyModeControl()));
      return dense
          ? Row(children: [
              Expanded(child: captureCard),
              const SizedBox(width: 8),
              Expanded(child: modeCard),
            ])
          : Column(
              children: [captureCard, const SizedBox(height: 8), modeCard]);
    }
    if (mobile || requiresTun) {
      final session = ref.watch(sessionControllerProvider);
      final platform =
          Theme.of(context).platform == TargetPlatform.iOS ? 'iOS' : 'Android';
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('网络接管 · $platform'),
                    Text('通过系统隧道接管网络',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
              const SizedBox(width: 8),
              Text(session.connected ? '已启用' : '连接时启用',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.primary)),
            ])),
        const SizedBox(height: 12),
        const SurfaceCard(
            padding: EdgeInsets.all(12),
            child: _ProxyModeControl(stacked: true)),
      ]);
    }
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            if (requiresTun) {
              return const Row(children: [
                RainlinkIcon(RainlinkGlyph.link, size: 18),
                SizedBox(width: 10),
                Expanded(child: Text('系统隧道')),
                Text('连接时自动启用'),
              ]);
            }
            const systemProxy = _CapabilitySwitch(label: '系统代理');
            const tun = _CapabilitySwitch(label: 'TUN 模式');
            if (constraints.maxWidth < 300) {
              return const Column(children: [systemProxy, tun]);
            }
            return Row(children: [
              const Expanded(child: systemProxy),
              const SizedBox(width: 12),
              Container(height: 24, width: 1, color: colors.border),
              const SizedBox(width: 12),
              const Expanded(child: tun),
            ]);
          }),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),
          const _ProxyModeControl(),
        ],
      ),
    );
  }
}

class _ProxyModeControl extends ConsumerWidget {
  const _ProxyModeControl({this.stacked = false});
  final bool stacked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(proxyModeProvider);
    return LayoutBuilder(builder: (context, constraints) {
      final selector = RainlinkSegmentedControl<ProxyMode>(
        expanded: stacked || constraints.maxWidth < 300,
        segments: const [
          RainlinkSegment(value: ProxyMode.rule, label: '规则'),
          RainlinkSegment(value: ProxyMode.global, label: '全局'),
          RainlinkSegment(value: ProxyMode.direct, label: '直连'),
        ],
        selected: mode,
        onChanged: (selection) {
          ref.read(sessionControllerProvider.notifier).setMode(selection);
        },
      );
      if (stacked || constraints.maxWidth < 300) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('代理模式'),
            const SizedBox(height: 8),
            selector,
          ],
        );
      }
      return Row(children: [
        const Expanded(child: Text('代理模式')),
        const SizedBox(width: 8),
        selector,
      ]);
    });
  }
}

class OverviewOutletCard extends ConsumerWidget {
  const OverviewOutletCard({this.mobile = false, super.key});
  final bool mobile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final data = session.telemetry;
    final ip = data?.ip;
    const countries = {
      'cn': '中国',
      'de': '德国',
      'gb': '英国',
      'jp': '日本',
      'nl': '荷兰',
      'sg': '新加坡',
      'us': '美国'
    };
    final code = data?.countryCode ?? '';
    final country = countries[code] ??
        (data?.country.isNotEmpty ?? false ? data?.country : null) ??
        '未获取';
    final textTheme = Theme.of(context).textTheme;
    final countryIndicator = Row(mainAxisSize: MainAxisSize.min, children: [
      if (countries.containsKey(code))
        SvgPicture.asset('assets/flags/$code.svg', width: 18, height: 14)
      else
        const RainlinkIcon(RainlinkGlyph.globe, size: 16),
      const SizedBox(width: 8),
      Flexible(
          child: Text(country, maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]);
    final refresh = Tooltip(
      message: data?.probeError.isNotEmpty ?? false
          ? data?.probeError ?? ''
          : '刷新出口与延迟',
      child: IconButton(
          onPressed: session.connected
              ? ref.read(sessionControllerProvider.notifier).probe
              : null,
          icon: const RainlinkIcon(RainlinkGlyph.refresh, size: 18)),
    );
    return SurfaceCard(
      key: const ValueKey('overview-outlet-card'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          if (mobile) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Text('当前出口', style: textTheme.bodySmall)),
                    ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .55),
                        child: countryIndicator),
                  ]),
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          SelectableText(
                              ip?.isNotEmpty ?? false ? ip ?? '' : '未获取',
                              key: const ValueKey('overview-outlet-ip'),
                              style: textTheme.titleMedium?.copyWith(
                                  fontFamily: 'Roboto Mono',
                                  fontSize: 18,
                                  height: 1.3,
                                  fontWeight: FontWeight.w400,
                                  fontVariations: const [
                                    FontVariation('wght', 400)
                                  ])),
                          Text(
                              session.connected
                                  ? data?.probeError.isNotEmpty == true
                                      ? '探测失败，点按重试'
                                      : '代理出口 · 以实际探测为准'
                                  : '连接后显示实际出口',
                              style: textTheme.bodySmall),
                        ])),
                    refresh,
                  ]),
                  const SizedBox(height: 6),
                ]);
          }
          return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(child: Text('当前出口', style: textTheme.bodySmall)),
                      ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.45),
                          child: countryIndicator),
                      const SizedBox(width: 8),
                      refresh,
                    ]),
                    SelectableText(ip?.isNotEmpty ?? false ? ip ?? '' : '未获取',
                        key: const ValueKey('overview-outlet-ip'),
                        style: textTheme.titleMedium?.copyWith(
                            fontFamily: 'Roboto Mono',
                            fontSize: 20,
                            height: 1.3,
                            fontWeight: FontWeight.w400,
                            fontVariations: const [
                              FontVariation('wght', 400)
                            ])),
                  ]));
        }
        return Row(children: [
          Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('当前出口', style: textTheme.bodySmall),
                const SizedBox(height: 4),
                Tooltip(
                    message: ip ?? '',
                    child: Text(ip?.isNotEmpty ?? false ? ip ?? '' : '未获取',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                            fontFamily: 'Roboto Mono',
                            fontSize: 20,
                            height: 1.1,
                            fontWeight: FontWeight.w400,
                            fontVariations: const [
                              FontVariation('wght', 400)
                            ]))),
              ])),
          Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('国家 / 地区', style: textTheme.bodySmall),
                const SizedBox(height: 4),
                countryIndicator,
              ])),
          if (constraints.maxWidth >= 700)
            Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(session.connected ? '代理出口' : '等待连接',
                      style: textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                      data?.probeError.isNotEmpty == true
                          ? '探测失败，可重试'
                          : '以实际出口探测为准',
                      style: textTheme.bodySmall),
                ])),
          refresh,
        ]);
      }),
    );
  }
}

class OverviewLatencyCard extends ConsumerWidget {
  const OverviewLatencyCard({this.expand = false, super.key});

  final bool expand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final samples =
        ref.watch(sessionControllerProvider.select((state) => state.latencies));
    final colors = RainlinkColors.of(context);
    final chart = RainlinkLineChart(series: [
      RainlinkChartSeries(
          samples.map((value) => value.toDouble()).toList(), colors.primary,
          fill: true)
    ], emptyLabel: '暂无延迟数据');
    return SurfaceCard(
      key: const ValueKey('overview-latency-card'),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text('延迟趋势',
                    style: Theme.of(context).textTheme.titleMedium)),
            Text(samples.isEmpty ? '等待探测' : '${samples.last} ms',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
          const SizedBox(height: 8),
          if (expand)
            Expanded(child: chart)
          else
            SizedBox(height: 100, child: chart),
          const SizedBox(height: 8),
          const _HostStatusHint(),
        ],
      ),
    );
  }
}

class OverviewNodeHealthCard extends ConsumerWidget {
  const OverviewNodeHealthCard({this.dense = false, super.key});
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final nodes = ref.watch(availableNodesProvider).valueOrNull ?? [];
    final current = nodes.where((node) => node.id == session.active?.target.id);
    final visible = [
      ...current,
      ...nodes.where((node) => node.id != session.active?.target.id)
    ].take(dense ? 2 : 3);
    final colors = RainlinkColors.of(context);
    return SurfaceCard(
      key: const ValueKey('overview-health-card'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('节点健康', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          if (nodes.isEmpty) {
            return Center(
                child: Text('添加节点后查看状态',
                    style: Theme.of(context).textTheme.bodySmall));
          }
          final capacity =
              (constraints.maxHeight / 28).floor().clamp(0, visible.length);
          return Column(children: [
            for (final node in visible.take(capacity))
              Consumer(builder: (context, ref, _) {
                final health = ref.watch(nodeLatencyProvider(node));
                final latency = health.latency;
                return SizedBox(
                    height: 28,
                    child: Row(children: [
                      Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: health.failed && !health.pending
                                  ? colors.error
                                  : latency != null
                                      ? colors.primary
                                      : colors.muted)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(NodeDisplayInfo.fromName(node.name).name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall)),
                      const SizedBox(width: 8),
                      Text(
                          health.pending
                              ? '测速中'
                              : health.failed
                                  ? '失败'
                                  : latency != null
                                      ? '$latency ms'
                                      : '未探测',
                          style: Theme.of(context).textTheme.bodySmall),
                    ]));
              }),
          ]);
        })),
        InkWell(
            onTap: () => context.go('/groups'),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  const RainlinkIcon(RainlinkGlyph.folder, size: 14),
                  const SizedBox(width: 8),
                  Text('管理分组', style: Theme.of(context).textTheme.bodySmall),
                ]))),
      ]),
    );
  }
}

class _HostStatusHint extends ConsumerWidget {
  const _HostStatusHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RainlinkColors.of(context);
    final message = ref.watch(coreStatusProvider.select((core) => core.when(
          data: (value) => value.message,
          loading: () => '正在检查桌面宿主…',
          error: (error, stackTrace) => '宿主检查失败，可在设置中重试。',
        )));
    return Row(
      key: const ValueKey('overview-host-status'),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RainlinkIcon(RainlinkGlyph.terminal, size: 16, color: colors.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
              message: message,
              child: Text(message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontSize: 11))),
        ),
      ],
    );
  }
}

class _CapabilitySwitch extends ConsumerWidget {
  const _CapabilitySwitch({required this.label});
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final capabilities =
        ref.watch(coreStatusProvider).valueOrNull?.capabilities;
    final isTun = label == 'TUN 模式';
    final available =
        (isTun ? capabilities?.tun : capabilities?.systemProxy) ?? false;
    final controller = ref.read(sessionControllerProvider.notifier);
    return Row(children: [
      Expanded(child: Text(label)),
      Tooltip(
        message: isTun
            ? available
                ? '连接时接管设备流量；Windows 可能申请管理员权限，连接中切换会重连当前目标'
                : '当前平台尚未接入 TUN'
            : available
                ? '连接时启用当前用户的系统代理，断开后恢复原设置'
                : '当前平台尚未接入系统代理',
        child: RainlinkSwitch(
            key: ValueKey('capture-$label'),
            label: label,
            value: isTun ? session.tun : session.systemProxy,
            onChanged: available &&
                    !session.working &&
                    (session.active == null || session.connected)
                ? isTun
                    ? controller.setTun
                    : controller.setSystemProxy
                : null),
      ),
    ]);
  }
}

class OverviewMetricCard extends ConsumerWidget {
  const OverviewMetricCard(
      {required this.label, required this.detail, super.key});
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final data = session.telemetry;
    final traffic = ref.watch(dailyTrafficProvider).valueOrNull;
    final value = switch (label) {
      '今日流量' => traffic == null ? '—' : formatBytes(traffic.total),
      '下载速度' => data == null ? '—' : '${formatBytes(data.download)}/s',
      '网络质量' => data?.latency == null ? '—' : '${data?.latency} ms',
      _ => '—',
    };
    final subtitle = switch (label) {
      '下载速度' when data != null => '上传 ${formatBytes(data.upload)}/s',
      '今日流量' when traffic != null =>
        '↓ ${formatBytes(traffic.download)}   ↑ ${formatBytes(traffic.upload)}',
      '网络质量' when data?.latency != null => '经当前代理的请求耗时',
      _ => detail,
    };
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child:
                    Text(label, style: Theme.of(context).textTheme.bodySmall)),
            const SizedBox(width: 8),
            Flexible(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(height: 1.1, fontSize: 22))),
          ]),
          const SizedBox(height: 4),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.2)),
        ],
      ),
    );
  }
}
