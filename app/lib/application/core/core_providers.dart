import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/core_gateway.dart';
import '../../domain/core/core_status.dart';
import '../updates/app_update_controller.dart';

final coreGatewayProvider = Provider<CoreGateway>((ref) {
  throw StateError('CoreGateway must be provided during bootstrap.');
});

final coreStatusProvider = FutureProvider<CoreStatus>((ref) async {
  // An update candidate must not launch a core child before the helper accepts
  // its first frame and migrated database.
  final gateway = ref.watch(coreGatewayProvider);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  await ref.watch(startupReadyProvider);
  if (disposed) return const CoreStatus.unavailable('应用已退出');
  return gateway.inspect();
});
