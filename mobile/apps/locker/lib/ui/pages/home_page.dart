import 'dart:async';
import 'dart:io';

import "package:app_links/app_links.dart";
import "package:ente_accounts/services/user_service.dart";
import "package:ente_components/ente_components.dart";
import 'package:ente_events/event_bus.dart';
import "package:ente_events/models/trigger_logout_event.dart";
import "package:ente_legacy/events/legacy_kit_created_event.dart";
import 'package:ente_ui/utils/dialog_util.dart';
import "package:ente_utils/email_util.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import 'package:listen_sharing_intent/listen_sharing_intent.dart';
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/events/opened_settings_event.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/models/selected_files.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/local_settings.dart';
import "package:locker/states/user_details_state.dart";
import "package:locker/ui/components/empty_state_widget.dart";
import "package:locker/ui/components/home_empty_state_widget.dart";
import "package:locker/ui/components/legacy_setup_banner.dart";
import 'package:locker/ui/components/recents_section_widget.dart';
import "package:locker/ui/components/save_to_locker_empty_state_widget.dart";
import 'package:locker/ui/components/search_result_view.dart';
import "package:locker/ui/drawer/drawer_page.dart";
import 'package:locker/ui/mixins/search_mixin.dart';
import 'package:locker/ui/pages/save_page.dart';
import 'package:locker/ui/pages/uploader_page.dart';
import "package:locker/ui/utils/legacy_utils.dart";
import "package:locker/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import 'package:locker/utils/collection_sort_util.dart';
import 'package:logging/logging.dart';

class LockerHomeHeader extends StatelessWidget {
  const LockerHomeHeader({
    super.key,
    required this.scaffoldKey,
    required this.onLegacyTapped,
    this.isSyncing = false,
  });

