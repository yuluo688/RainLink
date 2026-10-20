import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/preferences/theme_controller.dart';
import '../application/preferences/device_settings_controller.dart';
import '../application/preferences/desktop_integration_controller.dart';
import '../application/groups/group_providers.dart';
import '../application/groups/subscription_expiry_monitor.dart';
import '../application/telemetry/core_log_collector.dart';
import '../application/connection/session_controller.dart';
import '../application/connection/connection_providers.dart';
import '../application/connection/mobile_startup_controller.dart';
import '../application/preferences/mobile_integration_controller.dart';
import '../domain/platform/mobile_integration.dart';
import '../design_system/theme/rainlink_theme.dart';
import '../design_system/layout/app_layout.dart';
import '../domain/preferences/app_preferences.dart';
import '../domain/preferences/device_settings.dart';
import '../domain/platform/desktop_integration.dart';
import '../application/updates/app_update_controller.dart';
import '../domain/updates/app_update.dart';
import '../domain/connection/connection_models.dart';
import 'router.dart';

class RainlinkApp extends ConsumerStatefulWidget {
  const RainlinkApp({this.router, super.key});
  final GoRouter? router;

  @override
  ConsumerState<RainlinkApp> createState() => _RainlinkAppState();
}

class _RainlinkAppState extends ConsumerState<RainlinkApp>
    with WidgetsBindingObserver {
  // Cache for this app instance; ThemeData captures its native platform.
  late final _lightThemes = {
    for (final density in AppDensity.values)
      density: buildRainlinkTheme(Brightness.light, density: density),
  };
  late final _darkThemes = {
    for (final density in AppDensity.values)
      density: buildRainlinkTheme(Brightness.dark, density: density),
  };
  late final bool _ownsRouter;
  late final GoRouter _router;
  late final SubscriptionMaintenance? _maintenance;
  late final SubscriptionExpiryMonitor? _expiryMonitor;
  late final CoreLogCollector _logCollector;
  late final SessionController _session;
  late final MobileStartupController _mobileStartup;
  StreamSubscription<DesktopAction>? _desktopActions;
  StreamSubscription<MobileAction>? _mobileActions;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  bool _servicesStarted = false;
  bool _notificationsReady = false;
  bool _handingOffUpdate = false;
  void Function()? _detachUpdateHandoff;

  @override
  void initState() {
    super.initState();
    // Capture ownership at creation, independently of later widget updates.
    _ownsRouter = widget.router == null;
    _router = widget.router ?? createRouter();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_startServices());
      }
    });
    // The window guard lives above MaterialApp. Route with the owned router,
    // rather than looking up a GoRouter from that ancestor's BuildContext.
    _desktopActions = ref.read(desktopIntegrationProvider)?.actions.listen((
      action,
    ) {
      if (mounted && action == DesktopAction.showGroups) _router.go('/groups');
    });
    final mobile = ref.read(mobileIntegrationProvider);
    _notificationsReady = mobile == null;
    if (mobile != null) {
      _mobileActions = mobile.actions.listen(
        (action) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _router.go(
                action == MobileAction.groups ? '/groups' : '/overview',
              );
            }
          });
          WidgetsBinding.instance.scheduleFrame();
        },
        onError:
            (Object error, StackTrace stack) => _notice('无法打开通知对应的页面，请从底部导航进入'),
      );
      ref.listenManual(proxyModeProvider, (previous, next) {
        if (previous == next) return;
        unawaited(
          ref
              .read(deviceSettingsControllerProvider.notifier)
              .saveConnection(mode: next)
              .catchError((Object error, StackTrace stack) {
                _notice('代理模式已生效，但下次启动的偏好未能保存。');
              }),
        );
      });
    }
    WidgetsBinding.instance.addObserver(this);
    _session = ref.read(sessionControllerProvider.notifier);
    _mobileStartup = ref.read(mobileStartupControllerProvider);
    _maintenance = ref.read(subscriptionMaintenanceProvider);
    _expiryMonitor = ref.read(subscriptionExpiryMonitorProvider);
    _logCollector = ref.read(coreLogCollectorProvider.notifier);
    if (ref.read(updateInstallationModeProvider) ==
        UpdateInstallationMode.androidInstaller) {
      _detachUpdateHandoff = ref
          .read(updateShutdownProvider)
          .attach(_installAndroidUpdate);
    }
    ref.listenManual(desktopIntegrationNoticeProvider, (previous, message) {
      if (message == null || message.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _messenger.currentState?.showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      });
    });
  }

  Future<void> _startServices() async {
    await ref.read(startupReadyProvider);
    if (!mounted || _servicesStarted) return;
    _servicesStarted = true;
    _session.setObserving(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
    _maintenance?.resume();
    if (_notificationsReady) _expiryMonitor?.resume();
    _logCollector.resume();
    await ref.read(appUpdateControllerProvider.notifier).start();
    if (!mounted) return;
    try {
      await _mobileStartup.start(
        isForeground:
            () =>
                mounted &&
                (WidgetsBinding.instance.lifecycleState == null ||
                    WidgetsBinding.instance.lifecycleState ==
                        AppLifecycleState.resumed),
      );
    } on Exception {
      _notice('自动连接或系统通知初始化未完成，请在概览和通用设置中检查');
    } finally {
      _notificationsReady = true;
      if (mounted &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        _expiryMonitor?.resume();
      }
    }
  }

  void _notice(String message) {
    if (mounted) {
      ref.read(desktopIntegrationNoticeProvider.notifier).state = message;
    }
  }

  Future<void> _installAndroidUpdate(PreparedUpdate update) async {
    if (!mounted || _handingOffUpdate) throw const UpdateException('当前安装尚未结束');
    setState(() => _handingOffUpdate = true);
    ref.read(connectionUpdateHoldProvider.notifier).state = true;
    final subscriptions = ref.read(subscriptionControllerProvider.notifier);
    try {
      _maintenance?.pause();
      _expiryMonitor?.pause();
      await _session.initialized;
      await _session.disconnect();
      if (!mounted ||
          ref.read(sessionControllerProvider).phase != ConnectionPhase.idle) {
        throw const UpdateException('连接尚未完全断开，请先在概览恢复网络后重试');
      }
      await subscriptions.suspend();
      await _maintenance?.suspend();
      await _expiryMonitor?.suspend();
      await _logCollector.suspend();
      await ref.read(deviceSettingsControllerProvider.notifier).flush();
      if (!mounted) throw const UpdateCancelled();
      await update.commit();
    } finally {
      subscriptions.resume();
      if (mounted) {
        ref.read(connectionUpdateHoldProvider.notifier).state = false;
        setState(() => _handingOffUpdate = false);
        final state = WidgetsBinding.instance.lifecycleState;
        if (state == null || state == AppLifecycleState.resumed) {
          _maintenance?.resume();
          if (_notificationsReady) _expiryMonitor?.resume();
          _logCollector.resume();
        }
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_servicesStarted) {
      _session.setObserving(state == AppLifecycleState.resumed);
    }
    if (state == AppLifecycleState.resumed && _servicesStarted) {
      if (ref.read(mobileIntegrationProvider) != null) {
        ref.invalidate(mobileNotificationStatusProvider);
      }
      if (!_handingOffUpdate) {
        _maintenance?.resume();
        if (_notificationsReady) _expiryMonitor?.resume();
        _logCollector.resume();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _maintenance?.pause();
      _expiryMonitor?.pause();
      _logCollector.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachUpdateHandoff?.call();
    unawaited(_desktopActions?.cancel());
    unawaited(_mobileActions?.cancel());
    _mobileStartup.dispose();
    _session.setObserving(false);
    _maintenance?.pause();
    _expiryMonitor?.pause();
    _logCollector.pause();
    if (_ownsRouter) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeControllerProvider);
    final appearance = ref.watch(
      deviceSettingsControllerProvider.select((v) => v.appearance),
    );
    return MaterialApp.router(
      title: 'RainLink',
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _lightThemes[appearance.density],
      darkTheme: _darkThemes[appearance.density],
      themeMode: switch (theme) {
        AppTheme.system => ThemeMode.system,
        AppTheme.dark => ThemeMode.dark,
        AppTheme.light => ThemeMode.light,
      },
      themeAnimationDuration:
          appearance.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 180),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final content = MediaQuery(
          data: media.copyWith(
            textScaler: _SettingsTextScaler(
              media.textScaler,
              appearance.textSize.scale,
            ),
            disableAnimations:
                media.disableAnimations || appearance.reduceMotion,
          ),
          child: AbsorbPointer(
            absorbing: _handingOffUpdate,
            child: child ?? const SizedBox.shrink(),
          ),
        );
        if (AppLayout.current != AppLayout.mobile) return content;
        // Custom headers have no AppBar to set system-bar contrast. Follow the
        // rendered theme so light mode never leaves white icons on white.
        final theme = Theme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          key: const ValueKey('mobile-system-bars'),
          value: (theme.brightness == Brightness.dark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark)
              .copyWith(
                statusBarColor: Colors.transparent,
                systemNavigationBarColor: theme.scaffoldBackgroundColor,
                systemNavigationBarDividerColor: Colors.transparent,
                systemNavigationBarIconBrightness:
                    theme.brightness == Brightness.dark
                        ? Brightness.light
                        : Brightness.dark,
              ),
          child: content,
        );
      },
      routerConfig: _router,
    );
  }
}

class _SettingsTextScaler extends TextScaler {
  const _SettingsTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is _SettingsTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
