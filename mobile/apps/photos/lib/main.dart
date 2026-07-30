import 'dart:async';
import 'dart:io';

import "package:adaptive_theme/adaptive_theme.dart";
import "package:computer/computer.dart";
import "package:ente_account_deletion/account_deletion.dart";
import "package:ente_components/ente_components.dart" as components;
import 'package:ente_crypto/ente_crypto.dart';
import "package:ente_crypto_api/ente_crypto_api.dart" show registerCryptoApi;
import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_lock_screen/ui/app_lock.dart";
import "package:ente_lock_screen/ui/lock_screen.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_rust/ente_rust.dart";
import "package:ente_strings/l10n/strings_localizations.dart";
import "package:ente_ui/theme/theme_config.dart" as ente_ui;
import "package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart";
import 'package:flutter/foundation.dart';
import "package:flutter/gestures.dart";
import 'package:flutter/material.dart';
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter_displaymode/flutter_displaymode.dart";
import "package:intl/date_symbol_data_local.dart";
import 'package:logging/logging.dart';
import "package:media_extension/media_extension_action_types.dart";
import "package:media_kit/media_kit.dart";
import "package:package_info_plus/package_info_plus.dart";
import 'package:path_provider/path_provider.dart';
import 'package:photos/app.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/error-reporting/super_logging.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/db/ml/db.dart";
import 'package:photos/ente_theme_data.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/module/upload/service/local_file_update_service.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import 'package:photos/services/app_lifecycle_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/favorites_service.dart';
import 'package:photos/services/home_widget_service.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import 'package:photos/services/machine_learning/ml_service.dart';
import 'package:photos/services/machine_learning/semantic_search/semantic_search_service.dart';
import 'package:photos/services/memory_lane/memory_lane_service.dart';
import 'package:photos/services/memory_share_service.dart';
import "package:photos/services/notification_service.dart";
import "package:photos/services/photos_contacts_service.dart";
import 'package:photos/services/push_service.dart';
import 'package:photos/services/search_service.dart';
import 'package:photos/services/social_notification_coordinator.dart';
import 'package:photos/services/sync/local_sync_service.dart';
import 'package:photos/services/sync/remote_sync_service.dart';
import "package:photos/services/sync/sync_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/src/rust/frb_generated.dart";
import "package:photos/utils/device_info.dart";
import "package:photos/utils/email_util.dart";
import "package:photos/utils/intent_util.dart";
import "package:photos/utils/photos_crypto_api_adapter.dart";
import 'package:rive/rive.dart' as rive;
import 'package:shared_preferences/shared_preferences.dart';

final _logger = Logger("main");

const kLastBGTaskHeartBeatTime = "bg_task_hb_time";
const kLastFGTaskHeartBeatTime = "fg_task_hb_time";
const kHeartBeatFrequency = Duration(seconds: 1);
const kFGSyncFrequency = Duration(minutes: 5);
const kFGHomeWidgetSyncFrequency = Duration(minutes: 15);
const kBGTaskTimeout = Duration(seconds: 28);
const kBGPushTimeout = Duration(seconds: 28);
const kFGTaskDeathTimeoutInMicroseconds = 5000000;
bool isProcessBg = true;
bool _stopHearBeat = false;
bool _isSyncInitialized = false;
bool _isRustInitialized = false;
Future<void>? _rustInitFuture;

enum ForegroundStartupMode { normal, picker }

