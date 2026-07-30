import "dart:async";
import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/l10n/strings_localizations.dart";
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:home_widget/home_widget.dart' as hw;
import 'package:logging/logging.dart';
import "package:media_extension/media_extension.dart";
import 'package:media_extension/media_extension_action_types.dart';
import "package:photos/core/event_bus.dart";
import 'package:photos/ente_theme_data.dart';
import "package:photos/events/memories_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/app_lifecycle_service.dart';
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/home_widget_service.dart";
import "package:photos/services/memory_home_widget_service.dart";
import "package:photos/services/people_home_widget_service.dart";
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/ui/picker/external_media_picker_page.dart";
import 'package:photos/ui/tabs/home_widget.dart';
import "package:photos/ui/viewer/actions/file_viewer.dart";
import "package:photos/utils/bg_task_utils.dart";
import "package:photos/utils/intent_util.dart";

class EnteApp extends StatefulWidget {
  final AdaptiveThemeMode? savedThemeMode;
  final Locale? locale;
  final MediaExtentionAction? initialMediaExtensionAction;

  const EnteApp(
    this.locale,
    this.savedThemeMode, {
    this.initialMediaExtensionAction,
    super.key,
  });

  static void setLocale(BuildContext context, Locale newLocale) {
    final state = context.findAncestorStateOfType<_EnteAppState>()!;
    state.setLocale(newLocale);
  }

  @override
  State<EnteApp> createState() => _EnteAppState();
}

class _EnteAppState extends State<EnteApp> with WidgetsBindingObserver {
  late Locale? locale;
  late StreamSubscription<MemoriesChangedEvent> _memoriesChangedSubscription;
  final _logger = Logger("EnteAppState");
  late StreamSubscription<PeopleChangedEvent> _peopleChangedSubscription;
  late Debouncer _changeCallbackDebouncer;
  StreamSubscription<MediaExtentionAction>? _intentActionSubscription;
  StreamSubscription<Uri?>? _widgetClickedSubscription;
  bool _didInitWidgetLaunchHandling = false;
  late Future<Widget> _initialAndroidHome;
  bool get _isPickerLaunch =>
      widget.initialMediaExtensionAction?.action == IntentAction.pick;

  @override
  void initState() {
    _logger.info('init App');
    super.initState();
    locale = widget.locale;
    _initialAndroidHome = _resolveInitialAndroidHome();
    if (Platform.isAndroid) {
      _intentActionSubscription = MediaExtension().intentActionStream.listen(
        (mediaExtentionAction) =>
            unawaited(_handleAndroidIntentAction(mediaExtentionAction)),
        onError: (Object error, StackTrace stackTrace) {
          _logger.warning(
            "Failed to handle Android intent action",
            error,
            stackTrace,
          );
        },
      );
    }
    WidgetsBinding.instance.addObserver(this);
    setupSubscription();
  }

