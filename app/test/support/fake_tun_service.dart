import 'dart:async';

import 'package:rainlink/domain/platform/tun_service.dart';

class FakeTunService implements TunServiceGateway {
  TunServiceStatus status = serviceStatus(TunServiceState.missing);
  Completer<void>? operation;
  Exception? failure;
  Exception? inspectionFailure;
  bool apply = true;
  int inspections = 0;
  int changes = 0;
  int cancellations = 0;

  @override
  Future<TunServiceStatus> inspect() async {
    inspections++;
    if (inspectionFailure case final error?) throw error;
    return status;
  }

  @override
  Future<void> change(TunServiceAction action) async {
    changes++;
    await operation?.future;
    if (failure case final error?) throw error;
    if (apply) {
      status = serviceStatus(action == TunServiceAction.uninstall
          ? TunServiceState.missing
          : TunServiceState.current);
    }
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }

  @override
  Future<void> close() async {}
}

TunServiceStatus serviceStatus(TunServiceState state) => TunServiceStatus(
    state: state,
    canManage: state != TunServiceState.unavailable,
    enabled: state == TunServiceState.current,
    active: state == TunServiceState.current,
    message: switch (state) {
      TunServiceState.missing => '尚未安装 TUN 权限服务',
      TunServiceState.current => '服务文件与当前应用一致',
      TunServiceState.different => '已安装服务与当前应用不同，可更新服务',
      TunServiceState.incomplete => '服务文件不完整或无法验证，可尝试恢复安装',
      TunServiceState.unavailable => '未找到可用的系统授权工具 pkexec',
    });