void main() async {
  debugRepaintRainbowEnabled = false;
  WidgetsFlutterBinding.ensureInitialized();
  ente_ui.AppThemeConfig.initialize(ente_ui.EnteApp.photos);
  await initIsIPad();
  if (isIPad) {
    // Workaround for https://github.com/flutter/flutter/issues/177992
    // iPadOS 26.1 sends fake (0,0) pointer events when taps happen near the
    // status bar; cancel them so they don't dismiss popups, dialogs, etc.
    // Once we upgrade to a Flutter version that includes the upstream fix,
    // this workaround can be removed. The entire workaround (isIPad flag,
    // initIsIPad, and this pointer guard) was introduced in a single commit
    // so reverting that commit will cleanly remove it.
    GestureBinding.instance.pointerRouter.addGlobalRoute((PointerEvent event) {
      if (event is PointerDownEvent && event.position == Offset.zero) {
        GestureBinding.instance.cancelPointer(event.pointer);
      }
    });
  }
  FFmpegKitConfig.init().ignore();
  await rive.RiveNative.init();
  MediaKit.ensureInitialized();

  final savedThemeMode = await AdaptiveTheme.getThemeMode();
  final initialMediaExtensionAction = Platform.isAndroid
      ? await initIntentAction()
      : MediaExtentionAction(action: IntentAction.main);
  await _runInForeground(savedThemeMode, initialMediaExtensionAction);

  if (Platform.isAndroid) FlutterDisplayMode.setHighRefreshRate().ignore();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(systemNavigationBarColor: Color(0x00010000)),
  );

  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
}

Future<void> _runInForeground(
  AdaptiveThemeMode? savedThemeMode,
  MediaExtentionAction initialMediaExtensionAction,
) async {
  components.ComponentTheme.configure(app: components.ComponentApp.photos);
  return await runWithLogs(() async {
    _logger.info("Starting app in foreground");
    isProcessBg = false;
    final isPickerStartup =
        initialMediaExtensionAction.action == IntentAction.pick;
    if (isPickerStartup) {
      unawaited(_warmPickerFilesDb());
    }
    await _init(
      false,
      via: 'mainMethod',
      startupMode: isPickerStartup
          ? ForegroundStartupMode.picker
          : ForegroundStartupMode.normal,
    );
    final Locale? locale = await getLocale(noFallback: true);
    runApp(
      AppLock(
        builder: (args) => EnteApp(
          locale,
          savedThemeMode,
          initialMediaExtensionAction: initialMediaExtensionAction,
        ),
        lockScreen: LockScreen(
          Configuration.instance,
          authReasonBuilder: (context) =>
              AppLocalizations.of(context).authToViewYourMemories,
          onLogout: (context) => UserService.instance.logout(context),
        ),
        enabled:
            await LockScreenSettings.instance.shouldShowLockScreen() ||
            localSettings.isOnGuestView(),
        onUnlock: () => unawaited(localSettings.setOnGuestView(false)),
        locale: locale,
        supportedLocales: appSupportedLocales,
        localizationsDelegates: const [
          StringsLocalizations.delegate,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: localResolutionCallBack,
        lightTheme: lightThemeData,
        darkTheme: darkThemeData,
        savedThemeMode: _themeMode(savedThemeMode),
      ),
    );
    if (isPickerStartup) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(SemanticSearchService.instance.init());
      unawaited(_warmForegroundDeferredServices());
    });
    unawaited(_scheduleFGSync('appStart in FG'));
  });
}

Future<void> _warmPickerFilesDb() async {
  final tlog = TimeLogger();
  try {
    _logger.info("Picker FilesDB warm-up init $tlog");
    await FilesDB.instance.sqliteAsyncDB;
    _logger.info("Picker FilesDB warm-up done $tlog");
  } catch (e, s) {
    _logger.warning("Picker FilesDB warm-up failed", e, s);
  }
}

Future<void> _warmForegroundDeferredServices() async {
  try {
    await MemoryLaneService.instance.init();
    if (flagService.facesTimeline) {
      MemoryLaneService.instance
          .queueFullRecompute(trigger: "startup")
          .ignore();
    } else {
      _logger.info("Memory Lane disabled via feature flag");
    }
  } catch (e, s) {
    _logger.warning("Deferred MemoryLaneService warm failed", e, s);
  }
  unawaited(
    Future.delayed(
      const Duration(seconds: 5),
      installSourceService.autoAttributePendingSource,
    ),
  );
}

ThemeMode _themeMode(AdaptiveThemeMode? savedThemeMode) {
  if (savedThemeMode == null) return ThemeMode.system;
  if (savedThemeMode.isLight) return ThemeMode.light;
  if (savedThemeMode.isDark) return ThemeMode.dark;
  return ThemeMode.system;
}

