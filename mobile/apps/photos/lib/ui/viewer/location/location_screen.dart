import "dart:async";
import 'dart:developer' as dev;

import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/location_filter.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";
import "package:photos/services/location_service.dart";
import "package:photos/states/location_screen_state.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/hierarchical_search_gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class LocationScreen extends StatefulWidget {
  final String tagPrefix;
  const LocationScreen({this.tagPrefix = "", super.key});

  @override
  State<LocationScreen> createState() => _LocationScreenState();
}

class _LocationScreenState extends State<LocationScreen> {
  final selectedFiles = SelectedFiles();

  @override
  Widget build(BuildContext context) {
    final locationTag = InheritedLocationScreenState.of(
      context,
    ).locationTagEntity.item;

    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: InheritedSearchFilterDataWrapper(
          searchFilterDataProvider: SearchFilterDataProvider(
            initialGalleryFilter: LocationFilter(
              locationTag: locationTag,
              occurrence: kMostRelevantFilter,
            ),
          ),
          child: Scaffold(
            body: LocationGalleryWidget(
              tagPrefix: widget.tagPrefix,
              selectedFiles: selectedFiles,
            ),
          ),
        ),
      ),
    );
  }
}

class LocationGalleryWidget extends StatefulWidget {
  final String tagPrefix;
  final SelectedFiles selectedFiles;
  const LocationGalleryWidget({
    required this.tagPrefix,
    required this.selectedFiles,
    super.key,
  });

  @override
  State<LocationGalleryWidget> createState() => _LocationGalleryWidgetState();
}

class _LocationGalleryWidgetState extends State<LocationGalleryWidget> {
  late final Future<FileLoadResult> fileLoadResult;
  late final List<EnteFile> allFilesWithLocation;

  final _selectedFiles = SelectedFiles();
  late final StreamSubscription<LocalPhotosUpdatedEvent> _filesUpdateEvent;
  @override
  void initState() {
    super.initState();

    final collectionsToHide = CollectionsService.instance
        .getHiddenCollectionIds();
    fileLoadResult = FilesDB.instance
        .fetchAllUploadedAndSharedFilesWithLocation(
          galleryLoadStartTime,
          galleryLoadEndTime,
          limit: null,
          asc: false,
          filterOptions: DBFilterOptions(
            ignoredCollectionIDs: collectionsToHide,
            hideIgnoredForUpload: true,
          ),
        )
        .then((value) {
          allFilesWithLocation = value.files;
          _filesUpdateEvent = Bus.instance.on<LocalPhotosUpdatedEvent>().listen(
            (event) {
              if (event.type == EventType.deletedFromDevice ||
                  event.type == EventType.deletedFromEverywhere ||
                  event.type == EventType.deletedFromRemote ||
                  event.type == EventType.hide) {
                for (var updatedFile in event.updatedFiles) {
                  allFilesWithLocation.remove(updatedFile);
                }
                if (mounted) {
                  setState(() {});
                }
              }
            },
          );
          return value;
        });
  }

  @override
  void dispose() {
    InheritedLocationScreenState.memoryCountNotifier.value = null;
    _filesUpdateEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedRadius = InheritedLocationScreenState.of(
      context,
    ).locationTagEntity.item.radius;
    final locationTag = InheritedLocationScreenState.of(
      context,
    ).locationTagEntity.item;
    final centerPoint = InheritedLocationScreenState.of(
      context,
    ).locationTagEntity.item.centerPoint;
    final appBar = GalleryAppBarWidget.sliverConfig(
      GalleryType.locationTag,
      locationTag.name,
      _selectedFiles,
    );

    Future<FileLoadResult> filterFiles() async {
      //waiting for allFilesWithLocation to be initialized
      await fileLoadResult;
      final stopWatch = Stopwatch()..start();
      final filesInLocation = allFilesWithLocation;
      filesInLocation.removeWhere((f) {
        return !isFileInsideLocationTag(
          centerPoint,
          f.location!,
          selectedRadius,
        );
      });
      dev.log(
        "Time taken to get all files in a location tag: ${stopWatch.elapsedMilliseconds} ms",
      );
      stopWatch.stop();
      InheritedLocationScreenState.memoryCountNotifier.value =
          filesInLocation.length;

      return Future.value(FileLoadResult(filesInLocation, false));
    }

    return FutureBuilder(
      //rebuild gallery only when there is change in radius or center point
      key: ValueKey("$centerPoint$selectedRadius"),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return SelectionState(
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
                                tagPrefix: widget.tagPrefix,
                                selectedFiles: _selectedFiles,
                                appBar: appBar,
                              )
                            : Gallery(
                                appBar: appBar,
                                loadingWidget: Column(
                                  children: [
                                    EnteLoadingWidget(
                                      color: getEnteColorScheme(
                                        context,
                                      ).strokeMuted,
                                    ),
                                  ],
                                ),
                                asyncLoader:
                                    (
                                      creationStartTime,
                                      creationEndTime, {
                                      limit,
                                      asc,
                                    }) async {
                                      return snapshot.data as FileLoadResult;
                                    },
                                reloadEvent: Bus.instance
                                    .on<LocalPhotosUpdatedEvent>(),
                                removalEventTypes: const {
                                  EventType.deletedFromRemote,
                                  EventType.deletedFromEverywhere,
                                },
                                selectedFiles: _selectedFiles,
                                tagPrefix: widget.tagPrefix,
                              );
                      },
                    );
                  },
                ),
                FileSelectionOverlayBar(
                  GalleryType.locationTag,
                  _selectedFiles,
                ),
              ],
            ),
          );
        } else {
          return CustomScrollView(
            slivers: [
              appBar.buildSliver(context),
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EnteLoadingWidget(),
              ),
            ],
          );
        }
      },
      future: filterFiles(),
    );
  }
}
