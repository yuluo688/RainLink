enum TunServiceState { missing, current, different, incomplete, unavailable }

enum TunServiceAction { install, uninstall, recover }

class TunServiceStatus {
  const TunServiceStatus({
    required this.state,
    required this.canManage,
    required this.enabled,
    required this.active,
    required this.message,
  });

  final TunServiceState state;
  final bool canManage;
  final bool enabled;
  final bool active;
  final String message;
}

/// Service installation is separate from the network connection lifecycle.
abstract interface class TunServiceGateway {
  Future<TunServiceStatus> inspect();
  Future<void> change(TunServiceAction action);
  Future<void> cancel();
  Future<void> close();
}
