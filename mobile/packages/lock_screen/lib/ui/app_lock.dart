import 'dart:async';

import "package:ente_lock_screen/lock_screen_settings.dart";
import 'package:flutter/material.dart';

@visibleForTesting
const appLockContentObscurerKey = ValueKey('app_lock_content_obscurer');

// ignore_for_file: unnecessary_this, library_private_types_in_public_api
class AppLock extends StatefulWidget {
  final Widget Function(Object?) builder;
  final Widget lockScreen;
  final bool enabled;
  final Duration backgroundLockLatency;
  final ThemeData? darkTheme;
  final ThemeData? lightTheme;
  final ThemeMode savedThemeMode;
  final Locale? locale;
  final List<Locale>? supportedLocales;
  final List<LocalizationsDelegate<dynamic>> localizationsDelegates;
  final LocaleListResolutionCallback? localeListResolutionCallback;
  final bool debugShowCheckedModeBanner;

  final VoidCallback? onUnlock;

  const AppLock({
    super.key,
    required this.builder,
    required this.lockScreen,
    required this.savedThemeMode,
    required this.supportedLocales,
    required this.localizationsDelegates,
    required this.localeListResolutionCallback,
    this.debugShowCheckedModeBanner = true,
    this.enabled = true,
    this.locale,
    this.backgroundLockLatency = const Duration(seconds: 0),
    this.darkTheme,
    this.lightTheme,
    this.onUnlock,
  });

  static _AppLockState? of(BuildContext context) =>
      context.findAncestorStateOfType<_AppLockState>();

  @override
  State<AppLock> createState() => _AppLockState();
}

class _AppLockState extends State<AppLock> with WidgetsBindingObserver {
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey();

  late bool _didUnlockForAppLaunch;
  late bool _isLocked;
  late bool _enabled;
  late ThemeMode _themeMode;
  int? _backgroundedAt;

  Timer? _backgroundLockLatencyTimer;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    this._didUnlockForAppLaunch = !this.widget.enabled;
    this._isLocked = false;
    this._enabled = this.widget.enabled;
    this._themeMode = this.widget.savedThemeMode;
  }

  @override
  void didUpdateWidget(covariant AppLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.savedThemeMode != this.widget.savedThemeMode) {
      this._themeMode = this.widget.savedThemeMode;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!this._enabled) {
      return;
    }

    if (state == AppLifecycleState.paused &&
        (!this._isLocked && this._didUnlockForAppLaunch)) {
      this._backgroundedAt = DateTime.now().millisecondsSinceEpoch;
      this._setLocked(true);
      this._backgroundLockLatencyTimer = Timer(
        Duration(milliseconds: LockScreenSettings.instance.getAutoLockTime()),
        () {
          this._backgroundedAt = null;
          unawaited(this.showLockScreen());
        },
      );
    }

    if (state == AppLifecycleState.resumed) {
      this._backgroundLockLatencyTimer?.cancel();
      final int? backgroundedAt = this._backgroundedAt;
      this._backgroundedAt = null;

      if (backgroundedAt != null) {
        final int elapsed =
            DateTime.now().millisecondsSinceEpoch - backgroundedAt;
        if (elapsed >= LockScreenSettings.instance.getAutoLockTime()) {
          unawaited(this.showLockScreen());
        } else {
          this._setLocked(false);
        }
      }
    }

    super.didChangeAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    this._backgroundLockLatencyTimer?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: widget.debugShowCheckedModeBanner,
      home: this.widget.enabled
          ? this._lockScreen
          : this._unlockedContent(null),
      navigatorKey: _navigatorKey,
      themeMode: this._themeMode,
      theme: widget.lightTheme,
      darkTheme: widget.darkTheme,
      locale: widget.locale,
      supportedLocales:
          widget.supportedLocales ?? const <Locale>[Locale('en', 'US')],
      localeListResolutionCallback: widget.localeListResolutionCallback,
      localizationsDelegates: widget.localizationsDelegates,
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/lock-screen':
            return PageRouteBuilder(
              pageBuilder: (_, _, _) => this._lockScreen,
              settings: settings,
            );
          case '/unlocked':
            return PageRouteBuilder(
              pageBuilder: (_, _, _) =>
                  this._unlockedContent(settings.arguments),
              settings: settings,
            );
        }
        return null;
      },
    );
  }

  Widget get _lockScreen {
    return PopScope(canPop: false, child: this.widget.lockScreen);
  }

  Widget _unlockedContent(Object? args) {
    return Stack(
      fit: StackFit.expand,
      children: [
        this.widget.builder(args),
        if (this._isLocked)
          Positioned.fill(
            key: appLockContentObscurerKey,
            child: AbsorbPointer(
              child: Builder(
                builder: (context) => ColoredBox(
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
              ),
            ),
          ),
      ],
    );
  }

  void didUnlock([Object? args]) {
    this.widget.onUnlock?.call();
    if (this._didUnlockForAppLaunch) {
      this._didUnlockOnAppPaused();
    } else {
      this._didUnlockOnAppLaunch(args);
    }
  }

  void setEnabled(bool enabled) {
    if (enabled) {
      this.enable();
    } else {
      this.disable();
    }
  }

  void setThemeMode(ThemeMode themeMode) {
    if (this._themeMode == themeMode) {
      return;
    }
    setState(() {
      this._themeMode = themeMode;
    });
  }

  void enable() {
    setState(() {
      this._enabled = true;
    });
  }

  void disable() {
    setState(() {
      this._enabled = false;
    });
  }

  Future<void> showLockScreen() {
    this._setLocked(true);
    return _navigatorKey.currentState!.pushNamed(
      '/lock-screen',
      arguments: {"manual": false},
    );
  }

  // Manual lock must not auto-authenticate on its first frame.
  Future<void> showManualLockScreen() {
    this._setLocked(true);
    return _navigatorKey.currentState!.pushNamed(
      '/lock-screen',
      arguments: {"manual": true},
    );
  }

  void _didUnlockOnAppLaunch(Object? args) {
    this._didUnlockForAppLaunch = true;
    _navigatorKey.currentState!.pushReplacementNamed(
      '/unlocked',
      arguments: args,
    );
  }

  void _didUnlockOnAppPaused() {
    this._setLocked(false);
    _navigatorKey.currentState!.pop();
  }

  void _setLocked(bool locked) {
    if (this._isLocked == locked) {
      return;
    }
    if (!mounted) {
      this._isLocked = locked;
      return;
    }
    setState(() {
      this._isLocked = locked;
    });
  }
}