Future<void> _homeWidgetSync([bool isBackground = false]) async {
  if (isBackground && Platform.isIOS) {
    _logger.info("Home widget sync skipped in background on iOS");
    return;
  }

  try {
    await HomeWidgetService.instance.initHomeWidget(isBackground);
  } catch (e, s) {
    _logger.severe("Error in syncing home widget", e, s);
  }
}

Future<void> runBackgroundTask(
  String taskId,
  TimeLogger tlog, {
  String mode = 'normal',
}) async {
  // Check if foreground is recently active to avoid conflicts
  final isRunningInFG = await _isRunningInForeground();

  // If FG was active in last 30 seconds, skip BG work
  if (isRunningInFG) {
    _logger.info(
      "[BG TASK] Foreground recently active, skipping background work",
    );
    return;
  }

  _logger.info(
    "[BG TASK] No recent foreground activity, proceeding with background work",
  );

  // Mark BG as active

  await _runMinimally(taskId, tlog);
}

Future<void> _runMinimally(String taskId, TimeLogger tlog) async {
  try {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _scheduleHeartBeat(prefs, true);
    await _ensureRustInitialized(via: 'workmanager:$taskId');

    _logger.info("[BG TASK] NetworkClient init $tlog");
    await NetworkClient.instance.init(packageInfo, prefs);
    _logger.info("[BG TASK] NetworkClient init done $tlog");

    ServiceLocator.instance.init(
      prefs,
      NetworkClient.instance.enteDio,
      NetworkClient.instance.getDio(),
      NetworkClient.instance.downloadDio,
      packageInfo,
    );
    NotificationService.instance.init(prefs);

    _logger.info("(for debugging) Configuration init $tlog");
    await Configuration.instance.init(prefs);
    _logger.info("(for debugging) Configuration done $tlog");

    // App LifeCycle
    AppLifecycleService.instance.init(prefs);
    AppLifecycleService.instance.onAppInBackground(
      'init via: WorkManager $tlog',
    );

    // Crypto rel.
    await Computer.shared().turnOn(workersCount: 4);
    CryptoUtil.init();

    // Initialize early so thermal/battery listeners can warm up while the
    // rest of background services are being initialized.
    final controller = computeController;
    await MemoryShareService.instance.init();

    _logger.info("(for debugging) CollectionsService init $tlog");
    await CollectionsService.instance.init(prefs);
    _logger.info("(for debugging) CollectionsService init done $tlog");

    // Upload & Sync Related
    await FileUploader.instance.init(prefs, true);
    LocalFileUpdateService.instance.init(prefs);
    await LocalSyncService.instance.init(prefs);
    RemoteSyncService.instance.init(prefs);
    await SyncService.instance.init(prefs);
    _isSyncInitialized = true;

    // Misc Services
    await UserService.instance.init();
    SocialNotificationCoordinator.instance.init(prefs);
    await NotificationService.instance.initializeForBackground();

    // Begin Execution
    // only runs for android
    _logger.info("[BG TASK] update notification");
    updateService.showUpdateNotification().ignore();
    _logger.info("[BG TASK] sync starting");
    await _sync('bgTaskActiveProcess');
    _logger.info("[BG TASK] sync completed");

    _logger.info("[BG TASK] locale fetch");
    final locale = await getLocale();
    await initializeDateFormatting(locale?.languageCode ?? "en");
    // only runs for android
    _logger.info("[BG TASK] home widget sync");
    if (!isLocalGalleryMode &&
        hasGrantedMLConsent &&
        localSettings.isMLLocalIndexingEnabled) {
      PersonService.init(entityService, MLDataDB.instance, prefs);
      _logger.info(
        "[BG TASK] person service initialized for memories recompute",
      );
    }
    await _homeWidgetSync(true);

    if ((isLocalGalleryMode || flagService.enableMLInBackground) &&
        hasGrantedMLConsent) {
      await controller.init();
      final canRunML = controller.requestCompute(ml: true);
      if (!canRunML) {
        _logger.info(
          "[BG TASK] skipping ML, compute requirements not satisfied",
        );
      } else {
        bool mlRunStarted = false;
        try {
          await MLService.instance.init();
          PersonService.init(entityService, MLDataDB.instance, prefs);
          mlRunStarted = true;
          await MLService.instance.runAllML(force: false);
        } finally {
          if (!mlRunStarted) {
            controller.releaseCompute(ml: true);
          }
        }
      }
    }
    _logger.info("[BG TASK] smart albums sync");
    await smartAlbumsService.syncSmartAlbums();

    _logger.info("[BG TASK] $taskId completed");
  } catch (e, s) {
    _logger.severe("[BG TASK] $taskId error", e, s);
  }
}

