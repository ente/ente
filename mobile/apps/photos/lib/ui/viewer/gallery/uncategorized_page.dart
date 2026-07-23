import 'package:flutter/material.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/collection_meta_event.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/files_updated_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/search/hierarchical/album_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/services/ignored_files_service.dart';
import "package:photos/ui/components/empty_state_component.dart";
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart';
import "package:photos/ui/viewer/gallery/hierarchical_search_gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class UnCategorizedPage extends StatelessWidget {
  final String tagPrefix;
  final Collection collection;
  final GalleryType appBarType;
  final GalleryType overlayType;
  final _selectedFiles = SelectedFiles();

  UnCategorizedPage(
    this.collection, {
    this.tagPrefix = "Uncategorized_page",
    this.appBarType = GalleryType.uncategorized,
    this.overlayType = GalleryType.uncategorized,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      appBarType,
      AppLocalizations.of(context).uncategorized,
      _selectedFiles,
      collection: collection,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final FileLoadResult result = await FilesDB.instance
            .getFilesInCollection(
              collection.id,
              creationStartTime,
              creationEndTime,
              limit: limit,
              asc: asc,
            );
        // hide ignored files from home page UI
        final ignoredIDs =
            await IgnoredFilesService.instance.idToIgnoreReasonMap;
        result.files.removeWhere(
          (f) =>
              f.uploadedFileID == null &&
              IgnoredFilesService.instance.shouldSkipUpload(ignoredIDs, f),
        );
        return result;
      },
      reloadEvent: Bus.instance.on<CollectionUpdatedEvent>().where(
        (event) => event.collectionID == collection.id,
      ),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      forceReloadEvents: [
        Bus.instance.on<CollectionMetaEvent>().where(
          (event) =>
              event.id == collection.id &&
              event.type == CollectionMetaEventType.sortChanged,
        ),
      ],
      tagPrefix: tagPrefix,
      selectedFiles: _selectedFiles,
      sortAsyncFn: () => collection.pubMagicMetadata.asc ?? false,
      initialFiles: null,
      albumName: AppLocalizations.of(context).uncategorized,
      emptyState: EmptyStateComponent(
        assetPath: "assets/empty-uncategorized.png",
        title: AppLocalizations.of(context).uncategorizedItemsWillShowUpHere,
      ),
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: InheritedSearchFilterDataWrapper(
          searchFilterDataProvider: SearchFilterDataProvider(
            initialGalleryFilter: AlbumFilter(
              collectionID: collection.id,
              albumName: collection.displayName,
              occurrence: kMostRelevantFilter,
            ),
          ),
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
                        builder: (context, isSearching, _) {
                          return isSearching
                              ? HierarchicalSearchGallery(
                                  tagPrefix: tagPrefix,
                                  selectedFiles: _selectedFiles,
                                  appBar: appBar,
                                )
                              : gallery;
                        },
                      );
                    },
                  ),
                  FileSelectionOverlayBar(
                    overlayType,
                    _selectedFiles,
                    collection: collection,
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
