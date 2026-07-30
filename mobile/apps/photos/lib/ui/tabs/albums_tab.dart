import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/album_sort_order_change_event.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/backup_folders_updated_event.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/favorites_service_init_complete_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/tab_changed_event.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/collections/device/device_folders_vertical_grid_view.dart";
import "package:photos/ui/collections/flex_grid_view.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/empty_state_component.dart";
import "package:photos/ui/tabs/albums/albums_manage_sheet.dart";
import "package:photos/ui/tabs/albums/empty_states/on_ente_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/received_empty_state.dart";
import "package:photos/ui/tabs/albums/empty_states/shared_empty_state.dart";
import "package:photos/ui/viewer/actions/album_selection_overlay_bar.dart";
import "package:photos/ui/viewer/actions/delete_empty_albums.dart";

enum _AlbumsFilter { ente, onDevice, shared, received }

enum _AlbumsMenuAction { toggleView, name, lastUpdated }

class AlbumsTab extends StatefulWidget {
  const AlbumsTab({
    super.key,
    this.selectedAlbums,
    this.isSearchActiveNotifier,
    this.shouldConsumeBackNotifier,
  });

  final SelectedAlbums? selectedAlbums;
  final ValueNotifier<bool>? isSearchActiveNotifier;
  final ValueNotifier<bool>? shouldConsumeBackNotifier;

  @override
  State<AlbumsTab> createState() => _AlbumsTabState();
}

