import 'dart:async';
import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_accounts/services/install_source_handler.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_components/ente_components.dart' as components;
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_crypto_dart_adapter/ente_crypto_dart_adapter.dart';
import 'package:ente_install_source/ente_install_source.dart';
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_legacy/services/legacy_kit_service.dart";
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_lock_screen/ui/lock_screen.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_network/network.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_rust/ente_rust.dart';
import "package:ente_strings/l10n/strings_localizations.dart";
import "package:ente_ui/theme/theme_config.dart";
import 'package:ente_ui/utils/window_listener_service.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:locker/app.dart';
import 'package:locker/core/locale.dart';
import 'package:locker/l10n/app_localizations.dart';
import 'package:locker/services/collections/collections_api_client.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/configuration.dart';
import "package:locker/services/contacts_display_service.dart";
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/favorites_service.dart';
import 'package:locker/services/files/download/service_locator.dart';
import 'package:locker/services/files/links/links_client.dart';
import 'package:locker/services/files/links/links_service.dart';
import 'package:locker/services/files/offline/offline_files_service.dart';
import 'package:locker/services/local_settings.dart';
import 'package:locker/services/trash/trash_service.dart';
import 'package:locker/services/update_service.dart';
import 'package:locker/ui/pages/home_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger("main");
bool _isRustInitialized = false;
Future<void>? _rustInitFuture;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await rive.RiveNative.init();
  registerCryptoApi(const EnteCryptoDartAdapter());

  if (PlatformDetector.isDesktop()) {
    await windowManager.ensureInitialized();
    await WindowListenerService.instance.init();
    final WindowOptions windowOptions = WindowOptions(
      size: WindowListenerService.instance.getWindowSize(),
      maximumSize: const Size(8192, 8192),
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      _initSystemTray().ignore();
    });
  }

  await _runInForeground();
  if (Platform.isAndroid) {
    FlutterDisplayMode.setHighRefreshRate().ignore();
    // Make the navigation bar transparent so the app theme can take over
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
}

Future<void> _initSystemTray() async {
  if (PlatformDetector.isMobile()) return;
  final String path = Platform.isWindows
      ? 'assets/icons/locker-icon.ico'
      : 'assets/icons/locker-icon.png';
  await trayManager.setIcon(path);
  final Menu menu = Menu(
    items: [
      MenuItem(key: 'hide_window', label: 'Hide Window'),
      MenuItem(key: 'show_window', label: 'Show Window'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: 'Exit App'),
    ],
  );
  await trayManager.setContextMenu(menu);
}

Future<void> _runInForeground() async {
  AppThemeConfig.initialize(EnteApp.locker);
  components.ComponentTheme.configure(app: components.ComponentApp.locker);
  final adaptiveThemeMode = await AdaptiveTheme.getThemeMode();
  final savedThemeMode = _themeMode(adaptiveThemeMode);
  return await _runWithLogs(() async {
    _logger.info("Starting app in foreground");
    try {
      await _ensureRustInitialized();
      await _init(false, via: 'mainMethod');
    } catch (e, s) {
      _logger.severe("Failed to init", e, s);
      rethrow;
    }
    final Locale? locale = await getLocale(noFallback: true);
    runApp(
      AppLock(
        builder: (args) =>
            App(locale: locale, savedThemeMode: adaptiveThemeMode),
        lockScreen: LockScreen(Configuration.instance),
        enabled: await LockScreenSettings.instance.shouldShowLockScreen(),
        locale: locale,
        lightTheme: components.ComponentTheme.themeForApp(
          components.ComponentApp.locker,
          brightness: Brightness.light,
        ),
        darkTheme: components.ComponentTheme.themeForApp(
          components.ComponentApp.locker,
          brightness: Brightness.dark,
        ),
        savedThemeMode: savedThemeMode,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: const [
          ...StringsLocalizations.localizationsDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: localResolutionCallBack,
      ),
    );
  });
}

Future<void> _ensureRustInitialized() async {
  if (_isRustInitialized) {
    return;
  }
  final inFlightInit = _rustInitFuture;
  if (inFlightInit != null) {
    await inFlightInit;
    return;
  }
  final initFuture = EnteRust.init();
  _rustInitFuture = initFuture;
  try {
    await initFuture;
    _isRustInitialized = true;
  } finally {
    _rustInitFuture = null;
  }
}

ThemeMode _themeMode(AdaptiveThemeMode? savedThemeMode) {
  if (savedThemeMode == null) return ThemeMode.system;
  if (savedThemeMode.isLight) return ThemeMode.light;
  if (savedThemeMode.isDark) return ThemeMode.dark;
  return ThemeMode.system;
}

Future _runWithLogs(Function() function, {String prefix = ""}) async {
  String dir = "";
  try {
    dir = "${(await getApplicationSupportDirectory()).path}/logs";
  } catch (_) {}
  await SuperLogging.main(
    LogConfig(
      body: function,
      logDirPath: dir,
      maxLogFiles: 5,
      enableInDebugMode: true,
      prefix: prefix,
    ),
  );
}

Future<void> _init(bool bool, {String? via}) async {
  try {
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    LocalSettings.instance.init(preferences);

    await CryptoUtil.init();

    await LockerDB.instance.init();

    await Configuration.instance.init([LockerDB.instance]);

    await Network.instance.init(Configuration.instance);
    final installSourceService = InstallSourceService(
      Network.instance.enteDio,
      app: Configuration.instance.appIdentity.app,
      getToken: Configuration.instance.getToken,
    );
    await UserService.instance.init(
      Configuration.instance,
      const HomePage(),
      installSourceHandler: InstallSourceHandler(
        hasInstallSource: installSourceService.hasInstallSource,
        autoAttributeSource: installSourceService.autoAttributeSource,
        autoAttributePendingSource:
            installSourceService.autoAttributePendingSource,
      ),
    );
    await LockScreenSettings.instance.init(
      Configuration.instance,
      hideAppContentDefault: true,
    );
    AccountDeletionSettings.instance.init(
      host: Configuration.instance,
      enteDio: Network.instance.enteDio,
    );
    await CollectionApiClient.instance.init();
    await CollectionService.instance.init(preferences);
    await FavoritesService.instance.init();
    await OfflineFilesService.instance.init();
    await LinksClient.instance.init();
    await LinksService.instance.init();
    ServiceLocator.instance.init(
      preferences,
      Network.instance.enteDio,
      Network.instance.getDio(),
      packageInfo,
    );
    await UpdateService.instance.init(preferences, packageInfo);
    await TrashService.instance.init(preferences);
    await EmergencyContactService.instance.init(
      UserService.instance,
      Configuration.instance,
    );
    await LockerContactsDisplayService.init(
      preferences: preferences,
      packageInfo: packageInfo,
    );
    await LegacyKitService.instance.init(
      config: Configuration.instance,
      sessionProvider: LockerContactsDisplayService.buildSession,
    );
    unawaited(
      Future.delayed(
        const Duration(seconds: 5),
        installSourceService.autoAttributePendingSource,
      ),
    );
  } catch (e) {
    _logger.severe("Error during initialization", e);
  }
}
