import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/platform/tun_service.dart';
import '../connection/session_controller.dart';
import 'core_providers.dart';

final tunServiceGatewayProvider = Provider<TunServiceGateway?>((ref) => null);
final tunServiceControllerProvider =
    StateNotifierProvider<TunServiceController, TunServiceView>((ref) {
  final gateway = ref.watch(tunServiceGatewayProvider);
  final busy = ref.read(coreServiceBusyProvider.notifier);
  return TunServiceController(gateway,
      canChange: () {
        final session = ref.read(sessionControllerProvider);
        return !session.working && !session.connected && session.active == null;
      },
      onBusy: (value) => busy.state = value);
});

class TunServiceView {
  const TunServiceView({
    this.status,
    this.loading = false,
    this.action,
    this.cancelling = false,
    this.message = '',
    this.error = '',
  });

  final TunServiceStatus? status;
  final bool loading;
  final TunServiceAction? action;
  final bool cancelling;
  final String message;
  final String error;
  bool get busy => action != null;
}

class TunServiceController extends StateNotifier<TunServiceView> {
  TunServiceController(this.gateway,
      {required this.canChange, required this.onBusy})
      : super(const TunServiceView()) {
    if (gateway != null) unawaited(refresh());
  }

  final TunServiceGateway? gateway;
  final bool Function() canChange;
  final void Function(bool) onBusy;

  Future<void> refresh() async {
    final service = gateway;
    if (service == null || state.busy || state.loading) return;
    state = TunServiceView(status: state.status, loading: true);
    try {
      final status = await service.inspect();
      if (mounted) state = TunServiceView(status: status);
    } on Exception catch (error) {
      if (mounted) state = TunServiceView(error: '$error');
    }
  }

  Future<void> perform(TunServiceAction action) async {
    final service = gateway;
    if (service == null || state.busy || state.loading) return;
    final previous = state.status;
    if (previous == null || !previous.canManage) return;
    if (!canChange()) {
      state = TunServiceView(status: previous, error: '请先在概览断开连接，再管理权限服务');
      return;
    }
    // This synchronous lease blocks new connection attempts before any await.
    onBusy(true);
    state = TunServiceView(status: previous, action: action);
    String error = '';
    TunServiceStatus? observed;
    var confirmed = false;
    try {
      await service.change(action);
      confirmed = true;
    } on Exception catch (failure) {
      error = '$failure';
    }
    try {
      observed = await service.inspect();
      if (confirmed && !_matches(action, observed)) {
        error = '服务状态未通过回读确认，请重新检查或恢复安装';
      }
    } on Exception catch (failure) {
      error = error.isEmpty ? '$failure' : '$error\n无法重新读取服务状态';
    } finally {
      if (mounted) {
        onBusy(false);
        state = TunServiceView(
            status: observed,
            message: error.isEmpty && confirmed ? '服务管理已完成，并已重新检查状态' : '',
            error: error);
      }
    }
  }

  bool _matches(TunServiceAction action, TunServiceStatus observed) =>
      switch (action) {
        TunServiceAction.install => observed.state == TunServiceState.current,
        TunServiceAction.uninstall => observed.state == TunServiceState.missing,
        TunServiceAction.recover =>
          observed.state != TunServiceState.incomplete &&
              observed.state != TunServiceState.unavailable,
      };

  Future<void> cancel() async {
    final service = gateway;
    if (service == null || !state.busy || state.cancelling) return;
    state = TunServiceView(
        status: state.status, action: state.action, cancelling: true);
    try {
      await service.cancel();
      // Await the original operation and read-back. A cancel acknowledgement
      // cannot prove a root transaction has exited or restored its files.
    } on Exception catch (error) {
      if (mounted && state.busy) {
        state = TunServiceView(
            status: state.status,
            action: state.action,
            cancelling: true,
            error: '$error');
      }
    }
  }
}
