import "dart:async";

import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/album_sort_order_change_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/hidden_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/collections/album/horizontal_list.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/empty_state_component.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/cleanup_hidden_files_widget.dart";
import "package:photos/ui/viewer/gallery/cleanup_hidden_from_device_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class HiddenPage extends StatefulWidget {
  final String tagPrefix;
  final GalleryType appBarType;
  final GalleryType overlayType;

  const HiddenPage({
    this.tagPrefix = "hidden_page",
    this.appBarType = GalleryType.hiddenSection,
    this.overlayType = GalleryType.hiddenSection,
    super.key,
  });

  @override
  State<HiddenPage> createState() => _HiddenPageState();
}

class _HiddenPageState extends State<HiddenPage> {
  int? _defaultHiddenCollectionId;
  final _hiddenCollectionsExcludingDefault = <Collection>[];
  bool _hasFilesNeedingCleanup = false;
  bool _hasHiddenFilesOnDevice = false;
  late StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatesSubscription;
  late StreamSubscription<AlbumSortOrderChangeEvent> _albumSortOrderChangeEvent;

  @override
  void initState() {
    super.initState();
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((event) {
          unawaited(_refreshHiddenCollections());
          _checkForCleanupNeeded();
          _checkForDeviceCleanupNeeded();
        });
    _albumSortOrderChangeEvent = Bus.instance
        .on<AlbumSortOrderChangeEvent>()
        .listen((event) {
          unawaited(_refreshHiddenCollections());
        });
    unawaited(_refreshHiddenCollections());
    _checkForCleanupNeeded();
    _checkForDeviceCleanupNeeded();
  }

  Future<void> _checkForCleanupNeeded() async {
    final hasCleanup = await CollectionsService.instance
        .hasFilesNeedingHiddenCleanup();
    if (mounted && hasCleanup != _hasFilesNeedingCleanup) {
      setState(() {
        _hasFilesNeedingCleanup = hasCleanup;
      });
    }
  }

  Future<void> _checkForDeviceCleanupNeeded() async {
    final hasDeviceFiles = await CollectionsService.instance
        .hasHiddenFilesOnDevice();
    if (mounted && hasDeviceFiles != _hasHiddenFilesOnDevice) {
      setState(() {
        _hasHiddenFilesOnDevice = hasDeviceFiles;
      });
    }
  }

  Future<void> _refreshHiddenCollections() async {
    final hiddenCollections = CollectionsService.instance
        .getHiddenCollections();
    final defaultHiddenCollection = await CollectionsService.instance
        .getDefaultHiddenCollection();
    final hiddenCollectionsExcludingDefault = hiddenCollections
        .where((c) => c.id != defaultHiddenCollection.id)
        .toList();
    await _sortCollectionsByCurrentPreferences(
      hiddenCollectionsExcludingDefault,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _hiddenCollectionsExcludingDefault
        ..clear()
        ..addAll(hiddenCollectionsExcludingDefault);
      _defaultHiddenCollectionId = defaultHiddenCollection.id;
    });
  }

  Future<void> _sortCollectionsByCurrentPreferences(
    List<Collection> collectionsToSort,
  ) async {
    if (collectionsToSort.length < 2) {
      return;
    }
    final currentSortKey = localSettings.albumSortKey();
    final currentSortDirection = localSettings.albumSortDirection();

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

  @override
  void dispose() {
    _collectionUpdatesSubscription.cancel();
    _albumSortOrderChangeEvent.cancel();
    super.dispose();
  }

  final _selectedFiles = SelectedFiles();

  @override
  Widget build(BuildContext context) {
    if (_defaultHiddenCollectionId == null) {
      return const EnteLoadingWidget();
    }
    final appBar = GalleryAppBarWidget.sliverConfig(
      widget.appBarType,
      AppLocalizations.of(context).hidden,
      _selectedFiles,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
        return FilesDB.instance.getFilesInCollections(
          [_defaultHiddenCollectionId!],
          creationStartTime,
          creationEndTime,
          Configuration.instance.getUserID()!,
          limit: limit,
          asc: asc,
        );
      },
      reloadEvent: Bus.instance.on<FilesUpdatedEvent>().where(
        (event) =>
            event.updatedFiles.firstWhereOrNull(
              (element) => element.uploadedFileID != null,
            ) !=
            null,
      ),
      removalEventTypes: const {
        EventType.unhide,
        EventType.deletedFromEverywhere,
        EventType.deletedFromRemote,
      },
      forceReloadEvents: [
        Bus.instance.on<FilesUpdatedEvent>().where(
          (event) =>
              event.updatedFiles.firstWhereOrNull(
                (element) => element.uploadedFileID != null,
              ) !=
              null,
        ),
      ],
      tagPrefix: widget.tagPrefix,
      selectedFiles: _selectedFiles,
      initialFiles: null,
      emptyState: _hiddenCollectionsExcludingDefault.isEmpty
          ? EmptyStateComponent(
              assetPath: "assets/empty_state_hidden.png",
              title: AppLocalizations.of(context).hiddenItemsWillShowUpHere,
            )
          : const SizedBox.shrink(),
      header: Column(
        children: [
          RepaintBoundary(
            child: AnimatedCrossFade(
              firstCurve: Curves.easeInOutQuart,
              secondCurve: Curves.easeInOutQuart,
              sizeCurve: Curves.easeInOutQuart,
              firstChild: CleanupHiddenFilesWidget(
                onCleanupComplete: () => _checkForCleanupNeeded(),
              ),
              secondChild: const SizedBox(width: double.infinity),
              crossFadeState: _hasFilesNeedingCleanup
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 750),
            ),
          ),
          RepaintBoundary(
            child: AnimatedCrossFade(
              firstCurve: Curves.easeInOutQuart,
              secondCurve: Curves.easeInOutQuart,
              sizeCurve: Curves.easeInOutQuart,
              firstChild: CleanupHiddenFromDeviceWidget(
                onCleanupComplete: () => _checkForDeviceCleanupNeeded(),
              ),
              secondChild: const SizedBox(width: double.infinity),
              crossFadeState: _hasHiddenFilesOnDevice
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 750),
            ),
          ),
          AlbumHorizontalList(
            () async {
              return _hiddenCollectionsExcludingDefault;
            },
            hasVerifiedLock: true,
            onViewAllTapped: () async {
              await routeToPage(
                context,
                CollectionListPage(
                  _hiddenCollectionsExcludingDefault,
                  sectionType: UISectionType.hiddenCollections,
                  appTitle: Text(AppLocalizations.of(context).hidden),
                  tag: "hidden",
                ),
              );
            },
          ),
        ],
      ),
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: SelectionState(
            selectedFiles: _selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                gallery,
                FileSelectionOverlayBar(widget.overlayType, _selectedFiles),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
