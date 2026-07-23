import "dart:async";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/album_sort_order_change_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/collection/collection_items.dart';
import "package:photos/models/selected_albums.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/flex_grid_view.dart";
import "package:photos/ui/components/searchable_appbar.dart";
import "package:photos/ui/viewer/actions/album_selection_overlay_bar.dart";

enum UISectionType {
  incomingCollections,
  outgoingCollections,
  homeCollections,
  archivedCollections,
  hiddenCollections,
}

enum _CollectionListMenuAction { toggleView, name, newest, updated }

class CollectionListPage extends StatefulWidget {
  final List<Collection>? collections;
  final Widget? appTitle;
  final double? initialScrollOffset;
  final String tag;
  final UISectionType sectionType;
  final bool startInSearchMode;

  const CollectionListPage(
    this.collections, {
    required this.sectionType,
    this.appTitle,
    this.initialScrollOffset,
    this.tag = "",
    this.startInSearchMode = false,
    super.key,
  });

  @override
  State<CollectionListPage> createState() => _CollectionListPageState();
}

class _CollectionListPageState extends State<CollectionListPage> {
  late StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatesSubscription;
  List<Collection>? collections;
  late AlbumSortKey sortKey;
  AlbumViewType? albumViewType;
  late AlbumSortDirection albumSortDirection;
  String _searchQuery = "";
  final _selectedAlbum = SelectedAlbums();
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    collections = widget.collections;
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((event) async {
          unawaited(refreshCollections());
        });
    sortKey = localSettings.albumSortKey();
    albumViewType = localSettings.albumViewType();
    albumSortDirection = localSettings.albumSortDirection();
    _scrollController = ScrollController(
      initialScrollOffset: widget.initialScrollOffset ?? 0,
    );
    unawaited(refreshCollections());
  }

  @override
  void dispose() {
    _collectionUpdatesSubscription.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool enableSelectionMode =
        widget.sectionType == UISectionType.homeCollections ||
        widget.sectionType == UISectionType.outgoingCollections ||
        widget.sectionType == UISectionType.incomingCollections ||
        widget.sectionType == UISectionType.archivedCollections ||
        widget.sectionType == UISectionType.hiddenCollections;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            Scrollbar(
              interactive: true,
              controller: _scrollController,
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                controller: _scrollController,
                slivers: [
                  SearchableAppBar(
                    searchIconPadding: const EdgeInsets.only(right: 8),
                    title: widget.appTitle ?? const SizedBox.shrink(),
                    heroTag: widget.tag,
                    autoActivateSearch: widget.startInSearchMode,
                    pinned: true,
                    onSearch: (value) {
                      _searchQuery = value;
                      unawaited(refreshCollections());
                    },
                    onSearchClosed: () {
                      _searchQuery = '';
                      unawaited(refreshCollections());
                    },
                    actions: [_sortMenu()],
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                  CollectionsFlexiGridViewWidget(
                    collections,
                    tag: widget.tag,
                    enableSelectionMode: enableSelectionMode,
                    albumViewType: albumViewType ?? AlbumViewType.grid,
                    selectedAlbums: _selectedAlbum,
                    sectionType: widget.sectionType,
                  ),
                ],
              ),
            ),
            AlbumSelectionOverlayBar(
              _selectedAlbum,
              widget.sectionType,
              collections!,
              showSelectAllButton: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sortMenu() {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: EntePopupMenuButton<_CollectionListMenuAction>(
        optionsBuilder: _buildMenuOptions,
        onSelected: _handleMenuSelection,
      ),
    );
  }

  List<EntePopupMenuOption<_CollectionListMenuAction>> _buildMenuOptions() {
    final colorScheme = getEnteColorScheme(context);
    final strings = AppLocalizations.of(context);
    final currentViewType = albumViewType ?? localSettings.albumViewType();
    final isListView = currentViewType == AlbumViewType.list;
    final currentSortKey = sortKey;
    final currentSortDirection = albumSortDirection;
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
        value: _CollectionListMenuAction.toggleView,
        label: isListView ? strings.grid : strings.list,
        trailingWidget: HugeIcon(
          icon: isListView
              ? HugeIcons.strokeRoundedGridView
              : HugeIcons.strokeRoundedMenu01,
          size: 12,
          strokeWidth: 3,
          color: colorScheme.contentLight,
        ),
      ),
      EntePopupMenuOption(
        value: _CollectionListMenuAction.name,
        label: strings.name,
        secondaryLabel: nameSortDirection != AlbumSortDirection.descending
            ? strings.sortAToZ
            : strings.sortZToA,
        isActive: currentSortKey == AlbumSortKey.albumName,
        activeTrailingWidget: activeTrailingWidget,
      ),
      EntePopupMenuOption(
        value: _CollectionListMenuAction.newest,
        label: strings.newest,
        isActive: currentSortKey == AlbumSortKey.newestPhoto,
        activeTrailingWidget: activeTrailingWidget,
      ),
      EntePopupMenuOption(
        value: _CollectionListMenuAction.updated,
        label: strings.updated,
        isActive: currentSortKey == AlbumSortKey.lastUpdated,
        activeTrailingWidget: activeTrailingWidget,
        showDivider: false,
      ),
    ];
  }

  Future<void> _handleMenuSelection(_CollectionListMenuAction selected) async {
    switch (selected) {
      case _CollectionListMenuAction.toggleView:
        await _toggleViewMode();
        break;
      case _CollectionListMenuAction.name:
        await _setSortMode(AlbumSortKey.albumName);
        break;
      case _CollectionListMenuAction.newest:
        await _setSortMode(AlbumSortKey.newestPhoto);
        break;
      case _CollectionListMenuAction.updated:
        await _setSortMode(AlbumSortKey.lastUpdated);
        break;
    }
  }

  Future<void> _toggleViewMode() async {
    final next =
        (albumViewType ?? localSettings.albumViewType()) == AlbumViewType.grid
        ? AlbumViewType.list
        : AlbumViewType.grid;
    setState(() {
      albumViewType = next;
    });
    await localSettings.setAlbumViewType(next);
  }

  Future<void> _setSortMode(AlbumSortKey key) async {
    final currentSortKey = sortKey;
    final currentSortDirection = albumSortDirection;
    final AlbumSortDirection nextDirection;
    if (currentSortKey == key) {
      nextDirection = currentSortDirection == AlbumSortDirection.ascending
          ? AlbumSortDirection.descending
          : AlbumSortDirection.ascending;
    } else {
      nextDirection = AlbumSortDirection.ascending;
    }

    sortKey = key;
    albumSortDirection = nextDirection;
    await localSettings.setAlbumSortKey(key);
    await localSettings.setAlbumSortDirection(nextDirection);
    await refreshCollections();
    Bus.instance.fire(AlbumSortOrderChangeEvent());
  }

  Future<void> refreshCollections() async {
    if (widget.sectionType == UISectionType.incomingCollections ||
        widget.sectionType == UISectionType.outgoingCollections) {
      final SharedCollections sharedCollections = await CollectionsService
          .instance
          .getSharedCollections();
      if (widget.sectionType == UISectionType.incomingCollections) {
        collections = sharedCollections.incoming;
      } else {
        collections = sharedCollections.outgoing;
      }
    } else if (widget.sectionType == UISectionType.homeCollections) {
      collections = await CollectionsService.instance
          .getCollectionForOnEnteSection();
    } else if (widget.sectionType == UISectionType.archivedCollections) {
      collections = await CollectionsService.instance.getArchivedCollection();
    } else if (widget.sectionType == UISectionType.hiddenCollections) {
      collections = CollectionsService.instance.getHiddenCollections(
        includeDefaultHidden: false,
      );
    }
    if (_searchQuery.isNotEmpty) {
      collections = collections
          ?.where(
            (c) => c.displayName.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ),
          )
          .toList();
    }
    if (widget.sectionType == UISectionType.archivedCollections ||
        widget.sectionType == UISectionType.hiddenCollections) {
      await _sortCollectionsByCurrentPreferences(collections!);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _sortCollectionsByCurrentPreferences(
    List<Collection> collectionsToSort,
  ) async {
    if (collectionsToSort.length < 2) {
      return;
    }

    final currentSortKey = sortKey;
    final currentSortDirection = albumSortDirection;

    Map<int, int>? collectionIDToNewestPhotoTime;
    if (currentSortKey == AlbumSortKey.newestPhoto) {
      collectionIDToNewestPhotoTime = await CollectionsService.instance
          .getCollectionIDToNewestFileTime();
    }

    collectionsToSort.sort((first, second) {
      int comparison;
      if (currentSortKey == AlbumSortKey.albumName) {
        comparison = compareAsciiLowerCaseNatural(
          first.displayName,
          second.displayName,
        );
      } else if (currentSortKey == AlbumSortKey.newestPhoto) {
        comparison =
            (collectionIDToNewestPhotoTime?[second.id] ?? -1 * intMaxValue)
                .compareTo(
                  collectionIDToNewestPhotoTime?[first.id] ?? -1 * intMaxValue,
                );
      } else {
        comparison = second.updationTime.compareTo(first.updationTime);
      }
      return currentSortDirection == AlbumSortDirection.ascending
          ? comparison
          : -comparison;
    });
  }
}