  void setupSubscription() {
    _memoriesChangedSubscription = Bus.instance
        .on<MemoriesChangedEvent>()
        .listen((event) async {
          await MemoryHomeWidgetService.instance.memoryChanged();
        });
    _changeCallbackDebouncer = Debouncer(const Duration(milliseconds: 1500));
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen((
      event,
    ) async {
      _changeCallbackDebouncer.run(() async {
        unawaited(PeopleHomeWidgetService.instance.checkPeopleChanged());
        unawaited(smartAlbumsService.syncSmartAlbums());
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitWidgetLaunchHandling) {
      return;
    }
    _didInitWidgetLaunchHandling = true;
    if (_isPickerLaunch) {
      return;
    }
    _checkForWidgetLaunch();
  }

  Future<void> _checkForWidgetLaunch() async {
    await HomeWidgetService.instance.setAppGroup();
    await hw.HomeWidget.initiallyLaunchedFromHomeWidget().then(
      (uri) => HomeWidgetService.instance.onLaunchFromWidget(uri),
    );
    _widgetClickedSubscription = hw.HomeWidget.widgetClicked.listen(
      (uri) => unawaited(HomeWidgetService.instance.onLaunchFromWidget(uri)),
    );
  }

  void setLocale(Locale newLocale) {
    setState(() {
      locale = newLocale;
    });
  }

  Future<Widget> _resolveInitialAndroidHome() async {
    final mediaExtentionAction =
        widget.initialMediaExtensionAction ??
        (Platform.isAndroid
            ? await initIntentAction()
            : MediaExtentionAction(action: IntentAction.main));
    final lifecycleAction = _appLifecycleActionFor(mediaExtentionAction);
    AppLifecycleService.instance.setMediaExtensionAction(lifecycleAction);
    if (lifecycleAction.action == IntentAction.main) {
      unawaited(BgTaskUtils.configureWorkmanager());
    }
    if (mediaExtentionAction.action == IntentAction.pick) {
      return ExternalMediaPickerPage(
        requestedType: mediaExtentionAction.type,
        allowMultiple: mediaExtentionAction.allowMultiple,
      );
    }
    if (_shouldOpenFileViewer(mediaExtentionAction)) {
      return const FileViewer();
    }
    return const HomeWidget();
  }

  bool _shouldOpenFileViewer(MediaExtentionAction mediaExtentionAction) {
    return mediaExtentionAction.action == IntentAction.view &&
        (mediaExtentionAction.type == MediaType.image ||
            mediaExtentionAction.type == MediaType.video);
  }

  MediaExtentionAction _appLifecycleActionFor(
    MediaExtentionAction mediaExtentionAction,
  ) {
    if (mediaExtentionAction.action == IntentAction.view &&
        !_shouldOpenFileViewer(mediaExtentionAction)) {
      return MediaExtentionAction(action: IntentAction.main);
    }
    return mediaExtentionAction;
  }

  Future<void> _handleAndroidIntentAction(
    MediaExtentionAction mediaExtentionAction,
  ) async {
    AppLifecycleService.instance.setMediaExtensionAction(
      _appLifecycleActionFor(mediaExtentionAction),
    );
    if (mediaExtentionAction.action == IntentAction.pick) {
      await AppNavigationService.instance.pushPage(
        ExternalMediaPickerPage(
          requestedType: mediaExtentionAction.type,
          allowMultiple: mediaExtentionAction.allowMultiple,
        ),
      );
      return;
    }
    if (!_shouldOpenFileViewer(mediaExtentionAction)) {
      return;
    }
    await AppNavigationService.instance.pushPage(const FileViewer());
  }

  Widget _buildInitialAndroidHome() {
    return FutureBuilder<Widget>(
      future: _initialAndroidHome,
      builder: (context, snapshot) {
        return snapshot.data ??
            ColoredBox(color: Theme.of(context).scaffoldBackgroundColor);
      },
    );
  }

  Widget _buildHome() {
    if (Platform.isAndroid) {
      return _buildInitialAndroidHome();
    }
    return const HomeWidget();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) {
        computeController.onUserInteraction();
      },
      child: AdaptiveTheme(
        light: lightThemeData,
        dark: darkThemeData,
        initial: widget.savedThemeMode ?? AdaptiveThemeMode.system,
        builder: (lightTheme, dartTheme) => MaterialApp(
          navigatorKey: AppNavigationService.instance.navigatorKey,
          title: "ente",
          themeMode: ThemeMode.system,
          theme: lightTheme,
          darkTheme: dartTheme,
          home: _buildHome(),
          debugShowCheckedModeBanner: false,
          builder: EasyLoading.init(),
          locale: locale,
          supportedLocales: appSupportedLocales,
          localeListResolutionCallback: localResolutionCallBack,
          localizationsDelegates: const [
            StringsLocalizations.delegate,
            ...AppLocalizations.localizationsDelegates,
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _memoriesChangedSubscription.cancel();
    _peopleChangedSubscription.cancel();
    _changeCallbackDebouncer.cancelDebounceTimer();
    _intentActionSubscription?.cancel();
    _widgetClickedSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final String stateChangeReason = 'app -> $state';
    if (state == AppLifecycleState.resumed) {
      final lastAppOpenTime = AppLifecycleService.instance.getLastAppOpenTime();
      AppLifecycleService.instance.onAppInForeground(
        stateChangeReason + ': sync now',
      );
      if (_isPickerLaunch) {
        return;
      }
      unawaited(_reloadCachesUpdatedInBackground(lastAppOpenTime));
      SyncService.instance.sync();
    } else {
      AppLifecycleService.instance.onAppInBackground(stateChangeReason);
    }
  }

  Future<void> _reloadCachesUpdatedInBackground(
    int lastAppOpenTimeInMicroseconds,
  ) async {
    await ServiceLocator.instance.prefs.reload();

    final futures = <Future<void>>[];
    if (magicCacheService.lastMagicCacheUpdateTimeInMicroseconds >
        lastAppOpenTimeInMicroseconds) {
      futures.add(magicCacheService.refreshCache());
    }
    if (memoriesCacheService.lastMemoriesCacheUpdateTime >
        lastAppOpenTimeInMicroseconds) {
      futures.add(memoriesCacheService.refreshCache());
    }
    if (futures.isEmpty) {
      return;
    }
    await Future.wait(futures);
  }
}
