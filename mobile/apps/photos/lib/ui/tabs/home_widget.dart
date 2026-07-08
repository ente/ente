import "dart:async";
import "dart:convert";
import "dart:io";

import "package:app_links/app_links.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:logging/logging.dart";
import "package:media_extension/media_extension_action_types.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:move_to_background/move_to_background.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/account_configured_event.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/backup_folders_updated_event.dart";
import "package:photos/events/christmas_banner_event.dart";
import "package:photos/events/clear_and_unfocus_search_bar_event.dart";
import "package:photos/events/homepage_swipe_to_select_in_progress_event.dart";
import "package:photos/events/opened_settings_event.dart";
import "package:photos/events/permission_granted_event.dart";
import "package:photos/events/subscription_purchased_event.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/events/trigger_logout_event.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/search/index_of_indexed_stack.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/services/album_home_widget_service.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/memory_home_widget_service.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/services/people_home_widget_service.dart";
import "package:photos/services/sync/diff_fetcher.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/services/update_service.dart";
import "package:photos/states/user_details_state.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/extents_page_view.dart";
import "package:photos/ui/growth/referral_screen.dart";
import "package:photos/ui/home/christmas/christmas_pull_animation.dart";
import "package:photos/ui/home/christmas/christmas_utils.dart";
import "package:photos/ui/home/christmas/snow_fall_overlay.dart";
import "package:photos/ui/home/gallery_download_banner.dart";
import "package:photos/ui/home/grant_permissions_widget.dart";
import "package:photos/ui/home/header_widget.dart";
import "package:photos/ui/home/home_bottom_nav_bar.dart";
import "package:photos/ui/home/home_gallery_widget.dart";
import "package:photos/ui/home/landing_page_widget.dart";
import "package:photos/ui/home/loading_photos_widget.dart";
import "package:photos/ui/notification/update/change_log_page.dart";
import "package:photos/ui/rituals/ritual_camera_page.dart";
import "package:photos/ui/rituals/ritual_page.dart";
import "package:photos/ui/rituals/ritual_privacy.dart";
import "package:photos/ui/settings/app_update_dialog.dart";
import "package:photos/ui/settings_page.dart";
import "package:photos/ui/social/feed_screen.dart";
import "package:photos/ui/tabs/albums_tab.dart";
import "package:photos/ui/viewer/actions/file_viewer.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/shared_public_collection_page.dart";
import "package:photos/ui/viewer/search_tab/search_tab.dart";
import "package:photos/utils/collection_util.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/intent_util.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key});

  @override
  State<StatefulWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  static const _feedTab = FeedScreen(showBackButton: false);
  final _logger = Logger("HomeWidgetState");
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final _selectedAlbums = SelectedAlbums();
  final _selectedFiles = SelectedFiles();

  final PageController _pageController = PageController();
  int _selectedTabIndex = 0;
  final ValueNotifier<int> _selectedTabIndexNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> _christmasPullOffsetNotifier =
      ValueNotifier<double>(0);
  final ValueNotifier<bool> _christmasPullReleasedNotifier =
      ValueNotifier<bool>(false);

  // for receiving media files
  // ignore: unused_field
  StreamSubscription? _intentDataStreamSubscription;
  List<SharedMediaFile>? _sharedFiles;
  bool _shouldRenderCreateCollectionSheet = false;
  bool _mediaViewFallbackNavigationScheduled = false;
  bool _personSyncTriggered = false;
  bool _collectionsSyncTriggered = false;
  bool _isShowingChangeLog = false;
  bool _startWithoutAccount = false;
  final isOnSearchTabNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isAlbumsSearchActiveNotifier = ValueNotifier<bool>(
    false,
  );
  final ValueNotifier<bool> _shouldAlbumsSearchConsumeBackNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _shouldSearchTabSearchConsumeBackNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<bool> _swipeToSelectInProgressNotifier =
      ValueNotifier<bool>(false);

  late StreamSubscription<TabChangedEvent> _tabChangedEventSubscription;
  late StreamSubscription<SubscriptionPurchasedEvent>
  _subscriptionPurchaseEvent;
  late StreamSubscription<TriggerLogoutEvent> _triggerLogoutEvent;
  late StreamSubscription<UserLoggedOutEvent> _loggedOutEvent;
  late StreamSubscription<PermissionGrantedEvent> _permissionGrantedEvent;
  late StreamSubscription<SyncStatusUpdate> _firstImportEvent;
  late StreamSubscription<BackupFoldersUpdatedEvent> _backupFoldersUpdatedEvent;
  late StreamSubscription<AccountConfiguredEvent> _accountConfiguredEvent;
  StreamSubscription? _publicAlbumLinkSubscription;
  StreamSubscription<Uri?>? _authDeepLinkSubscription;
  late StreamSubscription<HomepageSwipeToSelectInProgressEvent>
  _homepageSwipeToSelectInProgressEventSubscription;
  late StreamSubscription<ChristmasBannerEvent>
  _christmasBannerEventSubscription;
  late StreamSubscription<AppModeChangedEvent> _appModeChangedEventSubscription;

  final DiffFetcher _diffFetcher = DiffFetcher();

  void _startWithoutAccountFlow() {
    setState(() {
      _startWithoutAccount = true;
    });
  }

  @override
  void initState() {
    _logger.info("initstate");
    super.initState();

    NotificationService.instance
        .initialize(_onDidReceiveNotificationResponse)
        .ignore();

    if (LocalSyncService.instance.hasCompletedFirstImportOrBypassed()) {
      syncWidget();
    }
    _tabChangedEventSubscription = Bus.instance.on<TabChangedEvent>().listen((
      event,
    ) {
      final previousTabIndex = _selectedTabIndex;
      _selectedTabIndex = event.selectedIndex;
      _selectedTabIndexNotifier.value = event.selectedIndex;

      if (event.selectedIndex == 3) {
        isOnSearchTabNotifier.value = true;
        unawaited(SemanticSearchService.instance.prepareForInteractiveSearch());
      } else {
        isOnSearchTabNotifier.value = false;
      }
      if (event.source != TabChangedEventSource.pageView) {
        debugPrint(
          "TabChange going from $previousTabIndex to ${event.selectedIndex} source: ${event.source}",
        );
        if (_pageController.hasClients) {
          final pageDelta = (event.selectedIndex - previousTabIndex).abs();
          if (pageDelta <= 1) {
            _pageController.animateToPage(
              event.selectedIndex,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeIn,
            );
          } else {
            _pageController.jumpToPage(event.selectedIndex);
          }
        }
      }
    });
    _subscriptionPurchaseEvent = Bus.instance
        .on<SubscriptionPurchasedEvent>()
        .listen((event) {
          setState(() {});
        });
    _accountConfiguredEvent = Bus.instance.on<AccountConfiguredEvent>().listen((
      event,
    ) {
      _startWithoutAccount = false;
      setState(() {});
      // fetch user flags on login
      if (!isLocalGalleryMode) {
        flagService.flags;
      }
    });
    _triggerLogoutEvent = Bus.instance.on<TriggerLogoutEvent>().listen((
      event,
    ) async {
      await _autoLogoutAlert();
    });
    _loggedOutEvent = Bus.instance.on<UserLoggedOutEvent>().listen((event) {
      _logger.info('logged out, selectTab index to 0');
      _selectedTabIndex = 0;
      _selectedTabIndexNotifier.value = 0;
      _startWithoutAccount = false;
      if (mounted) {
        setState(() {});
      }
    });
    _permissionGrantedEvent = Bus.instance.on<PermissionGrantedEvent>().listen((
      event,
    ) async {
      if (mounted) {
        setState(() {});
      }
    });
    _appModeChangedEventSubscription = Bus.instance
        .on<AppModeChangedEvent>()
        .listen((event) async {
          if (mounted) {
            setState(() {});
            _scheduleChangeLogCheck(delay: const Duration(milliseconds: 250));
          }
        });
    _firstImportEvent = Bus.instance.on<SyncStatusUpdate>().listen((
      event,
    ) async {
      if (mounted && event.status == SyncStatus.completedFirstGalleryImport) {
        Duration delayInRefresh = const Duration(milliseconds: 0);
        // Loading page will redirect to BackupFolderSelectionPage.
        // To avoid showing folder hook in middle during routing,
        // delay state refresh for home page
        if (!permissionService.hasGrantedLimitedPermissions()) {
          delayInRefresh = const Duration(milliseconds: 250);
        }
        Future.delayed(delayInRefresh, () {
          if (mounted) {
            setState(() {});
            syncWidget();
            if (!NotificationService.instance.hasGrantedPermissions() &&
                isLocalGalleryMode &&
                !Configuration.instance.hasConfiguredAccount()) {
              Future.delayed(const Duration(seconds: 2), () {
                NotificationService.instance.requestPermissions().ignore();
              });
            }
          }
        });
      }
    });
    _backupFoldersUpdatedEvent = Bus.instance
        .on<BackupFoldersUpdatedEvent>()
        .listen((event) async {
          if (mounted) {
            setState(() {});
          }
        });
    _initDeepLinks();
    updateService.shouldShowUpdateNotification().then((value) {
      Future.delayed(Duration.zero, () {
        if (value) {
          showDialog(
            useRootNavigator: false,
            context: context,
            builder: (BuildContext context) {
              return AppUpdateDialog(updateService.getLatestVersionInfo());
            },
            barrierColor: Colors.black.withValues(alpha: 0.85),
          );
          updateService.resetUpdateAvailableShownTime();
        }
      });
    });

    // Initialize deep link subscription for public albums on both iOS and Android
    _initDeepLinkSubscriptionForPublicAlbums();

    // For sharing images coming from outside the app
    _initMediaShareSubscription();
    _scheduleChangeLogCheck(delay: const Duration(seconds: 1));

    if (Platform.isAndroid &&
        !localSettings.hasConfiguredInAppLinkPermissions() &&
        RemoteSyncService.instance.isFirstRemoteSyncDone() &&
        endpointConfig.isProduction) {
      PackageInfo.fromPlatform().then((packageInfo) {
        final packageName = packageInfo.packageName;
        if (packageName == 'io.ente.photos.independent' ||
            packageName == 'io.ente.photos.fdroid') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              requestPermissionToOpenLinksInApp(context, packageName);
            }
          });
        }
      });
    }

    _homepageSwipeToSelectInProgressEventSubscription = Bus.instance
        .on<HomepageSwipeToSelectInProgressEvent>()
        .listen((inProgress) {
          _swipeToSelectInProgressNotifier.value = inProgress.isInProgress;
        });

    _christmasBannerEventSubscription = Bus.instance
        .on<ChristmasBannerEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
    if (!isLocalGalleryMode && Configuration.instance.hasConfiguredAccount()) {
      MemoryShareService.instance.listMemoryShares().ignore();
    }
  }

  Future<void> syncWidget() async {
    await Future.delayed(const Duration(seconds: 5));

    _logger.info("Syncing home widget");
    await AlbumHomeWidgetService.instance.checkPendingAlbumsSync();
    await PeopleHomeWidgetService.instance.checkPendingPeopleSync();
    await MemoryHomeWidgetService.instance.checkPendingMemorySync();
  }

  void _scheduleChangeLogCheck({required Duration delay}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(delay, () {
        if (mounted) {
          showChangeLog(context);
        }
      });
    });
  }

  final Map<Uri, (bool, int)> _linkedPublicAlbums = {};
  Future<void> _handlePublicAlbumLink(Uri uri, String via) async {
    if (!mounted) {
      _logger.warning("Cannot handle public album link - widget not mounted");
      return;
    }
    try {
      _logger.info("Handling public album link: via $via");
      final int currentTime = DateTime.now().millisecondsSinceEpoch;
      final bool isInitialStream = via.toLowerCase().contains('initial');
      if (_linkedPublicAlbums.containsKey(uri)) {
        final (lastInitialLink, lastTime) = _linkedPublicAlbums[uri]!;
        // for initial stream, wait for 30 seconds to ignore duplicate links event
        if (currentTime - lastTime < (lastInitialLink ? 30000 : 2000)) {
          _logger.info(
            "ignore was it has handled $lastInitialLink at epoch $lastTime",
          );
          return;
        }
      }
      _linkedPublicAlbums[uri] = (isInitialStream, currentTime);

      final Collection? collection = await CollectionsService.instance
          .getCollectionFromPublicLink(context, uri);
      if (collection == null) {
        return;
      }

      final existingCollection = CollectionsService.instance.getCollectionByID(
        collection.id,
      );

      if (collection.isOwner(Configuration.instance.getUserID() ?? -1) ||
          (existingCollection != null && !existingCollection.isDeleted)) {
        await routeToPage(
          context,
          CollectionPage(CollectionWithThumbnail(collection, null)),
        );
        return;
      }

      // Check for action=join parameter to show join dialog
      final shouldShowJoinDialog =
          uri.queryParameters['action'] == 'join' &&
          Configuration.instance.isLoggedIn();

      final dialog = createProgressDialog(context, "Loading...");
      final publicUrl = collection.publicURLs[0];
      if (!publicUrl.enableDownload) {
        await showErrorDialog(
          context,
          context.l10n.canNotOpenTitle,
          context.l10n.canNotOpenBody,
        );
        return;
      }
      if (publicUrl.passwordEnabled) {
        await showTextInputDialog(
          context,
          title: AppLocalizations.of(context).enterPassword,
          submitButtonLabel: AppLocalizations.of(context).ok,
          alwaysShowSuccessState: false,
          popnavAfterSubmission: false,
          onSubmit: (String text) async {
            if (text.trim() == "") {
              return;
            }
            try {
              final hashedPassword = await CryptoUtil.deriveKey(
                utf8.encode(text),
                CryptoUtil.base642bin(publicUrl.nonce!),
                publicUrl.memLimit!,
                publicUrl.opsLimit!,
              );

              unawaited(
                CollectionsService.instance
                    .verifyPublicCollectionPassword(
                      context,
                      CryptoUtil.bin2base64(hashedPassword),
                      collection.id,
                    )
                    .then((result) async {
                      if (result) {
                        await dialog.show();

                        final List<EnteFile> sharedFiles = await _diffFetcher
                            .getPublicFiles(
                              context,
                              collection.id,
                              collection.pubMagicMetadata.asc ?? false,
                            );
                        await dialog.hide();
                        Navigator.of(context).pop();

                        await routeToPage(
                          context,
                          SharedPublicCollectionPage(
                            CollectionWithThumbnail(collection, null),
                            files: sharedFiles,
                            shouldShowJoinDialog: shouldShowJoinDialog,
                          ),
                        );
                      }
                    }),
              );
            } catch (e, s) {
              _logger.severe("Failed to decrypt password for album", e, s);
              await showGenericErrorDialog(context: context, error: e);
              return;
            }
          },
        );
      } else {
        await dialog.show();

        final List<EnteFile> sharedFiles = await _diffFetcher.getPublicFiles(
          context,
          collection.id,
          collection.pubMagicMetadata.asc ?? false,
        );
        await dialog.hide();

        await routeToPage(
          context,
          SharedPublicCollectionPage(
            CollectionWithThumbnail(collection, null),
            files: sharedFiles,
            shouldShowJoinDialog: shouldShowJoinDialog,
          ),
        );
        if (sharedFiles.length == 1) {
          await routeToPage(
            context,
            DetailPage(
              DetailPageConfiguration(
                sharedFiles,
                0,
                "sharedPublicCollection",
                galleryType: GalleryType.sharedPublicCollection,
              ),
            ),
          );
        }
      }
    } catch (e, s) {
      _logger.severe("Failed to handle public album link", e, s);
      return;
    }
  }

  Future<void> _autoLogoutAlert() async {
    final AlertDialog alert = AlertDialog(
      title: Text(AppLocalizations.of(context).sessionExpired),
      content: Text(AppLocalizations.of(context).pleaseLoginAgain),
      actions: [
        TextButton(
          child: Text(
            AppLocalizations.of(context).ok,
            style: TextStyle(
              color: Theme.of(context).colorScheme.greenAlternative,
            ),
          ),
          onPressed: () async {
            Navigator.of(context).pop('dialog');
            Navigator.of(context).popUntil((route) => route.isFirst);
            final dialog = createProgressDialog(
              context,
              AppLocalizations.of(context).loggingOut,
            );
            await dialog.show();
            await Configuration.instance.logout();
            await dialog.hide();
          },
        ),
      ],
    );

    await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (BuildContext context) {
        return alert;
      },
    );
  }

  @override
  void dispose() {
    _tabChangedEventSubscription.cancel();
    _subscriptionPurchaseEvent.cancel();
    _triggerLogoutEvent.cancel();
    _loggedOutEvent.cancel();
    _permissionGrantedEvent.cancel();
    _appModeChangedEventSubscription.cancel();
    _firstImportEvent.cancel();
    _backupFoldersUpdatedEvent.cancel();
    _accountConfiguredEvent.cancel();
    _intentDataStreamSubscription?.cancel();
    isOnSearchTabNotifier.dispose();
    _isAlbumsSearchActiveNotifier.dispose();
    _shouldAlbumsSearchConsumeBackNotifier.dispose();
    _shouldSearchTabSearchConsumeBackNotifier.dispose();
    _pageController.dispose();
    _publicAlbumLinkSubscription?.cancel();
    _authDeepLinkSubscription?.cancel();
    _homepageSwipeToSelectInProgressEventSubscription.cancel();
    _christmasBannerEventSubscription.cancel();
    _swipeToSelectInProgressNotifier.dispose();
    _selectedTabIndexNotifier.dispose();
    _christmasPullOffsetNotifier.dispose();
    _christmasPullReleasedNotifier.dispose();
    super.dispose();
  }

  void _initMediaShareSubscription() {
    // For sharing images/public links coming from outside the app while the app is in the memory
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            unawaited(_handleSharedMediaStream(value));
          },
          onError: (err) {
            _logger.severe("getIntentDataStream error: $err");
          },
        );
    // For sharing images/public links coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      unawaited(_handleInitialSharedMedia(value));
    });
  }

  Future<void> _handleSharedMediaStream(List<SharedMediaFile> value) async {
    if (!mounted || value.isEmpty) {
      return;
    }

    // Check if this is a public album link
    if (_isPublicAlbumUrl(value[0].path)) {
      final uri = Uri.parse(value[0].path);
      unawaited(_handlePublicAlbumLink(uri, "sharedIntent.getMediaStream"));
      return;
    }

    if (await _consumeAndroidMediaViewIntent()) {
      _scheduleMediaViewFallbackNavigation();
      return;
    }

    if (!mounted) {
      return;
    }
    if (value[0].mimeType != null &&
        (value[0].mimeType!.contains("image") ||
            value[0].mimeType!.contains("video"))) {
      unawaited(
        showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              actions: [
                const SizedBox(height: 24),
                ButtonWidget(
                  labelText: AppLocalizations.of(context).openFile,
                  buttonType: ButtonType.primary,
                  onTap: () async {
                    Navigator.of(context).pop(true);
                  },
                ),
                const SizedBox(height: 12),
                ButtonWidget(
                  buttonType: ButtonType.secondary,
                  labelText: AppLocalizations.of(context).backupFile,
                  onTap: () async {
                    Navigator.of(context).pop(false);
                  },
                ),
              ],
            );
          },
        ).then((shouldOpenFile) {
          if (!mounted || shouldOpenFile == null) {
            return;
          }
          if (shouldOpenFile) {
            unawaited(
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) {
                    return FileViewer(sharedMediaFile: value[0]);
                  },
                ),
              ),
            );
          } else {
            setState(() {
              _shouldRenderCreateCollectionSheet = true;
              _sharedFiles = value;
            });
          }
        }),
      );
    }
  }

  Future<void> _handleInitialSharedMedia(List<SharedMediaFile> value) async {
    if (!mounted) {
      return;
    }
    // Check if this is a public album link
    if (value.isNotEmpty && _isPublicAlbumUrl(value[0].path)) {
      final uri = Uri.parse(value[0].path);
      unawaited(_handlePublicAlbumLink(uri, "sharedIntent.getInitialMedia"));
      return;
    }

    if (await _consumeAndroidMediaViewIntent()) {
      if (!mounted) {
        return;
      }
      unawaited(
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) {
              return const FileViewer();
            },
          ),
        ),
      );
      return;
    }

    if (value.isEmpty || !mounted) {
      return;
    }

    setState(() {
      _sharedFiles = value;
      _shouldRenderCreateCollectionSheet = true;
    });
  }

  Future<bool> _consumeAndroidMediaViewIntent() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final mediaExtensionAction = await initIntentAction();
    AppLifecycleService.instance.setMediaExtensionAction(mediaExtensionAction);

    if (!_isMediaViewAction(mediaExtensionAction)) {
      return false;
    }

    _logger.info("Consuming shared media callback for Android media view");
    await ReceiveSharingIntent.instance.reset();
    return true;
  }

  bool _isMediaViewAction(MediaExtentionAction action) {
    return action.action == IntentAction.view &&
        (action.type == MediaType.image || action.type == MediaType.video);
  }

  void _scheduleMediaViewFallbackNavigation() {
    if (_mediaViewFallbackNavigationScheduled) {
      return;
    }
    _mediaViewFallbackNavigationScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      _mediaViewFallbackNavigationScheduled = false;
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      unawaited(
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) {
              return const FileViewer();
            },
          ),
        ),
      );
    });
  }

  Future<void> _initDeepLinkSubscriptionForPublicAlbums() async {
    final appLinks = AppLinks();

    // Handle public album deep links:
    // - iOS: Universal Links (https://albums.ente.io/... or
    //   https://albums.ente.com/...)
    // - Android: App Links (https://albums...) or custom scheme
    //   (ente://albums...)
    try {
      final initialUri = await appLinks.getInitialLink();
      if (initialUri != null) {
        if (_isPublicAlbumDeepLink(initialUri)) {
          await _handlePublicAlbumLink(initialUri, "appLinks.getInitialLink");
        } else {
          _logger.info("Ignoring deep link: $initialUri");
        }
      } else {
        _logger.info(
          "No initial link received in public album link subscription.",
        );
      }
    } catch (e) {
      _logger.severe("Error while getting initial public album deep link: $e");
    }

    _publicAlbumLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri? uri) {
        if (uri != null) {
          if (_isPublicAlbumDeepLink(uri)) {
            _handlePublicAlbumLink(uri, "appLinks.uriLinkStream");
          } else {
            _logger.info("Ignoring deep link: $uri");
          }
        } else {
          _logger.info("No link received in public album link subscription.");
        }
      },
      onError: (err) {
        _logger.severe("Error while getting public album deep link: $err");
      },
    );
  }

  bool _isPublicAlbumDeepLink(Uri uri) {
    if (!_isPublicAlbumHost(uri.host)) {
      return false;
    }
    if (Platform.isIOS) {
      return uri.scheme == "https";
    }
    if (Platform.isAndroid) {
      return uri.scheme == "ente" || uri.scheme == "https";
    }
    return false;
  }

  bool _isPublicAlbumUrl(String url) {
    final host = Uri.tryParse(url)?.host ?? "";
    return _isPublicAlbumHost(host);
  }

  bool _isPublicAlbumHost(String host) {
    return host == "albums.ente.io" || host == "albums.ente.com";
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building home_Widget with tab $_selectedTabIndex");
    final enableDrawer = _shouldEnableDrawer();
    final action = AppLifecycleService.instance.mediaExtensionAction.action;
    final isOnOnlineGrantPermissionScreen =
        Configuration.instance.hasConfiguredAccount() &&
        !isLocalGalleryMode &&
        _shouldShowPermissionWidget();
    return UserDetailsStateWidget(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final isStartWithoutAccountFlow =
              _startWithoutAccount &&
              !Configuration.instance.hasConfiguredAccount() &&
              !localSettings.isAppModeSet;
          if (isStartWithoutAccountFlow) {
            setState(() {
              _startWithoutAccount = false;
            });
            return;
          }
          if (_selectedTabIndex == 0) {
            if (_selectedFiles.files.isNotEmpty) {
              _selectedFiles.clearAll();
              return;
            }
            if (_isDrawerOpen()) {
              Navigator.pop(context);
            } else if (Platform.isAndroid && action == IntentAction.main) {
              unawaited(MoveToBackground.moveTaskToBack());
            } else {
              Navigator.pop(context);
            }
            return;
          }
          if (_selectedTabIndex == 1) {
            if (_selectedAlbums.albums.isNotEmpty) {
              _selectedAlbums.clearAll();
              return;
            }
            if (_shouldAlbumsSearchConsumeBackNotifier.value) {
              _isAlbumsSearchActiveNotifier.value = false;
              return;
            }
            if (_isAlbumsSearchActiveNotifier.value) {
              _isAlbumsSearchActiveNotifier.value = false;
            }
          }
          if (_selectedTabIndex == 3) {
            if (_shouldSearchTabSearchConsumeBackNotifier.value) {
              Bus.instance.fire(ClearAndUnfocusSearchBar());
              return;
            }
          }
          Bus.instance.fire(
            TabChangedEvent(0, TabChangedEventSource.backButton),
          );
        },
        child: Scaffold(
          key: _scaffoldKey,
          drawerScrimColor: getEnteColorScheme(context).strokeFainter,
          drawerEnableOpenDragGesture: false,
          //using a hack instead of enabling this as enabling this will create other problems
          drawer: enableDrawer
              ? ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: Drawer(
                    width: double.infinity,
                    shape: const RoundedRectangleBorder(),
                    child: SettingsPage(
                      emailNotifier: UserService.instance.emailValueNotifier,
                    ),
                  ),
                )
              : null,
          onDrawerChanged: (isOpened) {
            if (isOpened) {
              Bus.instance.fire(OpenedSettingsEvent());
            }
          },
          body: Stack(
            children: [
              Builder(
                builder: (context) {
                  return _getBody(context);
                },
              ),
              if (isChristmasPeriod())
                ValueListenableBuilder<double>(
                  valueListenable: _christmasPullOffsetNotifier,
                  builder: (context, pullOffset, child) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: _christmasPullReleasedNotifier,
                      builder: (context, isReleased, child) {
                        if (pullOffset <= 0) {
                          return const SizedBox.shrink();
                        }
                        return Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: ChristmasPullOverlay(
                            pullOffset: pullOffset,
                            isReleased: isReleased,
                          ),
                        );
                      },
                    );
                  },
                ),
              if (isChristmasPeriod())
                Positioned.fill(
                  child: FadingSnowOverlay(
                    pullOffsetNotifier: _christmasPullOffsetNotifier,
                  ),
                ),
            ],
          ),

          ///To fix the status bar not adapting it's color when switching
          ///screens the have different appbar colours.
          appBar: isOnOnlineGrantPermissionScreen
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(0),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: isOnSearchTabNotifier,
                    builder: (context, isOnSearchTab, _) {
                      return AnimatedBuilder(
                        animation: IndexOfStackNotifier(),
                        builder: (context, _) {
                          final colorScheme = getEnteColorScheme(context);
                          final resultsBackground = EnteTheme.isDark(context)
                              ? colorScheme.backgroundColour
                              : colorScheme.backgroundElevated2;
                          final isSearchResults =
                              isOnSearchTab &&
                              IndexOfStackNotifier().index == 1;
                          final isOnLandingPage =
                              !Configuration.instance.hasConfiguredAccount() &&
                              !isLocalGalleryMode &&
                              !_startWithoutAccount;
                          final isOnOnlineGrantPermissionScreen =
                              Configuration.instance.hasConfiguredAccount() &&
                              !isLocalGalleryMode &&
                              _shouldShowPermissionWidget();
                          return AppBar(
                            backgroundColor: isOnLandingPage
                                ? colorScheme.greenBase
                                : isSearchResults
                                ? resultsBackground
                                : isOnOnlineGrantPermissionScreen
                                ? colorScheme.backgroundColour
                                : colorScheme.backgroundColour,
                          );
                        },
                      );
                    },
                  ),
                ),
          resizeToAvoidBottomInset: false,
        ),
      ),
    );
  }

  Widget _getBody(BuildContext context) {
    final bool localGalleryMode = isLocalGalleryMode;
    if (!Configuration.instance.hasConfiguredAccount()) {
      _closeDrawerIfOpen();
      final shouldBootstrapLocalGalleryEntryFlow =
          _startWithoutAccount && !localGalleryMode;
      final hasPersistedLocalGalleryMode =
          localSettings.isAppModeSet && localGalleryMode;
      final canResumePersistedLocalGalleryMode =
          hasPersistedLocalGalleryMode &&
          permissionService.hasGrantedPermissions();
      final shouldUseLocalGalleryEntryFlow =
          _startWithoutAccount || canResumePersistedLocalGalleryMode;

      if (shouldBootstrapLocalGalleryEntryFlow) {
        return const GrantPermissionsWidget(startWithoutAccount: true);
      }
      if (shouldUseLocalGalleryEntryFlow && _shouldShowPermissionWidget()) {
        return const GrantPermissionsWidget(startWithoutAccount: true);
      }
      if (!shouldUseLocalGalleryEntryFlow) {
        return LandingPageWidget(
          onStartWithoutAccount: _startWithoutAccountFlow,
        );
      }
    }
    _ensurePersonSync();
    _ensureCollectionsSync();
    if (_shouldShowPermissionWidget()) {
      _ensurePersonSync();
      return const GrantPermissionsWidget();
    }
    if (_shouldShowLoadingWidget()) {
      return const LoadingPhotosWidget();
    }
    if (_sharedFiles != null &&
        _sharedFiles!.isNotEmpty &&
        _shouldRenderCreateCollectionSheet) {
      //The gallery is getting rebuilt for some reason when the keyboard is up.
      //So to stop showing multiple CreateCollectionSheets, this flag
      //needs to be set to false the first time it is rendered.
      _shouldRenderCreateCollectionSheet = false;
      ReceiveSharingIntent.instance.reset();
      Future.delayed(const Duration(milliseconds: 10), () {
        showCollectionActionSheet(
          context,
          sharedFiles: _sharedFiles,
          actionType: CollectionActionType.addFiles,
        );
      });
    }

    return Stack(
      children: [
        Builder(
          builder: (context) {
            return ValueListenableBuilder(
              valueListenable: _swipeToSelectInProgressNotifier,
              builder: (context, inProgress, child) {
                return ValueListenableBuilder<int>(
                  valueListenable: _selectedTabIndexNotifier,
                  builder: (context, selectedTabIndex, _) {
                    return ExtentsPageView(
                      onPageChanged: (page) {
                        Bus.instance.fire(
                          TabChangedEvent(page, TabChangedEventSource.pageView),
                        );
                      },
                      controller: _pageController,
                      openDrawer: Scaffold.of(context).openDrawer,
                      physics: inProgress
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      children: [
                        _buildTabHeroMode(0, selectedTabIndex, child!),
                        _buildTabHeroMode(
                          1,
                          selectedTabIndex,
                          AlbumsTab(
                            selectedAlbums: _selectedAlbums,
                            isSearchActiveNotifier:
                                _isAlbumsSearchActiveNotifier,
                            shouldConsumeBackNotifier:
                                _shouldAlbumsSearchConsumeBackNotifier,
                          ),
                        ),
                        _buildTabHeroMode(2, selectedTabIndex, _feedTab),
                        _buildTabHeroMode(
                          3,
                          selectedTabIndex,
                          SearchTab(
                            shouldConsumeBackNotifier:
                                _shouldSearchTabSearchConsumeBackNotifier,
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (!isChristmasPeriod()) return false;

                  if (notification.metrics.axis != Axis.vertical) return false;

                  const double maxPullOffset = 200.0;

                  if (notification is ScrollUpdateNotification) {
                    final double pixels = notification.metrics.pixels;
                    if (pixels < 0) {
                      if (pixels < -maxPullOffset) {
                        final scrollPosition = Scrollable.of(
                          notification.context!,
                        ).position;
                        scrollPosition.correctBy(-maxPullOffset - pixels);
                      }

                      final double clampedOffset = (-pixels).clamp(
                        0.0,
                        maxPullOffset,
                      );
                      _christmasPullOffsetNotifier.value = clampedOffset;
                      if (_christmasPullReleasedNotifier.value) {
                        _christmasPullReleasedNotifier.value = false;
                      }
                    } else if (_christmasPullOffsetNotifier.value != 0) {
                      _christmasPullOffsetNotifier.value = 0;
                    }
                  } else if (notification is ScrollEndNotification) {
                    if (_christmasPullOffsetNotifier.value > 0) {
                      _christmasPullReleasedNotifier.value = true;
                    }
                  }
                  return false;
                },
                child: HomeGalleryWidget(
                  header: const HeaderWidget(),
                  footer: const SizedBox(height: 160),
                  selectedFiles: _selectedFiles,
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: ValueListenableBuilder(
            valueListenable: isOnSearchTabNotifier,
            builder: (context, value, child) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (flagService.internalUser) const GalleryDownloadBanner(),
                  HomeBottomNavigationBar(
                    _selectedFiles,
                    _selectedAlbums,
                    selectedTabIndex: _selectedTabIndex,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTabHeroMode(int tabIndex, int selectedTabIndex, Widget child) {
    return ClipRect(
      child: HeroMode(enabled: tabIndex == selectedTabIndex, child: child),
    );
  }

  bool _isDrawerOpen() {
    return _scaffoldKey.currentState?.isDrawerOpen ?? false;
  }

  void _closeDrawerIfOpen() {
    if (_isDrawerOpen()) {
      SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
        _scaffoldKey.currentState?.closeDrawer();
      });
    }
  }

  Future<bool> _initDeepLinks() async {
    // Platform messages may fail, so we use a try/catch PlatformException.
    final appLinks = AppLinks();
    try {
      final initialLink = await appLinks.getInitialLink();
      // Parse the link and warn the user, if it is not correct,
      // but keep in mind it could be `null`.
      if (initialLink != null) {
        _logger.info("Initial link received: host ${initialLink.host}");
        _getCredentials(context, initialLink);
        return true;
      } else {
        _logger.info("No initial link received.");
      }
    } on PlatformException {
      // Handle exception by warning the user their action did not succeed
      // return?
      _logger.severe("PlatformException thrown while getting initial link");
    }

    // Attach a listener to the stream
    _authDeepLinkSubscription = appLinks.uriLinkStream.listen(
      (link) {
        _logger.info("Link received: host ${link.host}");
        _getCredentials(context, link);
      },
      onError: (err) {
        _logger.severe(err);
      },
    );
    return false;
  }

  void _getCredentials(BuildContext context, Uri? link) {
    if (Configuration.instance.hasConfiguredAccount() || link == null) {
      return;
    }
    final ott = link.queryParameters["ott"];
    if (ott == null || ott.isEmpty) {
      _logger.info("Ignoring auth deep link without ott parameter");
      return;
    }
    UserService.instance.verifyEmail(context, ott);
  }

  Future<void> showChangeLog(BuildContext context) async {
    if (_isShowingChangeLog || !mounted) {
      return;
    }
    _isShowingChangeLog = true;
    try {
      final action = await updateService.getChangeLogAction(
        locale: Localizations.localeOf(context),
        isLocalGallery: isLocalGalleryMode,
        isSignedIn: Configuration.instance.isLoggedIn(),
      );
      if (!mounted || action == ChangeLogAction.skip) {
        return;
      }
      if (action == ChangeLogAction.consumeWithoutShowing) {
        updateService.hideChangeLog().ignore();
        return;
      }
      final colorScheme = getEnteColorScheme(context);
      final sheetAction = await showBarModalBottomSheet<ChangeLogPageAction>(
        topControl: const SizedBox.shrink(),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(5),
            topRight: Radius.circular(5),
          ),
        ),
        backgroundColor: colorScheme.backgroundElevated,
        enableDrag: false,
        barrierColor: backdropFaintDark,
        context: context,
        builder: (BuildContext context) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: const ChangeLogPage(),
          );
        },
      );
      // Do not show change dialog again
      await updateService.hideChangeLog();
      if (!mounted) {
        return;
      }
      if (sheetAction == ChangeLogPageAction.openReferrals) {
        await routeToPage(context, const ReferralScreen());
      }
    } finally {
      _isShowingChangeLog = false;
    }
  }

  void _onDidReceiveNotificationResponse(
    NotificationResponse notificationResponse,
  ) async {
    if (!mounted) return;
    final String? payload = notificationResponse.payload;
    if (payload != null) {
      debugPrint('notification payload: $payload');
      final uri = Uri.tryParse(payload);
      if (uri != null &&
          (uri.host.toLowerCase() == "ritual" ||
              uri.host.toLowerCase() == "camera")) {
        final ritualId = uri.queryParameters["ritualId"] ?? "";
        final albumIdRaw = uri.queryParameters["albumId"];
        final int? albumId = albumIdRaw != null && albumIdRaw.isNotEmpty
            ? int.tryParse(albumIdRaw)
            : null;
        var canOpenRitual = true;
        if (ritualId.isNotEmpty) {
          final ritual = findRitualById(ritualId);
          canOpenRitual = ritual != null
              ? await requestHiddenRitualAccess(context, ritual)
              : await requestHiddenRitualAccessForAlbumId(context, albumId);
          if (!mounted || !canOpenRitual) {
            return;
          }
          // Ensure the camera is stacked on top of the ritual page so the user
          // lands on the ritual details after adding photos via a notification.
          // ignore: unawaited_futures
          AppNavigationService.instance.pushPage(
            RitualPage(ritualId: ritualId),
          );
        }
        if (!canOpenRitual) return;
        // ignore: unawaited_futures
        AppNavigationService.instance.pushPage(
          RitualCameraPage(ritualId: ritualId, albumId: albumId),
        );
        return;
      }
      if (uri != null && uri.host.toLowerCase() == "feed") {
        if (!Configuration.instance.isLoggedIn()) {
          return;
        }
        final target = FeedNavigationTarget.fromUri(uri);
        // ignore: unawaited_futures
        AppNavigationService.instance.pushPage(
          FeedScreen(initialTarget: target),
        );
        return;
      }
      if (payload.toLowerCase().contains("onthisday")) {
        // ignore: unawaited_futures
        memoriesCacheService.goToOnThisDayMemory();
      } else if (payload.toLowerCase().contains("birthday")) {
        final personID = payload.substring("birthday_".length);
        // ignore: unawaited_futures
        memoriesCacheService.goToPersonMemory(personID);
      } else {
        final collectionID = Uri.parse(payload).queryParameters["collectionID"];
        if (collectionID != null) {
          final collection = CollectionsService.instance.getCollectionByID(
            int.parse(collectionID),
          )!;
          final thumbnail = await CollectionsService.instance.getCover(
            collection,
          );
          // ignore: unawaited_futures
          AppNavigationService.instance.pushPage(
            CollectionPage(CollectionWithThumbnail(collection, thumbnail)),
          );
        }
      }
    }
  }

  bool _shouldEnableDrawer() {
    final isFirstImportCompleted = LocalSyncService.instance
        .hasCompletedFirstImportOrBypassed();
    return isFirstImportCompleted;
  }

  bool _shouldShowPermissionWidget() {
    return !permissionService.hasGrantedPermissions() &&
        !backupPreferenceService.hasSkippedOnboardingPermission;
  }

  bool _shouldShowLoadingWidget() {
    if (isLocalGalleryMode) {
      return false;
    }
    if (!permissionService.hasGrantedPermissions()) {
      return false;
    }
    final isFirstImportCompletedOrBypassed = LocalSyncService.instance
        .hasCompletedFirstImportOrBypassed();
    return !isFirstImportCompletedOrBypassed;
  }

  void _ensurePersonSync() {
    if (_personSyncTriggered) {
      return;
    }
    if (isLocalGalleryMode) {
      return;
    }
    _personSyncTriggered = true;
    entityService.syncEntities().then((_) {
      PersonService.instance.refreshPersonCache();
    });
  }

  void _ensureCollectionsSync() {
    if (_collectionsSyncTriggered) {
      return;
    }
    if (isLocalGalleryMode) {
      return;
    }
    if (!(backupPreferenceService.hasSkippedOnboardingPermission ||
        backupPreferenceService.isOnlyNewBackupEnabled)) {
      return;
    }
    // When first import is bypassed by skipped onboarding or only-new backup,
    // trigger collection sync here instead of waiting for the
    // completedFirstGalleryImport refresh path.
    _collectionsSyncTriggered = true;
    CollectionsService.instance.sync().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
}
