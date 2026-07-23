import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:ente_auth/services/preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

class WindowListenerService with WindowListener, TrayListener {
  static const double initialWindowHeight = 1200.0;
  static const double initialWindowWidth = 800.0;
  static const bool initialIsMaximized = false;
  static const double maxWindowHeight = 8192.0;
  static const double maxWindowWidth = 8192.0;
  late SharedPreferences _preferences;
  bool _isListening = false;
  bool _isQuitting = false;

  WindowListenerService._privateConstructor();

  static final WindowListenerService instance =
      WindowListenerService._privateConstructor();

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    if (_isListening) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    _isListening = true;
  }

  Size getWindowSize() {
    final double windowWidth =
        _preferences.getDouble('windowWidth') ?? initialWindowWidth;
    final double windowHeight =
        _preferences.getDouble('windowHeight') ?? initialWindowHeight;
    final w = windowWidth.clamp(200.0, maxWindowWidth);
    final h = windowHeight.clamp(400.0, maxWindowHeight);
    return Size(w, h);
  }

  bool getIsMaximized() {
    return _preferences.getBool('is_maximized') ?? initialIsMaximized;
  }

  @override
  void onWindowResize() {
    unawaited(_saveWindowSize());
  }

  Future<void> _saveWindowSize() async {
    final width = (await windowManager.getSize()).width;
    final height = (await windowManager.getSize()).height;
    await _preferences.setDouble('windowWidth', width);
    await _preferences.setDouble('windowHeight', height);
  }

  @override
  void onWindowMaximize() {
    unawaited(_preferences.setBool('is_maximized', true));
  }

  @override
  void onWindowUnmaximize() {
    unawaited(_preferences.setBool('is_maximized', false));
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isWindows) {
      unawaited(_showWindow());
    } else {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isWindows) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      unawaited(_showWindow());
    }
  }

  @override
  void onWindowFocus() {
    if (Platform.isWindows || Platform.isLinux) {
      unawaited(windowManager.setSkipTaskbar(false));
    }
  }

  @override
  void onTrayIconRightMouseUp() {}

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'hide_window':
        unawaited(_hideWindow());
        break;
      case 'show_window':
        unawaited(_showWindow());
        break;
      case 'exit_app':
        unawaited(_quitApp());
        break;
    }
  }

  @override
  void onWindowClose() {
    if (_shouldMinimizeToTrayOnClose()) {
      unawaited(_hideWindow());
    } else {
      unawaited(_quitApp());
    }
  }

  bool _shouldMinimizeToTrayOnClose() {
    return _preferences.getBool(
          PreferenceService.kShouldMinimizeToTrayOnClose,
        ) ??
        false;
  }

  Future<void> _hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.setSkipTaskbar(false);
  }

  Future<void> _quitApp() async {
    if (_isQuitting) return;
    _isQuitting = true;

    if (Platform.isWindows) {
      final int hProcess = GetCurrentProcess();
      try {
        await trayManager.destroy();
      } finally {
        TerminateProcess(hProcess, 0);
      }
      return;
    }

    await windowManager.setPreventClose(false);
    await windowManager.destroy();

    // On Linux, closing via window_manager.destroy() can still segfault during
    // native window teardown. Explicitly exiting here avoids that crash.
    if (Platform.isLinux) {
      exit(0);
    }
  }
}
