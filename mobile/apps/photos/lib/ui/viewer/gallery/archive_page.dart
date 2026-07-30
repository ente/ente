import "dart:async";

import 'package:collection/collection.dart' show IterableExtension;
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/events/collection_updated_event.dart";
import 'package:photos/events/files_updated_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/metadata/common_keys.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/services/collections_service.dart';
import "package:photos/services/filter/db_filters.dart";
import "package:photos/ui/collections/album/horizontal_list.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/empty_state_component.dart";
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart';
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class ArchivePage extends StatefulWidget {
  final String tagPrefix;
  final GalleryType appBarType;
  final GalleryType overlayType;

  const ArchivePage({
    this.tagPrefix = "archived_page",
    this.appBarType = GalleryType.archive,
    this.overlayType = GalleryType.archive,
    super.key,
  });

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  final _selectedFiles = SelectedFiles();
  final _archivedCollections = <Collection>[];
  late StreamSubscription<CollectionUpdatedEvent>
  _collectionUpdatesSubscription;

  @override
  void initState() {
    super.initState();
    _collectionUpdatesSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .listen((event) {
          unawaited(_refreshArchivedCollections());
        });
    unawaited(_refreshArchivedCollections());
  }

  @override
  void dispose() {
    _collectionUpdatesSubscription.cancel();
    super.dispose();
  }

  Future<void> _refreshArchivedCollections() async {
    final archivedCollections = await CollectionsService.instance
        .getArchivedCollection();
    if (!mounted) {
      return;
    }
    setState(() {
      _archivedCollections
        ..clear()
        ..addAll(archivedCollections);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Set<int> hiddenCollectionIDs = CollectionsService.instance
        .getHiddenCollectionIds();
    final appBar = GalleryAppBarWidget.sliverConfig(
      widget.appBarType,
      AppLocalizations.of(context).archive,
      _selectedFiles,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
        return FilesDB.instance.getAllPendingOrUploadedFiles(
          creationStartTime,
          creationEndTime,
          Configuration.instance.getUserID()!,
          visibility: archiveVisibility,
          limit: limit,
          asc: asc,
          filterOptions: DBFilterOptions(
            hideIgnoredForUpload: true,
            dedupeUploadID: true,
            ignoredCollectionIDs: hiddenCollectionIDs,
          ),
          applyOwnerCheck: true,
        );
      },
      reloadEvent: Bus.instance.on<FilesUpdatedEvent>().where(
        (event) =>
            event.updatedFiles.firstWhereOrNull(
              (element) => element.uploadedFileID != null,
            ) !=
            null,
      ),
      removalEventTypes: const {EventType.unarchived},
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
      emptyState: _archivedCollections.isEmpty
          ? EmptyStateComponent(
              assetPath: "assets/empty_state_archive.png",
              title: AppLocalizations.of(context).archivedItemsWillShowUpHere,
            )
          : const SizedBox.shrink(),
      header: AlbumHorizontalList(
        () async => _archivedCollections,
        onViewAllTapped: () async {
          if (context.mounted) {
            await routeToPage(
              context,
              CollectionListPage(
                _archivedCollections,
                sectionType: UISectionType.archivedCollections,
                appTitle: Text(
                  AppLocalizations.of(context).archiveCollectionName,
                ),
                tag: "archived",
              ),
            );
          }
          unawaited(_refreshArchivedCollections());
        },
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
