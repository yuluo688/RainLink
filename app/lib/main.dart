import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stack_trace/stack_trace.dart' as async_stack;

import 'app/dependencies.dart';
import 'app/rainlink_app.dart';
import 'app/app_licenses.dart';
import 'data/database/open_database.dart';
import 'data/database/app_database.dart';
import 'data/preferences/drift_preferences_repository.dart';
import 'design_system/theme/rainlink_theme.dart';
import 'design_system/widgets/desktop_window_chrome.dart';
import 'platform/window/desktop_window.dart';
import 'platform/window/desktop_session_guard.dart';
import 'platform/updates/windows_update_startup.dart';

Future<void> main([List<String> arguments = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerRainlinkLicenses();
  AppDatabase? initializedDatabase;
  WindowsUpdateStartup? updating;
  try {
    updating = await WindowsUpdateStartup.detect(arguments);
    final database = await openAppDatabase();
    initializedDatabase = database;
    final preferences = DriftPreferencesRepository(database);
    final theme = await preferences.loadTheme();
    final settings = await preferences.loadDeviceSettings();
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      settings.general.validatedForDesktop();
    }
    await initializeDesktopWindow();
    final startupReady = Completer<void>();
    if (updating == null) startupReady.complete();
    Object? initialFrameError;
    final previousErrorHandler = FlutterError.onError;
    if (updating != null) {
      FlutterError.onError = (details) {
        initialFrameError ??= details.exception;
        previousErrorHandler?.call(details);
      };
    }
    runApp(ProviderScope(
      overrides: createAppOverrides(
          database: database,
          initialTheme: theme,
          initialSettings: settings,
          startupReady: startupReady.future),
      child: const DesktopSessionGuard(child: RainlinkApp()),
    ));
    if (updating != null) {
      final update = updating;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          if (initialFrameError != null) {
            throw StateError(
                'The candidate failed to render its initial frame');
          }
          await update.acknowledge();
          FlutterError.onError = previousErrorHandler;
          startupReady.complete();
        } on Object catch (error, stack) {
          await reportBootstrapFailure(error, stack,
              closeDatabase: database.close);
          exit(1);
        }
      });
    }
  } on Object catch (error, stackTrace) {
    await reportBootstrapFailure(error, stackTrace,
        closeDatabase: initializedDatabase?.close);
    if (updating != null ||
        arguments.any((arg) => arg.startsWith('--rainlink-update-'))) {
      exit(1);
    }
    runApp(MaterialApp(
      title: 'RainLink',
      debugShowCheckedModeBanner: false,
      theme: buildRainlinkTheme(Brightness.dark),
      home: Scaffold(
        body: Column(children: [
          if (usesCustomWindowChrome)
            const SizedBox(
              height: desktopHeaderHeight,
              child: Row(children: [
                Expanded(
                  child: DesktopWindowDragArea(
                    child: Padding(
                      padding: EdgeInsets.only(left: 20),
                      child: Text('RainLink'),
                    ),
                  ),
                ),
                DesktopWindowControls(),
              ]),
            ),
          const Expanded(
              child: Center(
                  child: Padding(
            padding: EdgeInsets.all(32),
            child: Text('RainLink 启动失败，无法初始化本地设置或窗口。\n请检查磁盘与应用权限后重新启动。',
                textAlign: TextAlign.center),
          ))),
        ]),
      ),
    ));
  }
}

Future<void> reportBootstrapFailure(Object error, StackTrace stackTrace,
    {Future<void> Function()? closeDatabase}) async {
  FlutterError.reportError(FlutterErrorDetails(
    exception: error,
    stack: _frameworkStack(stackTrace),
    library: 'RainLink bootstrap',
  ));
  try {
    await closeDatabase?.call();
  } on Object catch (cleanupError, cleanupStack) {
    // A secondary cleanup failure must not hide the startup error or fallback UI.
    FlutterError.reportError(FlutterErrorDetails(
      exception: cleanupError,
      stack: _frameworkStack(cleanupStack),
      library: 'RainLink bootstrap cleanup',
    ));
  }
}

// Drift can attach package:stack_trace chains outside a Flutter test binding.
// Normalize their frames before Flutter's error renderer parses the stack, so
// reporting the original failure cannot itself interrupt database cleanup.
StackTrace _frameworkStack(StackTrace stack) => switch (stack) {
      async_stack.Chain chain => chain.toTrace().vmTrace,
      async_stack.Trace trace => trace.vmTrace,
      _ => stack,
    };