  final GlobalKey<ScaffoldState> scaffoldKey;
  final VoidCallback onLegacyTapped;
  final bool isSyncing;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              _LockerHeaderAction(
                onTap: () => scaffoldKey.currentState!.openDrawer(),
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedMenu01,
                  color: colors.textBase,
                ),
              ),
              Expanded(
                child: Center(
                  child: isSyncing
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  colors.textBase,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.syncing,
                              style: TextStyles.body.copyWith(
                                color: colors.textBase,
                              ),
                            ),
                          ],
                        )
                      : SvgPicture.asset(
                          'assets/svg/app-logo.svg',
                          colorFilter: ColorFilter.mode(
                            colors.textBase,
                            BlendMode.srcIn,
                          ),
                        ),
                ),
              ),
              _LockerHeaderAction(
                onTap: onLegacyTapped,
                child: SizedBox.square(
                  dimension: 24,
                  child: SvgPicture.asset(
                    'assets/svg/legacy_heartbeat_icon.svg',
                    colorFilter: ColorFilter.mode(
                      colors.textBase,
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockerHeaderAction extends StatelessWidget {
  const _LockerHeaderAction({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Center(child: child)),
      ),
    );
  }
}

class HomePage extends UploaderPage {
  final String? initialSearchQuery;

  const HomePage({super.key, this.initialSearchQuery});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends UploaderPageState<HomePage>
    with TickerProviderStateMixin, SearchMixin {
  late final _settingsPage = DrawerPage(
    emailNotifier: UserService.instance.emailValueNotifier,
    scaffoldKey: scaffoldKey,
  );
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final _selectedFiles = SelectedFiles();
  final _scrollController = ScrollController();
  final _keyboardFocusNode = FocusNode();
  bool _isLoading = true;
  bool _hasCompletedInitialLoad = false;
  bool _isSettingsOpen = false;
  bool get _isSyncing => !_hasCompletedInitialLoad || _isLoading;
  bool get _isHomeEmptyState => _error == null && _recentFiles.isEmpty;
  bool get _showsLegacySetupEmptyState =>
      _isHomeEmptyState && !_hasSetupLegacyKit;

  List<Collection> _collections = [];
  List<Collection> _filteredCollections = [];
  List<EnteFile> _recentFiles = [];
  List<EnteFile> _filteredFiles = [];
  final ValueNotifier<List<EnteFile>> _displayedFilesNotifier = ValueNotifier(
    [],
  );

  String? _error;
  // Accumulated rightward drag distance for the open-drawer swipe.
  double _drawerDragDx = 0;
  late bool _hasSetupLegacyKit;
  final _logger = Logger('HomePage');
  StreamSubscription? _mediaStreamSubscription;
  StreamSubscription<Uri>? _deepLinkSubscription;
  StreamSubscription<TriggerLogoutEvent>? _triggerLogoutSubscription;
  StreamSubscription<CollectionsUpdatedEvent>? _collectionsUpdatedSubscription;
  StreamSubscription<LegacyKitCreatedEvent>? _legacyKitCreatedSubscription;

  @override
  void onFileUploadComplete() {
    _loadCollections();
  }

  @override
  List<Collection> get allCollections => _collections;

  @override
  List<EnteFile> get allFiles => _recentFiles;

  @override
  void onSearchResultsChanged(
    List<Collection> collections,
    List<EnteFile> files,
  ) {
    if (mounted) {
      setState(() {
        _filteredCollections = _filterOutUncategorized(collections);
        _filteredFiles = files;
      });
    }
  }

  @override
  void onSearchStateChanged(bool isActive) {
    if (!isActive && mounted) {
      setState(() {
        _filteredCollections = _filterOutUncategorized(_collections);
        _filteredFiles = _recentFiles;
      });
    }
  }

  List<Collection> _filterOutUncategorized(List<Collection> collections) {
    return CollectionSortUtil.filterAndSortCollections(collections);
  }

  @override
  void initState() {
    super.initState();

    _hasSetupLegacyKit = LocalSettings.instance.hasSetupLegacyKit;

    _loadCollections();

    // Initialize sharing functionality to handle shared files
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Add a small delay to ensure the app is fully loaded
        Future.delayed(const Duration(milliseconds: 1000), () {
          if (mounted) {
            initializeSharing();
          }
        });
      }
    });

    _initDeepLinks();

    // Activate search if initial query is provided (after collections are loaded)
    if (widget.initialSearchQuery != null &&
        widget.initialSearchQuery!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Wait a bit more to ensure collections are loaded
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            activateSearchWithQuery(widget.initialSearchQuery!);
          }
        });
      });
    }

    _collectionsUpdatedSubscription = Bus.instance
        .on<CollectionsUpdatedEvent>()
        .listen((event) async {
          await _loadCollections();
        });

    _triggerLogoutSubscription = Bus.instance.on<TriggerLogoutEvent>().listen((
      event,
    ) async {
      await _autoLogoutAlert();
    });

    _legacyKitCreatedSubscription = Bus.instance
        .on<LegacyKitCreatedEvent>()
        .listen((_) => unawaited(_evaluateLegacyKit()));
  }

  Future<void> _evaluateLegacyKit() async {
    if (_hasSetupLegacyKit) return;
    if (await hasLegacyKit() != true) return;
    await LocalSettings.instance.setHasSetupLegacyKit(true);
    if (!mounted) return;
    setState(() => _hasSetupLegacyKit = true);
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    _scrollController.dispose();
    _displayedFilesNotifier.dispose();
    _selectedFiles.dispose();
    _deepLinkSubscription?.cancel();
    _triggerLogoutSubscription?.cancel();
    _collectionsUpdatedSubscription?.cancel();
    _legacyKitCreatedSubscription?.cancel();
    disposeSharing();
    super.dispose();
  }

  Future<void> _autoLogoutAlert() async {
    if (!mounted) return;

    final navigator = Navigator.of(context);
    final l10n = context.l10n;

    await showBottomSheetComponent(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => BottomSheetComponent(
        title: l10n.sessionExpired,
        message: l10n.pleaseLoginAgain,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.ok,
            onTap: () async {
              navigator.pop();
              final dialog = createProgressDialog(context, l10n.pleaseWait);
              await dialog.show();
              await Configuration.instance.logout();
              await dialog.hide();
              navigator.popUntil((route) => route.isFirst);
            },
          ),
        ],
        showCloseButton: false,
      ),
    );
  }

  void initializeSharing() {
    _logger.info('Initializing sharing functionality...');

    try {
      _mediaStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen(
            (List<SharedMediaFile> value) {
              _logger.info(
                'Received shared media files via stream: ${value.length}',
              );
              for (var file in value) {
                _logger.info('Shared file received, type: ${file.type}');
              }
              if (value.isNotEmpty) {
                _handleSharedFiles(value);
              }
            },
            onError: (err) {
              _logger.severe('Error receiving shared media: $err');
            },
          );

      _logger.info('Media stream subscription created successfully');
    } catch (e) {
      _logger.severe('Error setting up media stream: $e');
    }

    _checkInitialSharedContent();
  }

  Future<void> _checkInitialSharedContent() async {
    try {
      _logger.info('Checking for initial shared content...');

      final initialMedia = await ReceiveSharingIntent.instance
          .getInitialMedia();
      _logger.info('Initial media check result: ${initialMedia.length} files');

      if (initialMedia.isNotEmpty) {
        _logger.info(
          'Found initial shared media files: ${initialMedia.length}',
        );
        for (var file in initialMedia) {
          _logger.info('Initial shared file, type: ${file.type}');
        }
        await _handleSharedFiles(initialMedia);
      } else {
        _logger.info('No initial shared media files found');
      }
    } catch (e) {
      _logger.severe('Error checking initial shared content: $e');
    }
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> sharedFiles) async {
    _logger.info('_handleSharedFiles called with ${sharedFiles.length} files');

    if (!mounted) {
      _logger.warning('Context not mounted, cannot handle shared files');
      return;
    }

    try {
      for (final sharedFile in sharedFiles) {
        _logger.info('Processing shared file');
        if (sharedFile.path.isNotEmpty) {
          final file = File(sharedFile.path);
          if (await file.exists()) {
            _logger.info('File exists, uploading');
            await uploadFiles([file]);
          } else {
            _logger.warning('Shared file does not exist');
          }
        } else {
          _logger.warning('Shared file has empty path');
        }
      }

      await ReceiveSharingIntent.instance.reset();
      _logger.info('Reset sharing intent after handling files');
    } catch (e) {
      _logger.severe('Error handling shared files: $e');
      if (mounted) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: context.l10n.uploadError,
            message: context.l10n.somethingWentWrong,
            illustration: LockerBottomSheetIllustration.warningGrey,
            actions: [
              ButtonComponent(
                label: context.l10n.contactSupport,
                onTap: () async {
                  await sendLogs(context, "support@ente.com", postShare: () {});
                },
              ),
            ],
          ),
        );
      }
    }
  }

  void disposeSharing() {
    _mediaStreamSubscription?.cancel();
    ReceiveSharingIntent.instance.reset();
    _logger.info('Sharing functionality disposed');
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    try {
      final initialLink = await appLinks.getInitialLink();
      if (initialLink != null) {
        _logger.info('Initial deep link received');
      }
    } catch (e) {
      _logger.severe('Error getting initial deep link: $e');
    }

    _deepLinkSubscription = appLinks.uriLinkStream.listen(
      (Uri uri) {
        _logger.info('Deep link received via stream');
      },
      onError: (err) {
        _logger.severe('Error receiving deep link: $err');
      },
    );
  }

  Future<void> _loadCollections() async {
    final shouldShowLoading =
        _collections.isEmpty && _recentFiles.isEmpty && !_isLoading;

    try {
      if (mounted && (shouldShowLoading || _error != null)) {
        setState(() {
          if (shouldShowLoading) {
            _isLoading = true;
          }
          _error = null;
        });
      }

      var collections = await CollectionService.instance.getCollections();
      await _loadRecentFiles(collections);

      // If collections are empty and first sync is complete, ensure default
      // collections are created. This handles the case where default collections
      // setup was skipped during initialization due to the master key not being
      // available yet.
      final hasCompletedFirstSync = CollectionService.instance
          .hasCompletedFirstSync();
      if (collections.isEmpty && hasCompletedFirstSync) {
        _logger.info("No collections found after sync, setting up defaults");
        await CollectionService.instance.ensureDefaultCollections();
        // Reload collections after setup
        collections = await CollectionService.instance.getCollections();
        await _loadRecentFiles(collections);
      }

      final sortedCollections = CollectionSortUtil.getSortedCollections(
        collections,
      );

      if (mounted) {
        setState(() {
          _collections = sortedCollections;
          _filteredCollections = _filterOutUncategorized(sortedCollections);
          _filteredFiles = _recentFiles;
          _isLoading = false;
          _hasCompletedInitialLoad = hasCompletedFirstSync;
        });
        if (_recentFiles.isEmpty) {
          unawaited(_evaluateLegacyKit());
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Error fetching collections: $error';
          _isLoading = false;
          _hasCompletedInitialLoad = CollectionService.instance
              .hasCompletedFirstSync();
        });
      }
    }
  }

  Future<void> _loadRecentFiles(List<Collection> collections) async {
    final allFiles = <EnteFile>[];

    for (final collection in collections) {
      allFiles.addAll(
        await CollectionService.instance.getFilesInCollection(collection),
      );
    }

    final uniqueFiles = <EnteFile>[];
    final seenHashes = <String>{};
    final seenIds = <int>{};

    for (final file in allFiles) {
      bool isDuplicate = false;

      if (file.hash != null && seenHashes.contains(file.hash)) {
        isDuplicate = true;
      } else if (file.uploadedFileID != null &&
          seenIds.contains(file.uploadedFileID)) {
        isDuplicate = true;
      }

      if (!isDuplicate) {
        uniqueFiles.add(file);
        if (file.hash != null) seenHashes.add(file.hash!);
        if (file.uploadedFileID != null) seenIds.add(file.uploadedFileID!);
      }
    }

    uniqueFiles.sort((a, b) {
      final timeA = a.updationTime ?? a.modificationTime ?? 0;
      final timeB = b.updationTime ?? b.modificationTime ?? 0;
      return timeB.compareTo(timeA);
    });

    _recentFiles = uniqueFiles;
  }

  void _handleSearchChange(String query) {
    updateSearchQuery(query);
  }

  void _handleClearSearch() {
    // Clear text and unfocus before dismissing search
    searchController.clear();
    searchFocusNode.unfocus();

    dismissSearch();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return UserDetailsStateWidget(
      child: ListenableBuilder(
        listenable: _selectedFiles,
        builder: (context, _) {
          final hasSelection = _selectedFiles.files.isNotEmpty;
          return PopScope(
            canPop: !isSearchActive && !_isSettingsOpen && !hasSelection,
            onPopInvokedWithResult: (didPop, result) async {
              if (didPop) {
                return;
              }

              if (hasSelection) {
                _selectedFiles.clearAll();
                return;
              }

              if (isSearchActive) {
                _handleClearSearch();
                return;
              }

              if (_isSettingsOpen) {
                scaffoldKey.currentState!.closeDrawer();
                return;
              }
            },
            child: KeyboardListener(
              focusNode: _keyboardFocusNode,
              onKeyEvent: handleKeyEvent,
              child: Scaffold(
                key: scaffoldKey,
                backgroundColor: colors.backgroundBase,
                drawer: Drawer(
                  width: 428,
                  backgroundColor: colors.backgroundBase,
                  child: _settingsPage,
                ),
                drawerEnableOpenDragGesture: false,
                onDrawerChanged: (isOpened) {
                  _isSettingsOpen = isOpened;
                  if (isOpened) {
                    Bus.instance.fire(OpenedSettingsEvent());
                  }
                },
                body: Stack(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (_) => _drawerDragDx = 0,
                      onHorizontalDragUpdate: (details) =>
                          _drawerDragDx += details.delta.dx,
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (_drawerDragDx > 60 || velocity > 150) {
                          scaffoldKey.currentState?.openDrawer();
                        }
                      },
                      child: _buildHomeContent(),
                    ),
                    ValueListenableBuilder<List<EnteFile>>(
                      valueListenable: _displayedFilesNotifier,
                      builder: (context, displayedFiles, _) {
                        return FileSelectionOverlayBar(
                          selectedFiles: _selectedFiles,
                          files: displayedFiles.isNotEmpty
                              ? displayedFiles
                              : _recentFiles,
                          scrollController: _scrollController,
                        );
                      },
                    ),
                  ],
                ),
                floatingActionButton: isSearchActive || _isHomeEmptyState
                    ? null
                    : ListenableBuilder(
                        listenable: _selectedFiles,
                        builder: (context, _) {
                          if (_selectedFiles.files.isNotEmpty) {
                            return const SizedBox.shrink();
                          }
                          return FloatingActionButton(
                            tooltip: 'Add item',
                            onPressed: _openSavePage,
                            shape: const CircleBorder(),
                            backgroundColor: colors.primary,
                            elevation: 0,
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedPlusSign,
                              color: colors.specialWhite,
                            ),
                          );
                        },
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              EmptyStateWidget(
                assetPath: 'assets/empty_state.png',
                title: context.l10n.somethingWentWrong,
                subtitle: _error!,
                showBorder: false,
              ),
              const SizedBox(height: 20),
              ButtonComponent(
                label: context.l10n.retry,
                onTap: _loadCollections,
              ),
            ],
          ),
        ),
      );
    }

    if (isSearchActive) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: SearchResultView(
          collections: _filteredCollections,
          files: _filteredFiles,
          searchQuery: searchQuery,
          isHomePage: true,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scrollBottomPadding = MediaQuery.of(context).padding.bottom + 120;

        return _recentFiles.isEmpty
            ? _buildEmptyState(scrollBottomPadding)
            : SingleChildScrollView(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  left: 16.0,
                  right: 16.0,
                  top: 0,
                  bottom: scrollBottomPadding,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LegacySetupBanner(),
                    RecentsSectionWidget(
                      collections: _collections,
                      recentFiles: _recentFiles,
                      selectedFiles: _selectedFiles,
                      displayedFilesNotifier: _displayedFilesNotifier,
                    ),
                  ],
                ),
              );
      },
    );
  }

  Widget _buildEmptyState(double scrollBottomPadding) {
    if (_hasSetupLegacyKit && !_isSyncing) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          left: Spacing.xl,
          right: Spacing.xl,
          bottom: scrollBottomPadding,
        ),
        child: SaveToLockerEmptyStateWidget(onUploadDocument: addFile),
      );
    }
    return SizedBox.expand(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: HomeEmptyStateWidget(
            isLoading: _isSyncing,
            onSetupLegacy: () => openLegacyFromHome(context),
            onSaveToLocker: _openSavePage,
          ),
        ),
      ),
    );
  }

  Widget _buildHomeContent() {
    return Column(
      children: [
        LockerHomeHeader(
          scaffoldKey: scaffoldKey,
          onLegacyTapped: () => unawaited(openLegacyFromHome(context)),
          isSyncing: _isSyncing,
        ),
        if (!_showsLegacySetupEmptyState) _buildSearchBar(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSearchBar() {
    final colors = context.componentColors;
    final showClearIcon =
        isSearchActive || searchController.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.lg,
        top: Spacing.lg,
        right: Spacing.lg,
        bottom: Spacing.xl,
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          if (!isSearchActive) {
            activateSearchWithQuery('');
          }
        },
        child: TextInputComponent(
          controller: searchController,
          focusNode: searchFocusNode,
          hintText: context.l10n.searchHint,
          onChanged: _handleSearchChange,
          autocorrect: false,
          enableSuggestions: false,
          shouldUnfocusOnClearOrSubmit: true,
          prefix: HugeIcon(
            icon: HugeIcons.strokeRoundedSearch01,
            color: colors.primary,
            size: 20,
            strokeWidth: 1.75,
          ),
          suffix: showClearIcon
              ? HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: colors.textLight,
                  size: 18,
                )
              : null,
          onSuffixTap: showClearIcon ? _handleClearSearch : null,
        ),
      ),
    );
  }

  void _openSavePage() {
    showSaveBottomSheet(context, onUploadDocument: addFile);
  }
}
