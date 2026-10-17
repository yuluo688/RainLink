import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/platform/app_notifications.dart';
import '../../domain/platform/mobile_integration.dart';
import 'desktop_integration_controller.dart';

final mobileIntegrationProvider = Provider<MobileIntegration?>((ref) => null);
final appNotificationsProvider = Provider<AppNotifications?>((ref) =>
    ref.watch(mobileIntegrationProvider) ??
    ref.watch(desktopIntegrationProvider));
final mobileNotificationStatusProvider =
    FutureProvider<MobileNotificationStatus?>(
        (ref) => ref.watch(mobileIntegrationProvider)?.inspectNotifications());
