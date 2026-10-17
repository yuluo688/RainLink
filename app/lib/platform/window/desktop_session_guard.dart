import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import '../../application/groups/subscription_expiry_monitor.dart';
import '../../application/connection/connect_selected.dart';
import '../../application/connection/connection_providers.dart';
import '../../application/connection/session_controller.dart';
import '../../application/core/core_providers.dart';
import '../../application/preferences/desktop_integration_controller.dart';
import '../../application/preferences/device_settings_controller.dart';
import '../../application/updates/app_update_controller.dart';
import '../../application/groups/group_providers.dart';
import '../../application/telemetry/core_log_collector.dart';
import '../../domain/updates/app_update.dart';
import '../../domain/connection/connection_models.dart';
import '../../domain/core/session_gateway.dart';
import '../../domain/platform/desktop_integration.dart';
import '../../domain/preferences/general_preferences.dart';

/// Normal exit awaits network restoration. Tray close preserves the live core.
class DesktopSessionGuard extends ConsumerStatefulWidget {
  const DesktopSessionGuard({required this.child, super.key});
  final Widget child;
  @override
  ConsumerState<DesktopSessionGuard> createState() =>
      _DesktopSessionGuardState();
}

class _DesktopSessionGuardState extends ConsumerState<DesktopSessionGuard>
    with WindowListener {
  DesktopIntegration? _integration;
  StreamSubscription<DesktopAction>? _actions;
  bool _closing = false;
  bool _acting = false;
  bool _disposed = false;
  Future<void> _trayUpdate = Future.value();
  Future<void> _preferenceWrites = Future.value();
  void Function()? _detachUpdate;
  bool _startupReady = false;

  @override
  void initState() {
    super.initState();
    if (!Platform.isWindows) return;
    _integration = ref.read(desktopIntegrationProvider);
    _detachUpdate = ref
        .read(updateShutdownProvider)
        .attach((update) => _exit(update: update));
    windowManager.addListener(this);
    unawaited(_initialize());
    ref.listenManual(proxyModeProvider, (previous, next) {
      if (previous != next) _remember(mode: next);
    });
    ref.listenManual(sessionControllerProvider, (previous, next) {
      _updateTray(next);
      if ((next.phase == ConnectionPhase.connected ||
              next.phase == ConnectionPhase.idle) &&
          (previous?.systemProxy != next.systemProxy ||
              previous?.tun != next.tun)) {
        _remember(systemProxy: next.systemProxy, tun: next.tun);
      }
      if (previous?.phase != next.phase &&
          (next.phase == ConnectionPhase.connected ||
              next.phase == ConnectionPhase.idle ||
              next.phase == ConnectionPhase.failed) &&
          ref
              .read(deviceSettingsControllerProvider)
              .general
              .connectionNotifications) {
        _notify(next.statusLabel);
      }
    });
  }

  Future<void> _initialize() async {
    try {
      await ref.read(startupReadyProvider);
      if (_disposed || _closing) return;
      if (mounted) setState(() => _startupReady = true);
      await windowManager.setPreventClose(true);
      if (_disposed) return;
      final integration = _integration;
      if (integration == null) return;
      _actions = integration.actions.listen((action) {
        if (_disposed || _closing || !mounted) return;
        if (action == DesktopAction.quit) {
          unawaited(_exit());
        } else if (action == DesktopAction.toggleConnection) {
          unawaited(_toggle());
        }
      });
      await integration.setTrayVisible(
          ref.read(deviceSettingsControllerProvider).general.showTray);
      if (_disposed) return;
      _updateTray(ref.read(sessionControllerProvider));
      if (ref.read(deviceSettingsControllerProvider).general.autoConnect) {
        await ref.read(connectSelectedProvider)(
            cancelled: () =>
                _disposed ||
                _closing ||
                !ref
                    .read(deviceSettingsControllerProvider)
                    .general
                    .autoConnect);
      }
    } on Exception catch (error) {
      _report('$error');
    }
  }

  void _report(String message) {
    if (_disposed) return;
    ref.read(desktopIntegrationNoticeProvider.notifier).state = message;
  }

  void _remember({ProxyMode? mode, bool? systemProxy, bool? tun}) {
    _preferenceWrites = ref
        .read(deviceSettingsControllerProvider.notifier)
        .saveConnection(mode: mode, systemProxy: systemProxy, tun: tun)
        .catchError((Object error, StackTrace stack) {
      _report('当前连接选项已生效，但下次启动的偏好未能保存。');
    });
  }

  void _updateTray(SessionView session) {
    final integration = _integration;
    if (integration == null || _disposed) return;
    final action = session.connected
        ? '断开连接'
        : session.phase == ConnectionPhase.starting
            ? '取消连接'
            : session.phase == ConnectionPhase.failed || session.active != null
                ? '恢复并断开'
                : '开始连接';
    _trayUpdate = _trayUpdate.then<void>((_) async {
      if (_disposed || _closing) return;
      await integration.updateTray(
          label: session.statusLabel,
          actionLabel: action,
          busy: session.working && session.phase != ConnectionPhase.starting);
    }).catchError((Object error, StackTrace stack) => _report('$error'));
  }

  void _notify(String message) {
    final integration = _integration;
    if (integration != null) {
      unawaited(integration
          .notifyConnection(message)
          .catchError((Object error, StackTrace stack) {
        _report('系统未能接收连接通知，可在设置中重试。');
      }));
    }
  }

  Future<void> _toggle() async {
    if (_acting || _closing) return;
    _acting = true;
    try {
      final state = ref.read(sessionControllerProvider);
      final controller = ref.read(sessionControllerProvider.notifier);
      if (state.phase == ConnectionPhase.starting ||
          state.connected ||
          state.active != null ||
          state.phase == ConnectionPhase.failed) {
        await controller.disconnect();
      } else if (!state.working) {
        await ref.read(connectSelectedProvider)(
            cancelled: () => _disposed || _closing);
      }
    } on Exception catch (error) {
      _report('$error');
      try {
        await _integration?.showWindow();
      } on Exception catch (showError) {
        _report('$showError');
      }
    } finally {
      _acting = false;
    }
  }

  @override
  void onWindowClose() => unawaited(_closeWindow());

  Future<void> _closeWindow() async {
    if (_closing) return;
    final general = ref.read(deviceSettingsControllerProvider).general;
    if (general.closeBehavior == WindowCloseBehavior.tray && general.showTray) {
      try {
        final integration = _integration;
        final observed = await integration?.inspect();
        if (observed?.trayVisible != true) {
          _report('托盘图标尚未就绪，窗口将保持打开。');
          return;
        }
        if (!_disposed) await integration?.hideWindow();
      } on Exception catch (error) {
        _report('无法安全隐藏窗口：$error');
      }
      return;
    }
    await _exit();
  }

  Future<void> _exit({PreparedUpdate? update}) async {
    if (_closing || _disposed) {
      if (update != null) throw const UpdateException('窗口正在退出，请稍后重试');
      return;
    }
    setState(() => _closing = true);
    final updates = ref.read(appUpdateControllerProvider.notifier);
    final maintenance = ref.read(subscriptionMaintenanceProvider);
    final subscriptions = ref.read(subscriptionControllerProvider.notifier);
    final logs = ref.read(coreLogCollectorProvider.notifier);
    final expiry = ref.read(subscriptionExpiryMonitorProvider);
    try {
      final session = ref.read(sessionControllerProvider.notifier);
      if (ref.read(sessionControllerProvider).phase != ConnectionPhase.idle) {
        await session.disconnect();
        if (_disposed) return;
        if (ref.read(sessionControllerProvider).phase != ConnectionPhase.idle) {
          throw const _RestoreIncomplete();
        }
      }
      final gateway = ref.read(coreGatewayProvider);
      await updates.close(handingOff: update != null);
      maintenance?.pause();
      await subscriptions.suspend();
      await maintenance?.suspend();
      await logs.suspend();
      await _preferenceWrites;
      await ref.read(deviceSettingsControllerProvider.notifier).flush();
      await expiry?.suspend();
      if (gateway is SessionGateway) await gateway.close();
      await _trayUpdate;
      // Native window destruction releases the tray. Keep its adapter alive
      // until then so a refused exit can continue to use this same window.
      await _integration?.setTrayVisible(false);
      // Native resources are already closed. Detach the local event listener
      // without awaiting cancellation from inside that listener's own callback.
      if (update != null) await update.commit();
      await windowManager.destroy();
    } on Exception catch (error) {
      try {
        await update?.abort();
      } on Exception {
        _report('安装交接未完成，安装程序正在停止，请稍后重试');
      }
      setState(() => _closing = false);
      updates.resumeAfterFailedExit(
          message: update == null ? '退出未完成，应用保持打开' : null);
      subscriptions.resume();
      maintenance?.resume();
      logs.resume();
      expiry?.resume();
      _report('$error');
      try {
        await _integration?.setTrayVisible(
            ref.read(deviceSettingsControllerProvider).general.showTray);
        await windowManager.show();
      } on Exception catch (showError) {
        _report('$showError');
      }
      if (update != null) rethrow;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _detachUpdate?.call();
    if (Platform.isWindows) windowManager.removeListener(this);
    unawaited(_actions?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !Platform.isWindows || (!_closing && _startupReady);
    return FocusTraversalGroup(
        descendantsAreFocusable: enabled,
        child: AbsorbPointer(absorbing: !enabled, child: widget.child));
  }
}

class _RestoreIncomplete implements Exception {
  const _RestoreIncomplete();
  @override
  String toString() => '网络设置尚未恢复，请在概览重试恢复后退出';
}
