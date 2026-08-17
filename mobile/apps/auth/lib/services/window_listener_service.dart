import 'dart:async';
import 'dart:io';

import 'package:ente_auth/services/preference_service.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

class WindowListenerService with WindowListener, TrayListener {
  static const double initialWindowHeight = 1200.0;
  static const double initialWindowWidth = 800.0;
  static const double menubarPopoverWidth = 380.0;
  static const double menubarPopoverHeight = 600.0;
  static const bool initialIsMaximized = false;
  static const double maxWindowHeight = 8192.0;
  static const double maxWindowWidth = 8192.0;
  late SharedPreferences _preferences;
  bool _isListening = false;
  bool _isQuitting = false;
  bool _isOneOffWindowed = false;
  bool _launchMenubarMode = false;

  bool get isOneOffWindowed => _isOneOffWindowed;

  WindowListenerService._privateConstructor();

  static final WindowListenerService instance =
      WindowListenerService._privateConstructor();

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    // Snapshot at launch: toggling the setting mid-session persists the pref
    // but must not reroute window behavior until restart, since the
    // startup-only window setup (title bar, size, activation policy) only
    // runs for the mode active at launch.
    _launchMenubarMode =
        Platform.isMacOS &&
        (_preferences.getBool(PreferenceService.kMenubarMode) ?? false);
    if (_isListening) return;
    windowManager.addListener(this);
    trayManager.addListener(this);
    _isListening = true;
  }

  bool isMenubarMode() {
    return _launchMenubarMode;
  }

  Size getWindowSize() {
    if (isMenubarMode()) {
      return const Size(menubarPopoverWidth, menubarPopoverHeight);
    }
    return _savedWindowSize();
  }

  Size _savedWindowSize() {
    final double windowWidth =
        _preferences.getDouble('windowWidth') ?? initialWindowWidth;
    final double windowHeight =
        _preferences.getDouble('windowHeight') ?? initialWindowHeight;
    final w = windowWidth.clamp(200.0, maxWindowWidth);
    final h = windowHeight.clamp(400.0, maxWindowHeight);
    return Size(w, h);
  }

  bool getIsMaximized() {
    if (isMenubarMode()) return false;
    return _preferences.getBool('is_maximized') ?? initialIsMaximized;
  }

  @override
  void onWindowResize() {
    if (isMenubarMode() && !_isOneOffWindowed) return;
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
    } else if (isMenubarMode()) {
      unawaited(_togglePopover());
    } else {
      unawaited(trayManager.popUpContextMenu());
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    if (Platform.isWindows || isMenubarMode()) {
      unawaited(trayManager.popUpContextMenu());
    } else {
      unawaited(_showWindow());
    }
  }

  Future<void> _togglePopover() async {
    if (await windowManager.isVisible()) {
      await _hideWindow();
    } else {
      await _positionAndShowPopover();
    }
  }

  Future<void> _positionAndShowPopover() async {
    const w = menubarPopoverWidth;
    const h = menubarPopoverHeight;
    // The status item is mirrored on every display's menubar, but
    // trayManager.getBounds() reports a single static instance, so the click
    // display has to come from the cursor position.
    Offset? cursor;
    List<Display> displays = const [];
    try {
      displays = await screenRetriever.getAllDisplays();
      final raw = await screenRetriever.getCursorScreenPoint();
      cursor = Offset(raw.dx, raw.dy + _cursorYCorrection(displays));
    } catch (_) {}
    final tray = await trayManager.getBounds();
    final anchor = cursor ?? tray?.center;
    if (anchor != null) {
      final displayBounds = _nearestDisplayBounds(anchor, displays);
      final trayOnSameDisplay =
          tray != null &&
          displayBounds != null &&
          _nearestDisplayBounds(tray.center, displays) == displayBounds;
      double x = (trayOnSameDisplay ? tray.center.dx : anchor.dx) - w / 2;
      final double y = trayOnSameDisplay
          ? tray.bottom + 4
          : (displayBounds?.top ?? 0) + 4;
      if (displayBounds != null) {
        x = x.clamp(displayBounds.left + 8.0, displayBounds.right - w - 8.0);
      }
      await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
    }
    await windowManager.show();
  }

  // screen_retriever's macOS getCursorScreenPoint flips y against the lowest
  // display top instead of the primary display top, a constant offset equal
  // to the lowest top's y in top-left coordinates. Reconstruct it from the
  // display list (frame top = visible top minus the menu bar strip).
  double _cursorYCorrection(List<Display> displays) {
    double lowestFrameTop = 0;
    for (final display in displays) {
      final visibleTop = display.visiblePosition?.dy;
      final visibleHeight = display.visibleSize?.height;
      if (visibleTop == null || visibleHeight == null) continue;
      final frameTop = visibleTop - (display.size.height - visibleHeight);
      if (frameTop > lowestFrameTop) lowestFrameTop = frameTop;
    }
    return lowestFrameTop;
  }

  // Nearest display by distance to its visible bounds, in both axes. The
  // visible rect excludes the menu bar and Dock strips, so a menubar click
  // is slightly outside every rect; nearest-rect matching absorbs that
  // without needing the exact strip sizes.
  Rect? _nearestDisplayBounds(Offset point, List<Display> displays) {
    Rect? best;
    double bestDistance = double.infinity;
    for (final display in displays) {
      final position = display.visiblePosition;
      final size = display.visibleSize ?? display.size;
      if (position == null) continue;
      final bounds = Rect.fromLTWH(
        position.dx,
        position.dy,
        size.width,
        size.height,
      );
      final dx = point.dx < bounds.left
          ? bounds.left - point.dx
          : (point.dx > bounds.right ? point.dx - bounds.right : 0.0);
      final dy = point.dy < bounds.top
          ? bounds.top - point.dy
          : (point.dy > bounds.bottom ? point.dy - bounds.bottom : 0.0);
      final distance = dx * dx + dy * dy;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = bounds;
      }
    }
    return best;
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
  void onWindowBlur() {
    if (!isMenubarMode() || _isOneOffWindowed || _isQuitting) return;
    // A sheet of our own app (e.g. the file picker) also takes key status;
    // only hide when focus actually moved to another app.
    Future.delayed(const Duration(milliseconds: 150), () async {
      if (_isQuitting) return;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
      await _hideWindow();
    });
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'hide_window':
        unawaited(_hideWindow());
        break;
      case 'show_window':
        unawaited(isMenubarMode() ? _showAsWindow() : _showWindow());
        break;
      case 'exit_app':
        unawaited(_quitApp());
        break;
    }
  }

  @override
  void onWindowClose() {
    if (isMenubarMode() || _shouldMinimizeToTrayOnClose()) {
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
    if (isMenubarMode()) {
      if (_isOneOffWindowed) {
        await _applyPopoverWindowStyle();
      }
      return;
    }
    await windowManager.setSkipTaskbar(true);
  }

  // One-off regular window from the tray menu, for when the popover is not
  // enough. Hiding it restores the popover style.
  Future<void> _showAsWindow() async {
    _isOneOffWindowed = true;
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setVisibleOnAllWorkspaces(
      false,
      visibleOnFullScreen: false,
    );
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setMinimumSize(const Size(200, 400));
    await windowManager.setMaximumSize(
      const Size(maxWindowWidth, maxWindowHeight),
    );
    await windowManager.setResizable(true);
    await windowManager.setSize(_savedWindowSize());
    await windowManager.center();
    await windowManager.show();
  }

  Future<void> _applyPopoverWindowStyle() async {
    _isOneOffWindowed = false;
    const popoverSize = Size(menubarPopoverWidth, menubarPopoverHeight);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(popoverSize);
    await windowManager.setMaximumSize(popoverSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setVisibleOnAllWorkspaces(
      true,
      visibleOnFullScreen: true,
    );
  }

  Future<void> _showWindow() async {
    if (isMenubarMode()) {
      // setSkipTaskbar(false) on macOS resets activation policy to .regular
      // and brings the dock icon back.
      await _positionAndShowPopover();
      return;
    }
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
