import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/core/core_providers.dart';
import '../application/preferences/theme_controller.dart';
import '../application/preferences/device_settings_controller.dart';
import '../domain/preferences/device_settings.dart';
import '../application/nodes/node_providers.dart';
import '../application/nodes/node_probe_controller.dart';
import '../application/groups/group_providers.dart';
import '../application/groups/subscription_expiry_monitor.dart';
import '../application/updates/app_update_controller.dart';
import '../data/updates/drift_update_preferences.dart';
import '../data/updates/github_release_source.dart';
import '../platform/updates/file_update_downloader.dart';
import '../platform/updates/process_update_installer.dart';
import '../platform/updates/android_update_installer.dart';
import '../application/connection/session_controller.dart';
import '../application/connection/connection_providers.dart';
import '../application/telemetry/core_log_collector.dart';
import '../application/routing/routing_providers.dart';
import '../application/chains/chain_providers.dart';
import '../data/chains/drift_chain_repository.dart';
import '../domain/chains/proxy_chain.dart';
import '../data/routing/drift_route_repository.dart';
import '../data/routing/drift_routing_resolver.dart';
import '../domain/routing/route_rules.dart';
import '../data/logs/drift_core_log_repository.dart';
import '../data/database/app_database.dart';
import '../data/preferences/drift_preferences_repository.dart';
import '../data/nodes/drift_node_repository.dart';
import '../data/nodes/drift_node_overrides_repository.dart';
import '../data/groups/drift_group_repository.dart';
import '../data/groups/drift_subscription_expiry_store.dart';
import '../data/subscriptions/http_subscription_fetcher.dart';
import '../data/traffic/drift_traffic_repository.dart';
import '../domain/core/core_gateway.dart';
import '../domain/preferences/app_preferences.dart';
import '../domain/nodes/proxy_node.dart';
import '../domain/nodes/node_probe.dart';
import '../platform/core/desktop_core_gateway.dart';
import '../platform/core/linux_tun_service_gateway.dart';
import '../application/core/tun_service_controller.dart';
import '../platform/core/android_core_gateway.dart';
import '../platform/core/unavailable_core_gateway.dart';
import '../platform/window/windows_desktop_integration.dart';
import '../platform/window/linux_desktop_integration.dart';
import '../application/preferences/desktop_integration_controller.dart';
import '../application/preferences/mobile_integration_controller.dart';
import '../platform/notifications/android_mobile_integration.dart';
import '../application/import/qr_import_providers.dart';
import '../data/import/qr_import_parser.dart';
import '../features/nodes/presentation/qr_import_dialog.dart';
import '../platform/qr/mobile_qr_camera_session.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw StateError('AppDatabase must be provided during bootstrap.');
});

