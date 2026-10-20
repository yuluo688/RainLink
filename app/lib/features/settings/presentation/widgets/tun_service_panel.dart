import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/connection/session_controller.dart';
import '../../../../application/core/tun_service_controller.dart';
import '../../../../design_system/theme/rainlink_colors.dart';
import '../../../../design_system/widgets/rainlink_icon.dart';
import '../../../../design_system/widgets/surface_card.dart';
import '../../../../domain/platform/tun_service.dart';

class TunServicePanel extends ConsumerWidget {
  const TunServicePanel({super.key});

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    TunServiceAction action,
    String label,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('$label？'),
            content: SizedBox(
              width: 400,
              child: Text(switch (action) {
                TunServiceAction.install =>
                  '将安装或更新当前版本的 TUN 权限服务，需要管理员授权。节点和订阅会保留。',
                TunServiceAction.uninstall =>
                  '将关闭并卸载权限服务，恢复相关网络设置，需要管理员授权。节点和订阅会保留。',
                TunServiceAction.recover => '将检查并恢复上次未完成的服务安装，需要管理员授权。',
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(label),
              ),
            ],
          ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(tunServiceControllerProvider.notifier).perform(action);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tunServiceGatewayProvider) == null) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(tunServiceControllerProvider);
    final session = ref.watch(sessionControllerProvider);
    final status = view.status;
    final idle =
        !session.working && !session.connected && session.active == null;
    final enabled =
        !view.busy && !view.loading && idle && status?.canManage == true;
    final colors = RainlinkColors.of(context);
    return SurfaceCard(
      key: const ValueKey('tun-service-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const RainlinkIcon(RainlinkGlyph.shield, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'TUN 权限服务',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '重新检查权限服务',
                onPressed:
                    view.busy || view.loading
                        ? null
                        : () =>
                            ref
                                .read(tunServiceControllerProvider.notifier)
                                .refresh(),
                icon: const RainlinkIcon(RainlinkGlyph.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            view.loading ? '正在检查服务…' : status?.message ?? '服务状态未获取',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (status != null &&
              (status.state == TunServiceState.current ||
                  status.state == TunServiceState.different)) ...[
            const SizedBox(height: 6),
            Text(
              '${status.active ? '服务已启动' : '服务未启动'} · ${status.enabled ? '开机启用' : '未设为开机启用'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '安装并启用后，在概览开启 TUN 模式；连接时由系统申请授权。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!idle) ...[
            const SizedBox(height: 8),
            Text('请先在概览断开连接，再管理权限服务。', style: TextStyle(color: colors.warning)),
          ],
          if (view.loading || view.busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (view.busy) ...[
            const SizedBox(height: 8),
            Text(view.cancelling ? '正在取消并确认恢复，请稍候…' : '等待系统授权或安装完成…'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('cancel-service-operation'),
                onPressed:
                    view.cancelling
                        ? null
                        : () =>
                            ref
                                .read(tunServiceControllerProvider.notifier)
                                .cancel(),
                child: const Text('取消操作'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status?.state != TunServiceState.current ||
                    status?.enabled != true ||
                    status?.active != true)
                  OutlinedButton(
                    key: const ValueKey('install-tun-service'),
                    onPressed:
                        enabled
                            ? () => _confirm(
                              context,
                              ref,
                              TunServiceAction.install,
                              status?.state == TunServiceState.different
                                  ? '更新服务'
                                  : status?.state == TunServiceState.current
                                  ? '启用服务'
                                  : '安装服务',
                            )
                            : null,
                    child: Text(
                      status?.state == TunServiceState.different
                          ? '更新服务'
                          : status?.state == TunServiceState.current
                          ? '启用服务'
                          : '安装服务',
                    ),
                  ),
                if (status != null && status.state != TunServiceState.missing)
                  OutlinedButton(
                    key: const ValueKey('uninstall-tun-service'),
                    onPressed:
                        enabled
                            ? () => _confirm(
                              context,
                              ref,
                              TunServiceAction.uninstall,
                              '卸载服务',
                            )
                            : null,
                    child: const Text('卸载服务'),
                  ),
                OutlinedButton(
                  key: const ValueKey('recover-tun-service'),
                  onPressed:
                      enabled
                          ? () => _confirm(
                            context,
                            ref,
                            TunServiceAction.recover,
                            '恢复安装',
                          )
                          : null,
                  child: const Text('恢复安装'),
                ),
              ],
            ),
          ],
          if (view.error.isNotEmpty || view.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              view.error.isNotEmpty ? view.error : view.message,
              style: TextStyle(
                color: view.error.isNotEmpty ? colors.error : colors.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
