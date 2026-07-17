import 'dart:async';
import 'dart:io';

import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/app/view/app.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/core/constants.dart';
import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/locale.dart';
import 'package:ente_auth/services/auth_theme_preferences.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/services/billing_service.dart';
import 'package:ente_auth/services/local_backup_service.dart';
import 'package:ente_auth/services/notification_service.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/services/window_listener_service.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/home_page.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_auth/utils/debug_build_flags.dart';
import 'package:ente_auth/utils/directory_utils.dart' as auth_dir_utils;
import 'package:ente_auth/utils/gallery_import_util.dart';
import 'package:ente_auth/utils/window_protocol_handler.dart';
import 'package:ente_components/ente_components.dart' as components;
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_crypto_dart_adapter/ente_crypto_dart_adapter.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_lock_screen/ui/lock_screen.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_network/network.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/l10n/strings_localizations.dart';
import 'package:ente_ui/theme/theme_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

final _logger = Logger("main");

Future<void> initSystemTray() async {
  if (PlatformDetector.isMobile()) return;
  final String path = Platform.isWindows
      ? 'assets/icons/auth-icon.ico'
      : Platform.isMacOS
      ? 'assets/icons/auth-icon-monochrome-padded.png'
      : _linuxTrayIconPath();
  await trayManager.setIcon(path, isTemplate: true);
  Menu menu = Menu(
    items: [
      MenuItem(key: 'hide_window', label: 'Hide Window'),
      MenuItem(key: 'show_window', label: 'Show Window'),
      MenuItem.separator(),
      MenuItem(key: 'exit_app', label: 'Exit App'),
    ],
  );
  await trayManager.setContextMenu(menu);
}

String _linuxTrayIconPath() {
  if (Platform.environment.containsKey('FLATPAK_ID') ||
      Platform.environment.containsKey('SNAP')) {
    return 'io.ente.auth';
  }
  return 'assets/icons/auth-icon-monochrome.png';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerCryptoApi(const EnteCryptoDartAdapter());

  if (PlatformDetector.isDesktop()) {
    await windowManager.ensureInitialized();
    await WindowListenerService.instance.init();
    await windowManager.setPreventClose(true);
    WindowOptions windowOptions = WindowOptions(
      size: WindowListenerService.instance.getWindowSize(),
      maximumSize: const Size(8192, 8192),
    );
    bool isMaximized = WindowListenerService.instance.getIsMaximized();
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await auth_dir_utils.DirectoryUtils.migrateNamingChanges();
      await windowManager.show();
      if (isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.focus();
      initSystemTray().ignore();
    });
  }

  await _runInForeground();
  if (Platform.isAndroid) {
    FlutterDisplayMode.setHighRefreshRate().ignore();
  }
}

Future<void> _runInForeground() async {
  AppThemeConfig.initialize(EnteApp.auth);
  components.ComponentTheme.configure(app: components.ComponentApp.auth);
  final savedThemeMode = await AuthThemePreferences.getThemeMode();
  final configuration = Configuration.instance;
  return await _runWithLogs(() async {
    _logger.info("Starting app in foreground");
    try {
      await _init(false, via: 'mainMethod');
    } catch (e, s) {
      _logger.severe("Failed to init", e, s);
      rethrow;
    }
    final Locale? locale = await getLocale(noFallback: true);
    unawaited(UpdateService.instance.showUpdateNotification());
    runApp(
      AppLock(
        builder: (args) => App(locale: locale, savedThemeMode: savedThemeMode),
        debugShowCheckedModeBanner: false,
        lockScreen: LockScreen(configuration),
        enabled: await LockScreenSettings.instance.shouldShowLockScreen(),
        locale: locale,
        lightTheme: lightThemeData,
        darkTheme: darkThemeData,
        savedThemeMode: savedThemeMode,
        localeListResolutionCallback: localResolutionCallBack,
        localizationsDelegates: const [
          ...StringsLocalizations.localizationsDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: appSupportedLocales,
        backgroundLockLatency: const Duration(seconds: 0),
      ),
    );
  });
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
      sentryDsn: sentryDSN,
      enableInDebugMode: true,
      prefix: prefix,
    ),
  );
}

void _registerWindowsProtocol() {
  const kWindowsScheme = 'enteauth';
  // Register our protocol only on Windows platform
  if (!kIsWeb && Platform.isWindows) {
    WindowsProtocolHandler().register(
      kWindowsScheme,
      executable: null,
      arguments: null,
    );
  }
}

Future<void> _init(bool bool, {String? via}) async {
  _registerWindowsProtocol();
  await CryptoUtil.init();

  await PreferenceService.instance.init();
  await CodeStore.instance.init();
  await CodeDisplayStore.instance.init();
  await Configuration.instance.init([AuthenticatorDB.instance]);
  await cleanupPickedImagesOnStartup(logger: _logger);
  await Network.instance.init(Configuration.instance);
  await UserService.instance.init(Configuration.instance, const HomePage());
  await AuthenticatorService.instance.init();
  await BillingService.instance.init();
  await NotificationService.instance.init();
  await UpdateService.instance.init();
  await IconUtils.instance.init();
  await LockScreenSettings.instance.init(
    Configuration.instance,
    hasOptedForOfflineMode: Configuration.instance.hasOptedForOfflineMode(),
    hideAppContentDefault: true,
  );
  if (shouldAllowAuthScreenCapture) {
    await LockScreenSettings.instance.setHideAppContent(false, persist: false);
  }
  AccountDeletionSettings.instance.init(
    host: Configuration.instance,
    enteDio: Network.instance.enteDio,
  );
  await LocalBackupService.instance.init(
    hasOptedForOfflineMode: Configuration.instance.hasOptedForOfflineMode(),
  );
}
