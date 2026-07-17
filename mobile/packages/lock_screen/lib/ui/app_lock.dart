import 'dart:async';

import "package:ente_lock_screen/lock_screen_settings.dart";
import 'package:flutter/material.dart';

/// A widget which handles app lifecycle events for showing and hiding a lock screen.
/// This should wrap around a `MyApp` widget (or equivalent).
///
/// [lockScreen] is a [Widget] which should be a screen for handling login logic and
/// calling `AppLock.of(context).didUnlock();` upon a successful login.
///
/// [builder] is a [Function] taking an [Object] as its argument and should return a
/// [Widget]. The [Object] argument is provided by the [lockScreen] calling
/// `AppLock.of(context).didUnlock();` with an argument. [Object] can then be injected
/// in to your `MyApp` widget (or equivalent).
///
/// [enabled] determines wether or not the [lockScreen] should be shown on app launch
/// and subsequent app pauses. This can be changed later on using `AppLock.of(context).enable();`,
/// `AppLock.of(context).disable();` or the convenience method `AppLock.of(context).setEnabled(enabled);`
/// using a bool argument.
///
/// [backgroundLockLatency] determines how much time is allowed to pass when
/// the app is in the background state before the [lockScreen] widget should be
/// shown upon returning. It defaults to instantly.
///

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

  /// Invoked on each successful unlock (launch, resume, or manual).
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
      this._backgroundLockLatencyTimer = Timer(
        Duration(milliseconds: LockScreenSettings.instance.getAutoLockTime()),
        () => this.showLockScreen(),
      );
    }

    if (state == AppLifecycleState.resumed) {
      this._backgroundLockLatencyTimer?.cancel();
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
      home: this.widget.enabled ? this._lockScreen : this.widget.builder(null),
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
              pageBuilder: (_, _, _) => this.widget.builder(settings.arguments),
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

  /// Causes `AppLock` to either pop the [lockScreen] if the app is already running
  /// or instantiates widget returned from the [builder] method if the app is cold
  /// launched.
  ///
  /// [args] is an optional argument which will get passed to the [builder] method
  /// when built. Use this when you want to inject objects created from the
  /// [lockScreen] in to the rest of your app so you can better guarantee that some
  /// objects, services or databases are already instantiated before using them.
  void didUnlock([Object? args]) {
    this.widget.onUnlock?.call();
    if (this._didUnlockForAppLaunch) {
      this._didUnlockOnAppPaused();
    } else {
      this._didUnlockOnAppLaunch(args);
    }
  }

  /// Makes sure that [AppLock] shows the [lockScreen] on subsequent app pauses if
  /// [enabled] is true of makes sure it isn't shown on subsequent app pauses if
  /// [enabled] is false.
  ///
  /// This is a convenience method for calling the [enable] or [disable] method based
  /// on [enabled].
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

  /// Makes sure that [AppLock] shows the [lockScreen] on subsequent app pauses.
  void enable() {
    setState(() {
      this._enabled = true;
    });
  }

  /// Makes sure that [AppLock] doesn't show the [lockScreen] on subsequent app pauses.
  void disable() {
    setState(() {
      this._enabled = false;
    });
  }

  /// Show the [lockScreen] for automatic locking (app launch, background resume).
  Future<void> showLockScreen() {
    this._isLocked = true;
    return _navigatorKey.currentState!.pushNamed(
      '/lock-screen',
      arguments: {"manual": false},
    );
  }

  /// Show the [lockScreen] for user-initiated manual lock (no auto-auth on first frame).
  Future<void> showManualLockScreen() {
    this._isLocked = true;
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
    this._isLocked = false;
    _navigatorKey.currentState!.pop();
  }
}
