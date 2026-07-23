import "dart:async";

import 'package:flutter/material.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/search/search_result.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart';
import "package:photos/ui/viewer/gallery/hierarchical_search_gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class SearchResultPage extends StatefulWidget {
  final SearchResult searchResult;
  final bool enableGrouping;
  final String tagPrefix;

  static const GalleryType appBarType = GalleryType.searchResults;
  static const GalleryType overlayType = GalleryType.searchResults;

  const SearchResultPage(
    this.searchResult, {
    this.enableGrouping = true,
    this.tagPrefix = "",
    super.key,
  });

  @override
  State<SearchResultPage> createState() => _SearchResultPageState();
}

class _SearchResultPageState extends State<SearchResultPage> {
  final _selectedFiles = SelectedFiles();
  late final List<EnteFile> files;
  late final StreamSubscription<LocalPhotosUpdatedEvent> _filesUpdatedEvent;
  late final SearchFilterDataProvider _searchFilterDataProvider;

  @override
  void initState() {
    super.initState();
    files = widget.searchResult.resultFiles();
    _filesUpdatedEvent = Bus.instance.on<LocalPhotosUpdatedEvent>().listen((
      event,
    ) {
      if (event.type == EventType.deletedFromDevice ||
          event.type == EventType.deletedFromEverywhere ||
          event.type == EventType.deletedFromRemote ||
          event.type == EventType.hide) {
        for (var updatedFile in event.updatedFiles) {
          files.remove(updatedFile);
        }
        setState(() {});
      }
    });
    _searchFilterDataProvider = SearchFilterDataProvider(
      initialGalleryFilter: widget.searchResult.getHierarchicalSearchFilter(),
    );
  }

  @override
  void dispose() {
    _filesUpdatedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      SearchResultPage.appBarType,
      widget.searchResult.name(),
      _selectedFiles,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
        final result = files
            .where(
              (file) =>
                  file.creationTime! >= creationStartTime &&
                  file.creationTime! <= creationEndTime,
            )
            .toList();
        return Future.value(
          FileLoadResult(result, result.length < files.length),
        );
      },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
      },
      tagPrefix: widget.tagPrefix + widget.searchResult.heroTag(),
      selectedFiles: _selectedFiles,
      enableFileGrouping: widget.enableGrouping,
      initialFiles: widget.searchResult.resultFiles().isNotEmpty
          ? [widget.searchResult.resultFiles().first]
          : null,
    );

    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: InheritedSearchFilterDataWrapper(
          searchFilterDataProvider: _searchFilterDataProvider,
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
                                  tagPrefix: widget.tagPrefix,
                                  selectedFiles: _selectedFiles,
                                  appBar: appBar,
                                )
                              : gallery;
                        },
                      );
                    },
                  ),
                  FileSelectionOverlayBar(
                    SearchResultPage.overlayType,
                    _selectedFiles,
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
