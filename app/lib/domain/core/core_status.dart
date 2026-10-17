/// Capabilities reported by the platform adapter, never inferred from the OS.
class CoreCapabilities {
  const CoreCapabilities({
    this.connect = false,
    this.systemProxy = false,
    this.tun = false,
    this.requiresTun = false,
  });

  final bool connect;
  final bool systemProxy;
  final bool tun;
  final bool requiresTun;
}

class CoreStatus {
  const CoreStatus({
    required this.hostAvailable,
    required this.message,
    this.hostVersion,
    this.coreVersion,
    this.capabilities = const CoreCapabilities(),
  });

  const CoreStatus.unavailable(String reason)
      : this(hostAvailable: false, message: reason);

  final bool hostAvailable;
  final String? hostVersion;
  final String? coreVersion;
  final String message;
  final CoreCapabilities capabilities;
}
