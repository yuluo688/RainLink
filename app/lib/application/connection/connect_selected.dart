import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/runtime_settings.dart';
import '../chains/chain_providers.dart';
import '../core/core_providers.dart';
import '../nodes/node_providers.dart';
import 'connection_providers.dart';
import 'session_controller.dart';

/// Startup and tray actions wait for storage, then use the same session commands.
final connectSelectedProvider =
    Provider<Future<void> Function({bool Function()? cancelled})>((ref) {
  return ({bool Function()? cancelled}) async {
    final controller = ref.read(sessionControllerProvider.notifier);
    final revision = controller.operationRevision;
    try {
      await Future.wait<Object?>([
        controller.initialized,
        ref.read(nodesProvider.future),
        ref.read(selectedNodeIdProvider.future),
        ref.read(chainsProvider.future),
        ref.read(selectedChainIdProvider.future),
        ref.read(coreStatusProvider.future),
      ]).timeout(const Duration(seconds: 10));
    } on TimeoutException {
      throw const SettingsException('读取连接目标超时，请检查本地数据和核心状态');
    }
    if (cancelled?.call() == true || revision != controller.operationRevision) {
      return;
    }
    if (!(ref.read(coreStatusProvider).valueOrNull?.capabilities.connect ??
        false)) {
      throw const SettingsException('网络核心尚未就绪，请在设置中检查');
    }
    final chain = ref.read(selectedChainProvider);
    final node = ref.read(selectedNodeProvider);
    if (chain != null) {
      await controller.connectChain(chain, ref.read(proxyModeProvider));
    } else if (node != null) {
      await controller.connect(node, ref.read(proxyModeProvider));
    } else {
      throw const SettingsException('尚未选择有效节点或代理链，请先在节点页选择');
    }
  };
});