class _AlbumsTabState extends State<AlbumsTab>
    with AutomaticKeepAliveClientMixin {
  static const int _kAlbumsTabIndex = 1;
  static const double _kHeaderToolbarHeight = 60;
  static const Duration _kSearchTransitionDuration = Duration(
    milliseconds: 240,
  );
  static const Duration _kContentTransitionDuration = Duration(
    milliseconds: 150,
  );
  static const double _kContentBottomPadding = 200;

  final ValueNotifier<_AlbumsFilter> _filter = ValueNotifier(
    _AlbumsFilter.ente,
  );
  final ValueNotifier<List<Collection>?> _enteCollections = ValueNotifier(null);
  final ValueNotifier<List<Collection>?> _sharedCollections = ValueNotifier(
    null,
  );
  final ValueNotifier<List<Collection>?> _receivedCollections = ValueNotifier(
    null,
  );
  final ValueNotifier<bool> _shouldShowDeleteEmptyAlbums = ValueNotifier(false);
  late final ValueNotifier<AlbumViewType> _viewType = ValueNotifier(
    localSettings.albumViewType(),
  );
  late final ValueNotifier<AlbumSortKey> _sortKey = ValueNotifier(
    localSettings.albumSortKey(),
  );
  late final ValueNotifier<AlbumSortDirection> _sortDirection = ValueNotifier(
    localSettings.albumSortDirection(),
  );
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  ScrollController _scrollController = ScrollController();
  final List<ScrollController> _retiredScrollControllers = [];

  bool _isSearchActive = false;
  String _searchQuery = "";

  late final StreamSubscription<CollectionMetaEvent>
  _collectionMetaEventSubscription;
  late final StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatesSubscription;
  late final StreamSubscription<LocalPhotosUpdatedEvent>
  _localFilesSubscription;
  late final StreamSubscription<FavoritesServiceInitCompleteEvent>
  _favoritesInitComplete;
  late final StreamSubscription<AlbumSortOrderChangeEvent>
  _albumSortOrderChangeEvent;
  late final StreamSubscription<BackupFoldersUpdatedEvent>
  _backupFoldersUpdatedEvent;
  late final StreamSubscription<AppModeChangedEvent> _appModeChangedEvent;
  late final StreamSubscription<UserLoggedOutEvent> _loggedOutEvent;
  late final StreamSubscription<TabChangedEvent> _tabChangedEvent;

  final _debouncer = Debouncer(
    const Duration(seconds: 2),
    executionInterval: const Duration(seconds: 5),
    leading: true,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadAll());

    _collectionMetaEventSubscription = Bus.instance
        .on<CollectionMetaEvent>()
        .listen((_) {
          _debouncer.run(_loadAll);
        });
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((_) {
          _debouncer.run(_loadAll);
        });
    _localFilesSubscription = Bus.instance.on<LocalPhotosUpdatedEvent>().listen(
      (_) {
        _debouncer.run(_loadAll);
      },
    );
    _albumSortOrderChangeEvent = Bus.instance
        .on<AlbumSortOrderChangeEvent>()
        .listen((_) {
          _syncSortState();
          unawaited(_loadAll());
        });
    _favoritesInitComplete = Bus.instance
        .on<FavoritesServiceInitCompleteEvent>()
        .listen((_) {
          _debouncer.run(_loadAll);
        });
    _backupFoldersUpdatedEvent = Bus.instance
        .on<BackupFoldersUpdatedEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
          _debouncer.run(_loadAll);
        });
    _appModeChangedEvent = Bus.instance.on<AppModeChangedEvent>().listen((_) {
      if (mounted) {
        setState(() {});
      }
      _debouncer.run(_loadAll);
    });
    _loggedOutEvent = Bus.instance.on<UserLoggedOutEvent>().listen((_) {
      _enteCollections.value = null;
      _sharedCollections.value = null;
      _receivedCollections.value = null;
    });
    _tabChangedEvent = Bus.instance.on<TabChangedEvent>().listen(
      _handleTabChanged,
    );
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    widget.isSearchActiveNotifier?.addListener(_handleSearchStateChanged);
    _syncSearchNotifier(_isSearchActive);
    _syncSearchBackNotifier();
  }

  @override
  void didUpdateWidget(covariant AlbumsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSearchActiveNotifier != widget.isSearchActiveNotifier) {
      oldWidget.isSearchActiveNotifier?.removeListener(
        _handleSearchStateChanged,
      );
      widget.isSearchActiveNotifier?.addListener(_handleSearchStateChanged);
      _syncSearchNotifier(_isSearchActive);
    }
    if (oldWidget.shouldConsumeBackNotifier !=
        widget.shouldConsumeBackNotifier) {
      _syncSearchBackNotifier(false, oldWidget.shouldConsumeBackNotifier);
      _syncSearchBackNotifier();
    }
  }

  void _handleSearchStateChanged() {
    if (widget.isSearchActiveNotifier?.value == false && _isSearchActive) {
      _deactivateSearch(syncNotifier: false);
    }
  }

  void _handleTabChanged(TabChangedEvent event) {
    if (event.selectedIndex != _kAlbumsTabIndex) {
      _searchFocusNode.unfocus();
    }
  }

  void _handleSearchFocusChanged() {
    _syncSearchBackNotifier();
  }

  void _syncSearchNotifier(bool isSearchActive) {
    final notifier = widget.isSearchActiveNotifier;
    if (notifier == null || notifier.value == isSearchActive) return;
    notifier.value = isSearchActive;
  }

  void _syncSearchBackNotifier([
    bool? shouldConsumeBack,
    ValueNotifier<bool>? notifier,
  ]) {
    final backNotifier = notifier ?? widget.shouldConsumeBackNotifier;
    final shouldConsume =
        shouldConsumeBack ?? (_searchFocusNode.hasFocus || _hasSearchQuery);
    if (backNotifier == null || backNotifier.value == shouldConsume) return;
    backNotifier.value = shouldConsume;
  }

  Future<void> _loadAll() async {
    if (!Configuration.instance.hasConfiguredAccount()) {
      _enteCollections.value = <Collection>[];
      _sharedCollections.value = <Collection>[];
      _receivedCollections.value = <Collection>[];
      _shouldShowDeleteEmptyAlbums.value = false;
      return;
    }
    await Future.wait([_loadEnteCollections(), _loadSharedCollections()]);
  }

  bool get _isLocalGalleryMode =>
      isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount();

  _AlbumsFilter get _effectiveFilter =>
      _isLocalGalleryMode ? _AlbumsFilter.onDevice : _filter.value;

  bool get _hasSearchQuery => _searchQuery.trim().isNotEmpty;

  void _syncSortState() {
    _sortKey.value = localSettings.albumSortKey();
    _sortDirection.value = localSettings.albumSortDirection();
    _viewType.value = localSettings.albumViewType();
  }

  Future<void> _loadEnteCollections() async {
    final collections = await CollectionsService.instance
        .getCollectionForOnEnteSection();
    final shouldShowDeleteEmptyAlbums = await _shouldShowDeleteEmptyAlbumsFor(
      collections,
    );
    if (!mounted) return;
    _shouldShowDeleteEmptyAlbums.value = shouldShowDeleteEmptyAlbums;
    _enteCollections.value = collections;
  }

  Future<bool> _shouldShowDeleteEmptyAlbumsFor(
    List<Collection> collections,
  ) async {
    if (!RemoteSyncService.instance.isFirstRemoteSyncDone()) {
      return false;
    }
    final collectionIDToLatestTimeCount = await CollectionsService.instance
        .getCollectionIDToNewestFileTime();
    final emptyAlbumCount = collections.where((collection) {
      final latestTimeCount = collectionIDToLatestTimeCount[collection.id];
      return latestTimeCount == null;
    }).length;
    return emptyAlbumCount > 2;
  }

  Future<void> _loadSharedCollections() async {
    final shared = await CollectionsService.instance.getSharedCollections();
    if (!mounted) return;
    _sharedCollections.value = shared.outgoing;
    _receivedCollections.value = shared.incoming;
  }

  void _selectFilter(_AlbumsFilter filter) {
    if (_isLocalGalleryMode && filter != _AlbumsFilter.onDevice) return;
    if (_filter.value == filter) return;
    widget.selectedAlbums?.clearAll();
    _resetScrollForNextContent();
    _filter.value = filter;
  }

  void _activateSearch() {
    if (_isSearchActive) return;
    widget.selectedAlbums?.clearAll();
    setState(() {
      _isSearchActive = true;
    });
    _syncSearchNotifier(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _deactivateSearch({bool syncNotifier = true}) {
    _searchController.clear();
    _searchFocusNode.unfocus();
    if (!_isSearchActive && _searchQuery.isEmpty) {
      _syncSearchBackNotifier(false);
      if (syncNotifier) {
        _syncSearchNotifier(false);
      }
      return;
    }
    _resetScrollForNextContent();
    setState(() {
      _isSearchActive = false;
      _searchQuery = "";
    });
    _syncSearchBackNotifier(false);
    if (syncNotifier) {
      _syncSearchNotifier(false);
    }
  }

  void _resetScrollForNextContent() {
    final oldController = _scrollController;
    _retiredScrollControllers.add(oldController);
    _scrollController = ScrollController();
    Future<void>.delayed(
      _kContentTransitionDuration + const Duration(milliseconds: 50),
      () {
        if (!_retiredScrollControllers.remove(oldController)) {
          return;
        }
        oldController.dispose();
      },
    );
  }

  List<Collection> _filterCollectionsByQuery(List<Collection> collections) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return collections;
    }
    return collections
        .where((c) => c.displayName.toLowerCase().contains(query))
        .toList();
  }

  Widget _buildCollectionContentSliver({
    required List<Collection> collections,
    required bool showCreateAlbum,
    required Widget emptyState,
    Widget? leadingSliver,
  }) {
    if (collections.isEmpty && _searchQuery.trim().isEmpty) {
      return SliverFillRemaining(hasScrollBody: false, child: emptyState);
    }

    final filteredCollections = _filterCollectionsByQuery(collections);

    return SliverMainAxisGroup(
      slivers: [
        ?leadingSliver,
        CollectionsFlexiGridViewWidget(
          filteredCollections,
          albumViewType: _viewType.value,
          selectedAlbums: widget.selectedAlbums,
          shrinkWrap: true,
          shouldShowCreateAlbum: showCreateAlbum && !_hasSearchQuery,
          enableSelectionMode: !_isSearchActive,
          bottomPadding: _kContentBottomPadding,
        ),
      ],
    );
  }

  Widget _buildDeleteEmptyAlbumsActionSlot() {
    return AnimatedSize(
      duration: _kContentTransitionDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: _kContentTransitionDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: _shouldShowDeleteEmptyAlbums.value
            ? Padding(
                key: const ValueKey("delete_empty_albums_action"),
                padding: const EdgeInsets.only(top: 8),
                child: DeleteEmptyAlbums(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onDeleted: () => _loadEnteCollections(),
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey("delete_empty_albums_hidden"),
              ),
      ),
    );
  }

  List<Widget> _buildCollectionSearchSectionSlivers({
    required String title,
    required String tag,
    required List<Collection>? collections,
  }) {
    if (collections == null) {
      return [
        SliverToBoxAdapter(child: _buildSearchSectionHeader(title)),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: EnteLoadingWidget(),
          ),
        ),
      ];
    }
    final filteredCollections = _filterCollectionsByQuery(collections);
    if (filteredCollections.isEmpty) {
      return const [];
    }
    return [
      SliverToBoxAdapter(child: _buildSearchSectionHeader(title)),
      CollectionsFlexiGridViewWidget(
        filteredCollections,
        albumViewType: _viewType.value,
        shrinkWrap: true,
        shouldShowCreateAlbum: false,
        enableSelectionMode: false,
        tag: tag,
        topPadding: 8,
        bottomPadding: 0,
      ),
    ];
  }

  Widget _buildSearchSectionHeader(String title) {
    final textTheme = getEnteTextTheme(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, top: 16),
      child: Text(
        title,
        style: TextStyles.h2.copyWith(color: textTheme.largeBold.color),
      ),
    );
  }

  Widget _buildGlobalSearchEmptyStateSliver(AppLocalizations strings) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: EmptyStateComponent(
        assetPath: "assets/empty_state_album_search.png",
        title: strings.noMatchesFound,
        textWidth: 240,
      ),
    );
  }

  Widget _buildGlobalSearchResultsSliver(AppLocalizations strings) {
    if (_isLocalGalleryMode) {
      return SliverMainAxisGroup(
        slivers: [
          DeviceFolderVerticalGridSliver(
            key: const ValueKey("album_search_local_device_folders"),
            searchQuery: _searchQuery.trim(),
            albumViewType: _viewType.value,
            sortKey: _sortKey.value,
            sortDirection: _sortDirection.value,
            showEmptyState: true,
            topPadding: 8,
            bottomPadding: 0,
            sectionHeader: _buildSearchSectionHeader(strings.onDevice),
            emptyStateSliver: _buildGlobalSearchEmptyStateSliver(strings),
          ),
          const SliverToBoxAdapter(
            child: SizedBox(height: _kContentBottomPadding),
          ),
        ],
      );
    }

    final enteCollections = _enteCollections.value;
    final sharedCollections = _sharedCollections.value;
    final receivedCollections = _receivedCollections.value;
    final filteredEnteCollections = enteCollections == null
        ? null
        : _filterCollectionsByQuery(enteCollections);
    final filteredSharedCollections = sharedCollections == null
        ? null
        : _filterCollectionsByQuery(sharedCollections);
    final filteredReceivedCollections = receivedCollections == null
        ? null
        : _filterCollectionsByQuery(receivedCollections);
    final hasRemoteCollections =
        (filteredEnteCollections?.isNotEmpty ?? false) ||
        (filteredSharedCollections?.isNotEmpty ?? false) ||
        (filteredReceivedCollections?.isNotEmpty ?? false);
    final hasFinishedLoadingRemoteCollections =
        enteCollections != null &&
        sharedCollections != null &&
        receivedCollections != null;
    final shouldShowDeviceSearchState =
        hasFinishedLoadingRemoteCollections && !hasRemoteCollections;

    return SliverMainAxisGroup(
      slivers: [
        ..._buildCollectionSearchSectionSlivers(
          title: strings.ente,
          tag: "album_search_ente",
          collections: filteredEnteCollections,
        ),
        DeviceFolderVerticalGridSliver(
          key: const ValueKey("album_search_device_folders"),
          searchQuery: _searchQuery.trim(),
          albumViewType: _viewType.value,
          sortKey: _sortKey.value,
          sortDirection: _sortDirection.value,
          showEmptyState: shouldShowDeviceSearchState,
          topPadding: 8,
          bottomPadding: 0,
          sectionHeader: _buildSearchSectionHeader(strings.onDevice),
          emptyStateSliver: shouldShowDeviceSearchState
              ? _buildGlobalSearchEmptyStateSliver(strings)
              : null,
        ),
        ..._buildCollectionSearchSectionSlivers(
          title: strings.sharedAlbumsLabel,
          tag: "album_search_shared",
          collections: filteredSharedCollections,
        ),
        ..._buildCollectionSearchSectionSlivers(
          title: strings.receivedAlbumsLabel,
          tag: "album_search_received",
          collections: filteredReceivedCollections,
        ),
        const SliverToBoxAdapter(
          child: SizedBox(height: _kContentBottomPadding),
        ),
      ],
    );
  }

  Widget _buildContentSliver(AppLocalizations strings) {
    if (_hasSearchQuery) {
      return _buildGlobalSearchResultsSliver(strings);
    }
    final filter = _effectiveFilter;
    final List<Collection>? collections;
    final bool showCreateAlbum;
    final Widget emptyState;
    switch (filter) {
      case _AlbumsFilter.ente:
        collections = _enteCollections.value;
        showCreateAlbum = true;
        emptyState = const OnEnteEmptyState();
      case _AlbumsFilter.shared:
        collections = _sharedCollections.value;
        showCreateAlbum = false;
        emptyState = const SharedEmptyState();
      case _AlbumsFilter.received:
        collections = _receivedCollections.value;
        showCreateAlbum = false;
        emptyState = const ReceivedEmptyState();
      case _AlbumsFilter.onDevice:
        return DeviceFolderVerticalGridSliver(
          searchQuery: _searchQuery.trim(),
          albumViewType: _viewType.value,
          sortKey: _sortKey.value,
          sortDirection: _sortDirection.value,
          bottomPadding: _kContentBottomPadding,
        );
    }
    if (collections == null) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: EnteLoadingWidget(),
        ),
      );
    }
    return _buildCollectionContentSliver(
      collections: collections,
      showCreateAlbum: showCreateAlbum,
      emptyState: emptyState,
      leadingSliver: filter == _AlbumsFilter.ente && !_hasSearchQuery
          ? SliverToBoxAdapter(child: _buildDeleteEmptyAlbumsActionSlot())
          : null,
    );
  }

  Key _contentStateKey() {
    final contentPhase = switch (_effectiveFilter) {
      _AlbumsFilter.ente =>
        _enteCollections.value == null ? "ente_loading" : "ente_ready",
      _AlbumsFilter.shared =>
        _sharedCollections.value == null ? "shared_loading" : "shared_ready",
      _AlbumsFilter.received =>
        _receivedCollections.value == null
            ? "received_loading"
            : "received_ready",
      _AlbumsFilter.onDevice => "device",
    };

    return ValueKey<Object>((
      _hasSearchQuery ? "search" : "filter",
      _effectiveFilter,
      _viewType.value,
      contentPhase,
    ));
  }

  Future<void> _toggleViewMode() async {
    final next = _viewType.value == AlbumViewType.grid
        ? AlbumViewType.list
        : AlbumViewType.grid;
    _viewType.value = next;
    await localSettings.setAlbumViewType(next);
  }

  Future<void> _setSortMode(AlbumSortKey key) async {
    AlbumSortDirection nextDirection;
    if (_sortKey.value == key) {
      nextDirection = _sortDirection.value == AlbumSortDirection.ascending
          ? AlbumSortDirection.descending
          : AlbumSortDirection.ascending;
    } else {
      nextDirection = AlbumSortDirection.ascending;
    }

    _sortKey.value = key;
    _sortDirection.value = nextDirection;
    await localSettings.setAlbumSortKey(key);
    await localSettings.setAlbumSortDirection(nextDirection);
    if (mounted) {
      Bus.instance.fire(AlbumSortOrderChangeEvent());
    }
  }

  List<EntePopupMenuOption<_AlbumsMenuAction>> _buildAlbumsMenuOptions() {
    final colorScheme = getEnteColorScheme(context);
    final strings = AppLocalizations.of(context);
    final isListView = _viewType.value == AlbumViewType.list;
    final showSortActions = !_hasSearchQuery;
    final currentSortKey = _sortKey.value;
    final currentSortDirection = _sortDirection.value;
    final nameSortDirection = currentSortKey == AlbumSortKey.albumName
        ? currentSortDirection
        : null;
    final activeTrailingWidget = HugeIcon(
      icon: currentSortDirection == AlbumSortDirection.ascending
          ? HugeIcons.strokeRoundedArrowUp02
          : HugeIcons.strokeRoundedArrowDown02,
      size: 12,
      strokeWidth: 3,
      color: colorScheme.textMuted,
    );

    return [
      EntePopupMenuOption(
        value: _AlbumsMenuAction.toggleView,
        label: isListView ? strings.grid : strings.list,
        showDivider: showSortActions,
        trailingWidget: HugeIcon(
          icon: isListView
              ? HugeIcons.strokeRoundedGridView
              : HugeIcons.strokeRoundedMenu01,
          size: 12,
          strokeWidth: 3,
          color: colorScheme.contentLight,
        ),
      ),
      if (showSortActions) ...[
        EntePopupMenuOption(
          value: _AlbumsMenuAction.name,
          label: strings.name,
          secondaryLabel: nameSortDirection != AlbumSortDirection.descending
              ? strings.sortAToZ
              : strings.sortZToA,
          isActive: currentSortKey == AlbumSortKey.albumName,
        ),
        EntePopupMenuOption(
          value: _AlbumsMenuAction.lastUpdated,
          label: strings.lastUpdated,
          isActive: currentSortKey == AlbumSortKey.lastUpdated,
          activeTrailingWidget: activeTrailingWidget,
          showDivider: false,
        ),
      ],
    ];
  }

  Future<void> _handleAlbumsMenuSelection(_AlbumsMenuAction selected) async {
    switch (selected) {
      case _AlbumsMenuAction.toggleView:
        await _toggleViewMode();
        break;
      case _AlbumsMenuAction.name:
        await _setSortMode(AlbumSortKey.albumName);
        break;
      case _AlbumsMenuAction.lastUpdated:
        await _setSortMode(AlbumSortKey.lastUpdated);
        break;
    }
  }

  Future<void> _showAlbumsOptionsMenu(BuildContext buttonContext) async {
    final options = _buildAlbumsMenuOptions();
    if (options.isEmpty) {
      return;
    }
    final selected = await showEntePopupMenu<_AlbumsMenuAction>(
      context: buttonContext,
      options: options,
    );
    if (selected == null || !mounted) return;
    await _handleAlbumsMenuSelection(selected);
  }

  @override
  void dispose() {
    _collectionMetaEventSubscription.cancel();
    _collectionUpdatesSubscription.cancel();
    _localFilesSubscription.cancel();
    _favoritesInitComplete.cancel();
    _albumSortOrderChangeEvent.cancel();
    _backupFoldersUpdatedEvent.cancel();
    _appModeChangedEvent.cancel();
    _loggedOutEvent.cancel();
    _tabChangedEvent.cancel();
    widget.isSearchActiveNotifier?.removeListener(_handleSearchStateChanged);
    _syncSearchBackNotifier(false);
    _searchFocusNode.removeListener(_handleSearchFocusChanged);
    _debouncer.cancelDebounceTimer();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    for (final controller in _retiredScrollControllers) {
      controller.dispose();
    }
    _retiredScrollControllers.clear();
    _filter.dispose();
    _enteCollections.dispose();
    _sharedCollections.dispose();
    _receivedCollections.dispose();
    _shouldShowDeleteEmptyAlbums.dispose();
    _viewType.dispose();
    _sortKey.dispose();
    _sortDirection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final componentColors = context.componentColors;
    final textTheme = getEnteTextTheme(context);
    final strings = AppLocalizations.of(context);
    final selectedAlbums = widget.selectedAlbums;
    final localGalleryMode = _isLocalGalleryMode;
    final albumsOptionsButton = Builder(
      builder: (buttonContext) => IconButtonComponent(
        variant: IconButtonComponentVariant.primary,
        shouldSurfaceExecutionStates: false,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedFilterHorizontal),
        onTap: () => unawaited(_showAlbumsOptionsMenu(buttonContext)),
      ),
    );
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: _kHeaderToolbarHeight,
                  child: AnimatedSwitcher(
                    duration: _kSearchTransitionDuration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    layoutBuilder: (currentChild, previousChildren) => Stack(
                      alignment: Alignment.centerLeft,
                      children: [...previousChildren, ?currentChild],
                    ),
                    transitionBuilder: (child, animation) {
                      final curvedAnimation = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final beginOffset =
                          child.key == const ValueKey("albums_search_toolbar")
                          ? const Offset(0.035, 0)
                          : const Offset(-0.035, 0);
                      return FadeTransition(
                        opacity: curvedAnimation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: beginOffset,
                            end: Offset.zero,
                          ).animate(curvedAnimation),
                          child: child,
                        ),
                      );
                    },
                    child: _isSearchActive
                        ? Row(
                            key: const ValueKey("albums_search_toolbar"),
                            children: [
                              Expanded(
                                child: TextInputComponent(
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  hintText: strings.searchAlbums,
                                  autofocus: true,
                                  shouldUnfocusOnClearOrSubmit: true,
                                  prefix: HugeIcon(
                                    icon: HugeIcons.strokeRoundedSearch01,
                                    size: 18,
                                    color: componentColors.textLight,
                                  ),
                                  suffix: HugeIcon(
                                    icon: HugeIcons.strokeRoundedCancel01,
                                    size: 18,
                                    color: componentColors.textLight,
                                  ),
                                  onSuffixTap: _deactivateSearch,
                                  onChanged: (value) {
                                    final hadSearchQuery = _hasSearchQuery;
                                    if (!hadSearchQuery &&
                                        value.trim().isNotEmpty) {
                                      _resetScrollForNextContent();
                                    }
                                    setState(() {
                                      _searchQuery = value;
                                    });
                                    _syncSearchBackNotifier();
                                  },
                                ),
                              ),
                            ],
                          )
                        : Row(
                            key: const ValueKey("albums_title_toolbar"),
                            children: [
                              Expanded(
                                child: Text(
                                  strings.albums,
                                  key: const ValueKey("albums_title"),
                                  style: TextStyles.display1.copyWith(
                                    color: textTheme.h4Bold.color,
                                  ),
                                ),
                              ),
                              IconButtonComponent(
                                variant: IconButtonComponentVariant.primary,
                                shouldSurfaceExecutionStates: false,
                                icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedSearch01,
                                ),
                                onTap: _activateSearch,
                              ),
                              const SizedBox(width: 6),
                              albumsOptionsButton,
                            ],
                          ),
                  ),
                ),
              ),
              AnimatedSize(
                duration: _kSearchTransitionDuration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: _kSearchTransitionDuration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _isSearchActive || localGalleryMode
                      ? const SizedBox.shrink(key: ValueKey("hidden_filters"))
                      : Padding(
                          key: const ValueKey("album_filters"),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: ValueListenableBuilder<_AlbumsFilter>(
                                  valueListenable: _filter,
                                  builder: (context, selected, _) {
                                    final effectiveFilter = localGalleryMode
                                        ? _AlbumsFilter.onDevice
                                        : selected;
                                    return Stack(
                                      children: [
                                        SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          physics:
                                              const BouncingScrollPhysics(),
                                          padding: const EdgeInsets.only(
                                            right: 72,
                                          ),
                                          child: Row(
                                            children: [
                                              if (!localGalleryMode) ...[
                                                _AlbumsFilterChip(
                                                  label: strings.ente,
                                                  selected:
                                                      effectiveFilter ==
                                                      _AlbumsFilter.ente,
                                                  onTap: () => _selectFilter(
                                                    _AlbumsFilter.ente,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                              ],
                                              _AlbumsFilterChip(
                                                label: strings.onDevice,
                                                selected:
                                                    effectiveFilter ==
                                                    _AlbumsFilter.onDevice,
                                                onTap: () => _selectFilter(
                                                  _AlbumsFilter.onDevice,
                                                ),
                                              ),
                                              if (!localGalleryMode) ...[
                                                const SizedBox(width: 8),
                                                _AlbumsFilterChip(
                                                  label:
                                                      strings.sharedAlbumsLabel,
                                                  selected:
                                                      effectiveFilter ==
                                                      _AlbumsFilter.shared,
                                                  onTap: () => _selectFilter(
                                                    _AlbumsFilter.shared,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                _AlbumsFilterChip(
                                                  label: strings
                                                      .receivedAlbumsLabel,
                                                  selected:
                                                      effectiveFilter ==
                                                      _AlbumsFilter.received,
                                                  onTap: () => _selectFilter(
                                                    _AlbumsFilter.received,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        _AlbumsMoreButtonOverlay(
                                          tooltip: strings.more,
                                          onTap: () =>
                                              showAlbumsManageSheet(context),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
              Expanded(
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _filter,
                    _enteCollections,
                    _sharedCollections,
                    _receivedCollections,
                    _shouldShowDeleteEmptyAlbums,
                    _viewType,
                    _sortKey,
                    _sortDirection,
                  ]),
                  builder: (context, _) {
                    return AnimatedSwitcher(
                      duration: _kContentTransitionDuration,
                      reverseDuration: _kContentTransitionDuration,
                      switchInCurve: Curves.easeInQuart,
                      switchOutCurve: Curves.easeOutExpo,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          fit: StackFit.expand,
                          children: [
                            for (final previousChild in previousChildren)
                              Positioned.fill(child: previousChild),
                            if (currentChild != null)
                              Positioned.fill(child: currentChild),
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        return FadeTransition(opacity: animation, child: child);
                      },
                      child: Scrollbar(
                        key: _contentStateKey(),
                        controller: _scrollController,
                        interactive: true,
                        child: CustomScrollView(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          slivers: [_buildContentSliver(strings)],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (selectedAlbums != null && !_isSearchActive)
          AnimatedBuilder(
            animation: Listenable.merge([
              _filter,
              _enteCollections,
              _sharedCollections,
              _receivedCollections,
            ]),
            builder: (context, _) {
              final filter = _effectiveFilter;
              final UISectionType sectionType;
              final List<Collection>? collections;
              switch (filter) {
                case _AlbumsFilter.ente:
                  sectionType = UISectionType.homeCollections;
                  collections = _enteCollections.value;
                case _AlbumsFilter.shared:
                  sectionType = UISectionType.outgoingCollections;
                  collections = _sharedCollections.value;
                case _AlbumsFilter.received:
                  sectionType = UISectionType.incomingCollections;
                  collections = _receivedCollections.value;
                case _AlbumsFilter.onDevice:
                  return const SizedBox.shrink();
              }
              if (collections == null) return const SizedBox.shrink();
              final filteredCollections = _filterCollectionsByQuery(
                collections,
              );
              if (filteredCollections.isEmpty) return const SizedBox.shrink();
              return AlbumSelectionOverlayBar(
                selectedAlbums,
                sectionType,
                filteredCollections,
                showSelectAllButton: true,
              );
            },
          ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _AlbumsFilterChip extends StatelessWidget {
  const _AlbumsFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TagChipComponent(
      label: label,
      state: selected
          ? TagChipComponentState.selected
          : TagChipComponentState.unselected,
      onTap: onTap,
    );
  }
}

class _AlbumsMoreButtonOverlay extends StatelessWidget {
  const _AlbumsMoreButtonOverlay({required this.tooltip, required this.onTap});

  final String tooltip;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final componentColors = context.componentColors;
    final maskColor = componentColors.backgroundBase;

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: SizedBox(
                width: 72,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        maskColor,
                        maskColor.withValues(alpha: 0.92),
                        maskColor.withValues(alpha: 0.55),
                        maskColor.withValues(alpha: 0.12),
                        maskColor.withValues(alpha: 0),
                      ],
                      stops: const [0, 0.3, 0.55, 0.8, 1],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 4,
            right: 0,
            child: IconButtonComponent(
              variant: IconButtonComponentVariant.primary,
              shouldSurfaceExecutionStates: false,
              tooltip: tooltip,
              icon: const Icon(Icons.keyboard_arrow_down, size: 18),
              onTap: onTap,
            ),
          ),
        ],
      ),
    );
  }
}
