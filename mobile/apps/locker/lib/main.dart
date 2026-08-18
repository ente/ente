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
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/theme/theme_config.dart";
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:locker/app.dart';
import 'package:locker/core/locale.dart';
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
import 'package:locker/services/frb_legacy_kit_rust_api.dart';
import 'package:locker/services/local_settings.dart';
import 'package:locker/services/trash/trash_service.dart';
import 'package:locker/services/update_service.dart';
import 'package:locker/src/rust/api/log.dart';
import 'package:locker/src/rust/frb_generated.dart';
import 'package:locker/ui/pages/home_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rive;
import 'package:shared_preferences/shared_preferences.dart';

final _logger = Logger("main");
bool _isRustInitialized = false;
Future<void>? _rustInitFuture;
late final LogSinkGuard _rustLogSinkGuard;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await rive.RiveNative.init();
  registerCryptoApi(const EnteCryptoDartAdapter());

  await _runInForeground();
  if (Platform.isAndroid) {
    FlutterDisplayMode.setHighRefreshRate().ignore();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Color(0x00000000),
        systemNavigationBarContrastEnforced: false,
      ),
    );
  }
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
  final initFuture = EnteLockerRust.init();
  _rustInitFuture = initFuture;
  try {
    await initFuture;
    _isRustInitialized = true;
    _attachRustLogStream();
  } finally {
    _rustInitFuture = null;
  }
}

void _attachRustLogStream() {
  final logger = Logger("rust");
  _rustLogSinkGuard = LogSinkGuard();
  _rustLogSinkGuard.attachLogStream().listen((entry) {
    final message = "[${entry.target}] ${entry.message}";
    switch (entry.level) {
      case LogLevel.error:
        logger.severe(message);
      case LogLevel.warn:
        logger.warning(message);
      case LogLevel.info:
        logger.info(message);
    }
  });
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
      rustApi: const FrbLegacyKitRustApi(),
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