Future<void> _init(
  bool isBackground, {
  String via = '',
  ForegroundStartupMode startupMode = ForegroundStartupMode.normal,
}) async {
  try {
    bool initComplete = false;
    final isPickerStartup =
        !isBackground && startupMode == ForegroundStartupMode.picker;
    final TimeLogger tlog = TimeLogger();
    Future.delayed(const Duration(seconds: 15), () {
      if (!initComplete && !isBackground) {
        _logger.severe("Stuck on splash screen for >= 15 seconds");
        triggerSendLogs(
          "support@ente.com",
          "Stuck on splash screen for >= 15 seconds on ${Platform.operatingSystem}",
          null,
        );
      }
    });
    if (!isBackground) _heartBeatOnInit(0);
    _logger.info("Initializing...  inBG =$isBackground via: $via $tlog");
    await _ensureRustInitialized(
      via: isBackground ? 'background:$via' : 'foreground:$via',
    );
    final SharedPreferences preferences = await SharedPreferences.getInstance();
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    await _logFGHeartBeatInfo(preferences);
    _logger.info("_logFGHeartBeatInfo done $tlog");
    unawaited(_scheduleHeartBeat(preferences, isBackground));
    NotificationService.instance.init(preferences);
    if (isBackground) {
      await NotificationService.instance.initializeForBackground();
    }
    AppLifecycleService.instance.init(preferences);
    if (isBackground) {
      AppLifecycleService.instance.onAppInBackground('init via: $via $tlog');
    } else {
      AppLifecycleService.instance.onAppInForeground('init via: $via $tlog');
    }
    // Start workers asynchronously. No need to wait for them to start
    Computer.shared().turnOn(workersCount: 4).ignore();
    CryptoUtil.init();

    _logger.info("NetworkClient init $tlog");
    await NetworkClient.instance.init(packageInfo, preferences);
    _logger.info("NetworkClient init done $tlog");

    ServiceLocator.instance.init(
      preferences,
      NetworkClient.instance.enteDio,
      NetworkClient.instance.getDio(),
      NetworkClient.instance.downloadDio,
      packageInfo,
    );
    wakeLockService.init(isBackground: isBackground);

    _logger.info("Configuration init $tlog");
    await Configuration.instance.init(preferences);
    _logger.info("Configuration done $tlog");

    _logger.info("Lockscreen init $tlog");
    registerCryptoApi(const PhotosCryptoApiAdapter());
    await LockScreenSettings.instance.init(
      Configuration.instance,
      useLegacyHashFallback: true,
      hasOptedForOfflineMode: isLocalGalleryMode,
      appLogoAsset: 'assets/ente-branding.svg',
      appLogoHeight: 18,
    );
    AccountDeletionSettings.instance.init(
      host: Configuration.instance,
      enteDio: NetworkClient.instance.enteDio,
    );

    await MemoryShareService.instance.init();

    _logger.info("UserService init $tlog");
    await UserService.instance.init();
    _logger.info("UserService init done $tlog");

    _logger.info("CollectionsService init $tlog");
    await CollectionsService.instance.init(preferences);
    _logger.info("CollectionsService init done $tlog");
    SocialNotificationCoordinator.instance.init(preferences);

    SearchService.instance.init();

    if (isPickerStartup) {
      if (Configuration.instance.hasConfiguredAccount()) {
        _logger.info("Minor inits for logged in state $tlog");
        PersonService.init(entityService, MLDataDB.instance, preferences);
        _logger.info("PersonService init for picker startup done $tlog");
        await FavoritesService.instance.initFav();
        _logger.info("FavoritesService init done $tlog");
      }
      _logger.info("Picker startup init done $tlog");
      initComplete = true;
      _stopHearBeat = true;
      return;
    }

    FavoritesService.instance.initFav().ignore();
    LocalFileUpdateService.instance.init(preferences);

    _logger.info("FileUploader init $tlog");
    await FileUploader.instance.init(preferences, isBackground);
    _logger.info("FileUploader init done $tlog");

    _logger.info("LocalSyncService init $tlog");
    await LocalSyncService.instance.init(preferences);
    _logger.info("LocalSyncService init done $tlog");

    RemoteSyncService.instance.init(preferences);
    _logger.info("RemoteFileMLService done $tlog");

    _logger.info("SyncService init $tlog");
    await SyncService.instance.init(preferences);
    _isSyncInitialized = true;
    _logger.info("SyncService init done $tlog");

    if (!isBackground && flagService.internalUser) {
      _logger.info("GalleryDownloadQueueService init $tlog");
      await galleryDownloadQueueService.init();
      _logger.info("GalleryDownloadQueueService init done $tlog");
    }

    _logger.info("RitualsService init $tlog");
    await ritualsService.init();
    _logger.info("RitualsService init done $tlog");

    if (!isBackground) {
      await _scheduleFGHomeWidgetSync();
    }

    if (Platform.isIOS) {
      PushService.instance
          .init(onBackgroundPush: _handleBackgroundPush)
          .ignore();
    }
    _logger.info("PushService/HomeWidget done $tlog");
    unawaited(MLService.instance.init());
    PersonService.init(entityService, MLDataDB.instance, preferences);
    try {
      await PersonService.instance.refreshPersonCache();
    } catch (e, s) {
      PersonService.instance.clearCache();
      _logger.severe("Person cache warm-up failed", e, s);
    }
    if (!isBackground) {
      unawaited(_warmContactsCacheInBackground());
    }
    wrappedService.scheduleInitialLoad();
    logLocalSettings();
    initComplete = true;
    _stopHearBeat = true;
    _logger.info("Initialization done $tlog");
  } catch (e, s) {
    _logger.severe("Error in init ", e, s);
    rethrow;
  }
}