/// Owns concrete adapters; presentation and application depend on interfaces.
List<Override> createAppOverrides({
  required AppDatabase database,
  required AppTheme initialTheme,
  DeviceSettings initialSettings = const DeviceSettings(),
  Future<void>? startupReady,
}) => [
  qrImportParserProvider.overrideWithValue(const StandardQrImportParser()),
  qrCameraFactoryProvider.overrideWithValue(
    Platform.isAndroid || Platform.isIOS ? MobileQrCameraSession.new : null,
  ),
  databaseProvider.overrideWith((ref) {
    ref.onDispose(() => unawaited(database.close()));
    return database;
  }),
  preferencesRepositoryProvider.overrideWith((ref) {
    return DriftPreferencesRepository(ref.watch(databaseProvider));
  }),
  initialThemeProvider.overrideWithValue(initialTheme),
  startupReadyProvider.overrideWith(
    (ref) => startupReady ?? Future<void>.value(),
  ),
  initialDeviceSettingsProvider.overrideWithValue(initialSettings),
  requiredTunnelProvider.overrideWithValue(Platform.isAndroid),
  mobileIntegrationProvider.overrideWith((ref) {
    if (!Platform.isAndroid) return null;
    final integration = AndroidMobileIntegration();
    ref.onDispose(integration.dispose);
    return integration;
  }),
  appReleaseSourceProvider.overrideWith(
    (ref) =>
        Platform.isWindows
            ? GithubReleaseSource()
            : Platform.isAndroid
            ? GithubReleaseSource(target: 'android-universal', extension: 'apk')
            : null,
  ),
  updatePreferencesProvider.overrideWith(
    (ref) =>
        Platform.isWindows || Platform.isAndroid
            ? DriftUpdatePreferences(ref.watch(databaseProvider))
            : null,
  ),
  updateDownloaderProvider.overrideWith(
    (ref) =>
        Platform.isWindows || Platform.isAndroid
            ? FileUpdateDownloader()
            : null,
  ),
  updateInstallerProvider.overrideWith(
    (ref) =>
        Platform.isWindows
            ? ProcessUpdateInstaller()
            : Platform.isAndroid
            ? AndroidUpdateInstaller()
            : null,
  ),
  updateInstallationModeProvider.overrideWithValue(
    Platform.isAndroid
        ? UpdateInstallationMode.androidInstaller
        : UpdateInstallationMode.desktopRestart,
  ),
  updateReceiptProvider.overrideWith((ref) {
    if (Platform.isWindows) return readUpdateReceipt;
    final installer = ref.watch(updateInstallerProvider);
    return Platform.isAndroid && installer is AndroidUpdateInstaller
        ? installer.readReceipt
        : null;
  }),
  desktopIntegrationProvider.overrideWith((ref) {
    if (!Platform.isWindows && !Platform.isLinux) return null;
    final integration =
        Platform.isLinux
            ? LinuxDesktopIntegration()
            : WindowsDesktopIntegration();
    ref.onDispose(integration.dispose);
    return integration;
  }),
  tunServiceGatewayProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    if (!Platform.isLinux || gateway is! DesktopCoreGateway) return null;
    final service = LinuxTunServiceGateway(gateway.executablePath);
    ref.onDispose(() => unawaited(service.close()));
    return service;
  }),
  chainTesterProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    return gateway is ChainTester
        ? gateway as ChainTester
        : const UnavailableChainTester();
  }),
  chainRepositoryProvider.overrideWith(
    (ref) => DriftChainRepository(
      ref.watch(databaseProvider),
      ref.watch(chainTesterProvider),
    ),
  ),
  routeRepositoryProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    return DriftRouteRepository(
      ref.watch(databaseProvider),
      gateway is RouteRuleValidator
          ? gateway as RouteRuleValidator
          : const _UnavailableRuleValidator(),
    );
  }),
  routingResolverProvider.overrideWith(
    (ref) => DriftRoutingResolver(
      ref.watch(databaseProvider),
      ref.watch(routeRepositoryProvider),
    ),
  ),
  trafficRepositoryProvider.overrideWith(
    (ref) => DriftTrafficRepository(ref.watch(databaseProvider)),
  ),
  coreLogRepositoryProvider.overrideWith(
    (ref) => DriftCoreLogRepository(ref.watch(databaseProvider)),
  ),
  nodeRepositoryProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    return DriftNodeRepository(
      ref.watch(databaseProvider),
      gateway is CredentialProtector
          ? gateway as CredentialProtector
          : const _UnavailableProtector(),
    );
  }),
  nodeOverridesRepositoryProvider.overrideWith(
    (ref) => DriftNodeOverridesRepository(ref.watch(databaseProvider)),
  ),
  nodeTesterProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    return gateway is NodeTester
        ? gateway as NodeTester
        : const UnavailableNodeTester();
  }),
  subscriptionFetcherProvider.overrideWith(
    (ref) => HttpSubscriptionFetcher(
      localProxyPort: () {
        final session = ref.read(sessionControllerProvider);
        if (session.working) {
          throw const NodeException('连接正在切换，请稍后更新订阅');
        }
        if (!session.connected) return null;
        final port = session.active?.proxyPort;
        if (port == null || port < 1 || port > 65535) {
          throw const NodeException('当前连接的本地代理端口无效，请重新连接');
        }
        return port;
      },
    ),
  ),
  groupRepositoryProvider.overrideWith((ref) {
    final gateway = ref.watch(coreGatewayProvider);
    return DriftGroupRepository(
      ref.watch(databaseProvider),
      gateway is SecretStore
          ? gateway as SecretStore
          : const _UnavailableProtector(),
      ref.watch(subscriptionFetcherProvider),
    );
  }),
  subscriptionMaintenanceProvider.overrideWith((ref) {
    final maintenance = SubscriptionMaintenance(
      ref.watch(groupRepositoryProvider),
      ref.watch(subscriptionControllerProvider.notifier),
    );
    ref.onDispose(maintenance.pause);
    return maintenance;
  }),
  subscriptionExpiryMonitorProvider.overrideWith((ref) {
    final notifications = ref.watch(appNotificationsProvider);
    if (notifications == null) return null;
    final monitor = SubscriptionExpiryMonitor(
      groups: ref.watch(groupRepositoryProvider),
      store: DriftSubscriptionExpiryStore(ref.watch(databaseProvider)),
      notifications: notifications,
      enabled: () {
        final general = ref.read(deviceSettingsControllerProvider).general;
        return general.subscriptionExpiryNotifications;
      },
      onError:
          (message) =>
              ref.read(subscriptionExpiryErrorProvider.notifier).state =
                  message,
    );
    ref.listen(
      deviceSettingsControllerProvider.select((v) => v.general),
      (previous, next) => unawaited(monitor.checkNow()),
    );
    ref.onDispose(monitor.dispose);
    return monitor;
  }),
  coreGatewayProvider.overrideWith((ref) {
    final CoreGateway gateway;
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      gateway = DesktopCoreGateway();
    } else if (Platform.isAndroid) {
      gateway = AndroidCoreGateway();
    } else {
      gateway = const UnavailableCoreGateway('移动端网络接管尚未接入');
    }
    ref.onDispose(gateway.dispose);
    return gateway;
  }),
];

class _UnavailableRuleValidator implements RouteRuleValidator {
  const _UnavailableRuleValidator();
  @override
  Future<void> validateRules(RouteRuleSet rules) async =>
      throw const RoutingException('当前平台的规则校验尚未接入');
}

class _UnavailableProtector implements SecretStore {
  const _UnavailableProtector();
  @override
  Future<String> protect(
    String nodeId,
    String username,
    String password, {
    String obfsPassword = '',
  }) async => throw const NodeException('当前平台的凭据存储尚未接入');
  @override
  Future<NodeCredentials> reveal(String id, String cipher) async =>
      throw const NodeException('当前平台的凭据存储尚未接入');
}
