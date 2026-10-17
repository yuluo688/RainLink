import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/connection/connection_models.dart';
import '../preferences/device_settings_controller.dart';

// The desired mode for the next connection, not an active core setting.
final proxyModeProvider = StateProvider<ProxyMode>(
    (ref) => ref.read(initialDeviceSettingsProvider).connection.mode);

/// Injected platform policy; desktop capture preferences remain independent.
final requiredTunnelProvider = Provider<bool>((ref) => false);