Future<void> _warmContactsCacheInBackground() async {
  try {
    await PhotosContactsService.instance.ensureReady();
  } catch (e, s) {
    _logger.warning("Deferred contacts warm-up failed", e, s);
  }
}

Future<void> _ensureRustInitialized({required String via}) async {
  if (_isRustInitialized) {
    return;
  }
  final inFlightInit = _rustInitFuture;
  if (inFlightInit != null) {
    await inFlightInit;
    return;
  }

  final initFuture = Future.wait([EntePhotosRust.init(), EnteRust.init()]);
  _rustInitFuture = initFuture;
  try {
    await initFuture;
    _isRustInitialized = true;
  } finally {
    _rustInitFuture = null;
  }
}

void logLocalSettings() {
  final settings = {
    'Show memories': memoriesCacheService.showAnyMemories,
    'Smart memories enabled': localSettings.isSmartMemoriesEnabled,
    'ML enabled': flagService.hasGrantedMLConsent,
    'ML local indexing enabled': localSettings.isMLLocalIndexingEnabled,
    'Multipart upload enabled': localSettings.userEnabledMultiplePart,
    'Gallery grid size': localSettings.getPhotoGridSize(),
    'Video streaming enabled':
        VideoPreviewService.instance.isVideoStreamingEnabled,
  };

  final formattedSettings = settings.entries
      .map((e) => '${e.key}: ${e.value}')
      .join(', ');
  _logger.info('Local settings - $formattedSettings');
}

void _heartBeatOnInit(int i) {
  if (i <= 15 && !_stopHearBeat) {
    Future.delayed(const Duration(seconds: 1), () {
      if (_stopHearBeat) {
        _logger.info("Stopping Heartbeat check at $i");
        return;
      }
      _logger.info("init Heartbeat $i");
      _heartBeatOnInit(i + 1);
    });
  }
}

