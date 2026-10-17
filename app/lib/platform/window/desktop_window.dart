import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

const _windowCommandTimeout = Duration(seconds: 5);
const _compactWindowSize = Size(960, 640);
const _workAreaMargin = 48.0;

// macOS keeps its native traffic lights; mobile never requests desktop channels.
bool get usesCustomWindowChrome =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

bool get supportsDesktopWindowMenu =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

// Native modal loops finish when the user releases the drag or dismisses the
// menu (including Escape); a command timeout would reject valid long gestures.
Future<void> dragDesktopWindow() => windowManager.startDragging();

Future<void> showDesktopWindowMenu() => windowManager.popUpWindowMenu();

Future<void> toggleDesktopWindowMaximized() async {
  final maximized =
      await windowManager.isMaximized().timeout(_windowCommandTimeout);
  if (maximized) {
    await windowManager.unmaximize().timeout(_windowCommandTimeout);
  } else {
    await windowManager.maximize().timeout(_windowCommandTimeout);
  }
}

/// Tracks native changes, including maximize/restore through system shortcuts.
class DesktopWindowController extends ChangeNotifier with WindowListener {
  bool _disposed = false;
  bool _maximized = false;
  bool _focused = true;

  bool get maximized => _maximized;
  bool get focused => _focused;

  Future<void> initialize() async {
    windowManager.addListener(this);
    final state = await Future.wait([
      windowManager.isMaximized(),
      windowManager.isFocused(),
    ]).timeout(_windowCommandTimeout);
    if (_disposed) return;
    _maximized = state[0];
    _focused = state[1];
    notifyListeners();
  }

  Future<void> minimize() =>
      windowManager.minimize().timeout(_windowCommandTimeout);

  Future<void> toggleMaximized() => toggleDesktopWindowMaximized();

  Future<void> close() => windowManager.close().timeout(_windowCommandTimeout);

  @override
  void onWindowMaximize() {
    _maximized = true;
    notifyListeners();
  }

  @override
  void onWindowUnmaximize() {
    _maximized = false;
    notifyListeners();
  }

  @override
  void onWindowFocus() {
    _focused = true;
    notifyListeners();
  }

  @override
  void onWindowBlur() {
    _focused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    windowManager.removeListener(this);
    super.dispose();
  }
}

Future<void> initializeDesktopWindow() async {
  if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
  await windowManager.ensureInitialized();
  final display = await screenRetriever.getPrimaryDisplay();
  final workArea = display.visibleSize ?? display.size;
  // Open with the compact layout and leave room for chrome and the taskbar.
  final initialSize = Size(
    math.min(_compactWindowSize.width, workArea.width - _workAreaMargin),
    math.min(_compactWindowSize.height, workArea.height - _workAreaMargin),
  );
  await windowManager.waitUntilReadyToShow(WindowOptions(
    title: 'RainLink',
    size: initialSize,
    minimumSize: initialSize,
    center: true,
    backgroundColor: Color(0xFF0F1011),
    titleBarStyle:
        usesCustomWindowChrome ? TitleBarStyle.hidden : TitleBarStyle.normal,
    windowButtonVisibility: !usesCustomWindowChrome,
  ));
  await windowManager.show();
  await windowManager.focus();
}
