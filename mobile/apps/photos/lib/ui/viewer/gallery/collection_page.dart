import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/events/collection_meta_event.dart";
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/files_updated_event.dart';
import "package:photos/models/collection/collection.dart";
import 'package:photos/models/collection/collection_items.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/search/hierarchical/album_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import 'package:photos/models/selected_files.dart';
import "package:photos/services/collections_service.dart";
import 'package:photos/services/ignored_files_service.dart';
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import "package:photos/ui/viewer/gallery/empty_album_state.dart";
import 'package:photos/ui/viewer/gallery/empty_state.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/hierarchical_search_gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/utils/magic_util.dart";

class CollectionPage extends StatefulWidget {
  final CollectionWithThumbnail c;
  final String tagPrefix;
  final String? coverHeroTag;
  final bool? hasVerifiedLock;
  final EnteFile? fileToJumpTo;

  const CollectionPage(
    this.c, {
    this.tagPrefix = "collection",
    this.coverHeroTag,
    this.hasVerifiedLock = false,
    this.fileToJumpTo,
    super.key,
  });

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  final _logger = Logger("CollectionPage");
  final _selectedFiles = SelectedFiles();
  final _coverAppBarKey = GlobalKey();
  late final _searchFilterDataProvider = SearchFilterDataProvider(
    initialGalleryFilter: AlbumFilter(
      collectionID: widget.c.collection.id,
      albumName: widget.c.collection.displayName,
      occurrence: kMostRelevantFilter,
    ),
  );
  late final StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatedSubscription;
  EnteFile? _cover;
  EnteFile? _defaultCover;
  late final String? _coverHeroTag;
  int _coverLoadGeneration = 0;
  int _galleryLoadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final collection = widget.c.collection;
    _cover =
        widget.c.thumbnail ??
        CollectionsService.instance.getCoverCache(collection);
    _defaultCover = _cover;
    _coverHeroTag =
        widget.coverHeroTag ??
        (_cover == null ? null : widget.tagPrefix + _cover!.tag);
    if (collection.hasCover) {
      unawaited(_loadCover());
    }
    _collectionUpdatedSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .where((event) => event.collectionID == collection.id)
        .listen((_) => _loadCover());
  }

  @override
  void dispose() {
    _collectionUpdatedSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadCover() async {
    final generation = ++_coverLoadGeneration;
    final collection = widget.c.collection;
    var cover = _defaultCover;
    if (collection.hasCover) {
      try {
        cover =
            await FilesDB.instance.getUploadedFile(
              collection.pubMagicMetadata.coverID!,
              collection.id,
            ) ??
            _defaultCover;
      } catch (e, s) {
        _logger.warning("Failed to load album cover", e, s);
      }
    }
    if (mounted && generation == _coverLoadGeneration) {
      setState(() => _cover = cover);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final tagPrefix = widget.tagPrefix;
    if (widget.hasVerifiedLock == false && c.collection.isHidden()) {
      return const EmptyState();
    }

    final galleryType = getGalleryType(
      c.collection,
      Configuration.instance.getUserID()!,
    );
    final List<EnteFile>? initialFiles = c.thumbnail != null
        ? [c.thumbnail!]
        : null;
    final appBar = GalleryAppBarWidget.sliverConfig(
      galleryType,
      c.collection.displayName,
      _selectedFiles,
      collection: c.collection,
      cover: _cover,
      coverHeroTag: _coverHeroTag,
      coverAppBarKey: _coverAppBarKey,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final generation = ++_galleryLoadGeneration;
        final FileLoadResult result = await FilesDB.instance
            .getFilesInCollection(
              c.collection.id,
              creationStartTime,
              creationEndTime,
              limit: limit,
              asc: asc,
            );
        final ignoredIDs =
            await IgnoredFilesService.instance.idToIgnoreReasonMap;
        result.files.removeWhere(
          (f) =>
              f.uploadedFileID == null &&
              IgnoredFilesService.instance.shouldSkipUpload(ignoredIDs, f),
        );
        if (mounted &&
            generation == _galleryLoadGeneration &&
            asc == (c.collection.pubMagicMetadata.asc ?? false)) {
          _defaultCover = result.files.firstOrNull;
          await _loadCover();
        }
        return result;
      },
      reloadEvent: Bus.instance.on<CollectionUpdatedEvent>().where(
        (event) => event.collectionID == c.collection.id,
      ),
      forceReloadEvents: [
        Bus.instance.on<CollectionMetaEvent>().where(
          (event) =>
              event.id == c.collection.id &&
              event.type == CollectionMetaEventType.sortChanged,
        ),
      ],
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      tagPrefix: "${tagPrefix}_files",
      selectedFiles: _selectedFiles,
      initialFiles: initialFiles,
      albumName: c.collection.displayName,
      sortAsyncFn: () => c.collection.pubMagicMetadata.asc ?? false,
      addHeaderOrFooterEmptyState: false,
      showSelectAll: true,
      groupHeaderAction: galleryType.canSort()
          ? ListenableBuilder(
              listenable: _selectedFiles,
              builder: (context, child) => _selectedFiles.files.isEmpty
                  ? child!
                  : const SizedBox.shrink(),
              child: _SortButton(c.collection),
            )
          : null,
      emptyState: galleryType == GalleryType.ownedCollection
          ? EmptyAlbumState(
              c.collection,
              onAddPhotos: () {
                Bus.instance.fire(
                  CollectionMetaEvent(
                    c.collection.id,
                    CollectionMetaEventType.autoAddPeople,
                  ),
                );
              },
            )
          : const EmptyState(),
      footer: const SizedBox(height: 212),
      fileToJumpTo: widget.fileToJumpTo,
    );

    return GalleryFilesState(
      child: InheritedSearchFilterDataWrapper(
        searchFilterDataProvider: _searchFilterDataProvider,
        child: GalleryBoundariesProvider(
          child: Scaffold(
            body: SelectionState(
              selectedFiles: _selectedFiles,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Builder(
                    builder: (context) {
                      return ValueListenableBuilder(
                        valueListenable: InheritedSearchFilterData.of(
                          context,
                        ).searchFilterDataProvider!.isSearchingNotifier,
                        builder: (context, value, _) {
                          return value
                              ? HierarchicalSearchGallery(
                                  tagPrefix: "${tagPrefix}_files",
                                  selectedFiles: _selectedFiles,
                                  appBar: appBar,
                                  hiddenCollectionID: c.collection.isHidden()
                                      ? c.collection.id
                                      : null,
                                )
                              : gallery;
                        },
                      );
                    },
                  ),
                  FileSelectionOverlayBar(
                    galleryType,
                    _selectedFiles,
                    collection: c.collection,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton(this.collection);

  final Collection collection;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return EntePopupMenuButton<bool>(
      optionsBuilder: () => [
        EntePopupMenuOption(value: false, label: strings.sortNewestFirst),
        EntePopupMenuOption(value: true, label: strings.sortOldestFirst),
      ],
      onSelected: (sortByAsc) {
        unawaited(changeSortOrder(context, collection, sortByAsc));
      },
      child: Tooltip(
        message: strings.sort,
        child: Padding(
          padding: const EdgeInsets.all(Spacing.xs),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowUpDown,
            size: IconSizes.small,
            color: context.componentColors.textLighter,
          ),
        ),
      ),
    );
  }
}