Future<void> _sync(String caller) async {
  if (!AppLifecycleService.instance.isForeground) {
    _logger.info("Syncing in background caller $caller");
  } else {
    _logger.info("Syncing in foreground caller $caller");
  }
  try {
    await SyncService.instance.sync();
  } catch (e, s) {
    if (!isHandledSyncError(e)) {
      _logger.warning("Sync error", e, s);
    }
  }
}

Future runWithLogs(Function() function, {String prefix = ""}) async {
  await SuperLogging.main(
    LogConfig(
      body: function,
      logDirPath: (await getApplicationSupportDirectory()).path + "/logs",
      maxLogFiles: 5,
      sentryDsn: kDebugMode ? sentryDebugDSN : sentryDSN,
      tunnel: sentryTunnel,
      enableInDebugMode: true,
      prefix: prefix,
    ),
  );
}

Future<void> _scheduleHeartBeat(
  SharedPreferences prefs,
  bool isBackground,
) async {
  await prefs.setInt(
    isBackground ? kLastBGTaskHeartBeatTime : kLastFGTaskHeartBeatTime,
    DateTime.now().microsecondsSinceEpoch,
  );
  Future.delayed(kHeartBeatFrequency, () async {
    // ignore: unawaited_futures
    _scheduleHeartBeat(prefs, isBackground);
  });
}

Future<void> _scheduleFGHomeWidgetSync() async {
  Future.delayed(kFGHomeWidgetSyncFrequency, () async {
    unawaited(_homeWidgetSyncPeriodic());
  });
}

Future<void> _homeWidgetSyncPeriodic() async {
  await _homeWidgetSync();
  Future.delayed(kFGHomeWidgetSyncFrequency, () async {
    unawaited(_homeWidgetSyncPeriodic());
  });
}

Future<void> _scheduleFGSync(String caller) async {
  await _sync(caller);
  Future.delayed(kFGSyncFrequency, () async {
    unawaited(_scheduleFGSync('fgSyncCron'));
  });
}

Future<bool> _isRunningInForeground() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final currentTime = DateTime.now().microsecondsSinceEpoch;
  final lastFGHeartBeatTime = DateTime.fromMicrosecondsSinceEpoch(
    prefs.getInt(kLastFGTaskHeartBeatTime) ?? 0,
  );
  return lastFGHeartBeatTime.microsecondsSinceEpoch >
      (currentTime - kFGTaskDeathTimeoutInMicroseconds);
}

Future<void> _handleBackgroundPush(Object message) async {
  final bool isRunningInFG = await _isRunningInForeground(); // hb
  final bool isInForeground = AppLifecycleService.instance.isForeground;
  if (isRunningInFG) {
    _logger.info(
      "Background push received when app is alive and runningInFG: $isRunningInFG inForeground: $isInForeground",
    );
    if (PushService.shouldSync(message)) {
      // FG is active, let it handle the sync
      _logger.info("Foreground is active, skipping background sync from push");
      // Could optionally trigger a sync event that FG can handle
    }
  } else {
    // App is dead or FG is not active
    runWithLogs(() async {
      _logger.info("Background push received, no active foreground");

      // Mark BG as active before starting
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        kLastBGTaskHeartBeatTime,
        DateTime.now().microsecondsSinceEpoch,
      );

      if (!_isSyncInitialized) {
        await _init(true, via: 'firebasePush');
      } else {
        _logger.info("Skipping background init; sync already initialized");
      }
      if (PushService.shouldSync(message)) {
        await _sync('firebaseBgSyncNoActiveProcess');
      }
    }, prefix: "[fbg]").ignore();
  }
}

Future<void> _logFGHeartBeatInfo(SharedPreferences prefs) async {
  final bool isRunningInFG = await _isRunningInForeground();
  await prefs.reload();
  final lastFGTaskHeartBeatTime = prefs.getInt(kLastFGTaskHeartBeatTime) ?? 0;
  final String lastRun = lastFGTaskHeartBeatTime == 0
      ? 'never'
      : DateTime.fromMicrosecondsSinceEpoch(lastFGTaskHeartBeatTime).toString();
  _logger.info('isAlreadyRunningFG: $isRunningInFG, last Beat: $lastRun');
}
