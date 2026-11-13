import 'dart:async';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_components/ente_components.dart' as components;
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_in_event.dart';
import 'package:ente_events/models/signed_out_event.dart';
import 'package:ente_strings/ente_strings.dart';
import "package:flutter/material.dart";
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:locker/core/locale.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/contacts_display_service.dart';
import "package:locker/services/update_service.dart";
import 'package:locker/ui/pages/home_page.dart';
import 'package:locker/ui/pages/onboarding_page.dart';
import "package:locker/ui/settings/app_update_sheet.dart";
import "package:locker/ui/settings/widgets/change_log_sheet.dart";

class App extends StatefulWidget {
  final Locale? locale;
  final AdaptiveThemeMode? savedThemeMode;

  const App({super.key, this.locale = const Locale("en"), this.savedThemeMode});

  static void setLocale(BuildContext context, Locale newLocale) {
    final _AppState state = context.findAncestorStateOfType<_AppState>()!;
    state.setLocale(newLocale);
  }

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  late StreamSubscription<SignedOutEvent> _signedOutEvent;
  late StreamSubscription<SignedInEvent> _signedInEvent;
  Locale? locale;
  void setLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);

    if (Configuration.instance.hasConfiguredAccount()) {
      LockerContactsDisplayService.scheduleEnsureReady();
    }

    _signedOutEvent = Bus.instance.on<SignedOutEvent>().listen((event) {
      LockerContactsDisplayService.scheduleResetLocalState();
      if (mounted) {
        setState(() {});
      }
    });
    _signedInEvent = Bus.instance.on<SignedInEvent>().listen((event) {
      UserService.instance.getUserDetailsV2().ignore();
      LockerContactsDisplayService.scheduleEnsureReady();
      if (mounted) {
        setState(() {});
      }
      unawaited(_showChangeLogIfNeeded());
    });
    locale = widget.locale;
    unawaited(_runStartupPrompts());
    super.initState();
  }

  Future<void> _runStartupPrompts() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    final didShowUpdatePrompt = await _checkForAppUpdates();
    if (!mounted || didShowUpdatePrompt) {
      return;
    }
    await _showChangeLogIfNeeded();
  }

  Future<bool> _checkForAppUpdates() async {
    final shouldShow = await UpdateService.instance
        .shouldShowUpdateNotification();
    if (!shouldShow || !mounted) {
      return false;
    }

    final latestVersion = UpdateService.instance.getLatestVersionInfo();
    if (latestVersion == null) {
      return false;
    }

    await showAppUpdateSheet(context, latestVersionInfo: latestVersion);
    await UpdateService.instance.markUpdateNotificationShown();
    return true;
  }

  Future<void> _showChangeLogIfNeeded() async {
    if (!mounted || !Configuration.instance.hasConfiguredAccount()) {
      return;
    }
    final shouldShow = await UpdateService.instance.shouldShowChangeLog();
    if (!shouldShow || !mounted) {
      return;
    }
    await showChangeLogSheet(context);
    await UpdateService.instance.markChangeLogShown();
  }

  @override
  void dispose() {
    super.dispose();
    _signedOutEvent.cancel();
    _signedInEvent.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Configuration.instance.hasConfiguredAccount()) {
        CollectionService.instance.sync();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget buildApp() {
      return AdaptiveTheme(
        light: components.ComponentTheme.themeForApp(
          components.ComponentApp.locker,
          brightness: Brightness.light,
        ),
        dark: components.ComponentTheme.themeForApp(
          components.ComponentApp.locker,
          brightness: Brightness.dark,
        ),
        initial: widget.savedThemeMode ?? AdaptiveThemeMode.system,
        builder: (lightTheme, dartTheme) => MaterialApp(
          title: "ente",
          themeMode: ThemeMode.system,
          theme: lightTheme,
          darkTheme: dartTheme,
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: appSupportedLocales,
          localeListResolutionCallback: localResolutionCallBack,
          localizationsDelegates: const [
            StringsLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          routes: _getRoutes,
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(
      minScaleFactor: 0.8,
      maxScaleFactor: 1.3,
      child: buildApp(),
    );
  }

  Map<String, WidgetBuilder> get _getRoutes {
    return {
      "/": (context) => Configuration.instance.hasConfiguredAccount()
          ? const HomePage()
          : const OnboardingPage(),
    };
  }
}
