import "dart:async";

import "package:defer_pointer/defer_pointer.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

class MapPullUpGallery extends StatefulWidget {
  final StreamController<List<EnteFile>> visibleImages;
  final double bottomUnsafeArea;
  final double bottomSheetDraggableAreaHeight;
  final bool hasLocationData;
  static const gridCrossAxisSpacing = 4.0;
  static const gridMainAxisSpacing = 4.0;
  static const gridPadding = 2.0;
  static const gridCrossAxisCount = 4;
  const MapPullUpGallery(
    this.visibleImages,
    this.bottomSheetDraggableAreaHeight,
    this.bottomUnsafeArea, {
    this.hasLocationData = true,
    super.key,
  });

  @override
  State<MapPullUpGallery> createState() => _MapPullUpGalleryState();
}

class _MapPullUpGalleryState extends State<MapPullUpGallery> {
  final _selectedFiles = SelectedFiles();

  @override
  Widget build(BuildContext context) {
    final Logger logger = Logger("_MapPullUpGalleryState");
    final screenHeight = MediaQuery.of(context).size.height;
    final unsafeAreaProportion = widget.bottomUnsafeArea / screenHeight;
    final double initialChildSize = 0.25 + unsafeAreaProportion;

    Widget? cachedScrollableContent;

    return DeferredPointerHandler(
      child: GalleryBoundariesProvider(
        child: GalleryFilesState(
          child: SelectionState(
            selectedFiles: _selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              clipBehavior: Clip.none,
              children: [
                DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: initialChildSize,
                  minChildSize: initialChildSize,
                  maxChildSize: 0.8,
                  snap: true,
                  snapSizes: const [0.5],
                  builder: (context, scrollController) {
                    //Must use cached widget here to avoid rebuilds when DraggableScrollableSheet
                    //is snapped to it's initialChildSize
                    cachedScrollableContent ??= cacheScrollableContent(
                      scrollController,
                      context,
                      logger,
                    );
                    return cachedScrollableContent!;
                  },
                ),
                DeferPointer(
                  //This is to make the FileSelectionOverlayBar respect SafeArea
                  child: MediaQuery(
                    data: MediaQueryData.fromView(View.of(context)),
                    child: FileSelectionOverlayBar(
                      GalleryType.searchResults,
                      _selectedFiles,
                      backgroundColor: getEnteColorScheme(
                        context,
                      ).backgroundElevated2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget cacheScrollableContent(
    ScrollController scrollController,
    BuildContext context,
    logger,
  ) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        color: colorScheme.backgroundElevated,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          DraggableHeader(
            scrollController: scrollController,
            bottomSheetDraggableAreaHeight:
                widget.bottomSheetDraggableAreaHeight,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeInOutExpo,
              switchOutCurve: Curves.easeInOutExpo,
              child: StreamBuilder<List<EnteFile>>(
                stream: widget.visibleImages.stream,
                builder:
                    (
                      BuildContext context,
                      AsyncSnapshot<List<EnteFile>> snapshot,
                    ) {
                      if (!snapshot.hasData) {
                        return SizedBox(
                          height: MediaQuery.of(context).size.height * 0.2,
                          child: const EnteLoadingWidget(),
                        );
                      }

                      final images = snapshot.data!;
                      logger.info("Visible images: ${images.length}");
                      //To retain only selected files that are in view (visible)
                      WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
                        _selectedFiles.retainFiles(images.toSet());
                      });

                      if (images.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.2,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    AppLocalizations.of(
                                      context,
                                    ).noPhotosFoundHere,
                                    style: textTheme.large,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    widget.hasLocationData
                                        ? AppLocalizations.of(
                                            context,
                                          ).zoomOutToSeePhotos
                                        : AppLocalizations.of(
                                            context,
                                          ).noImagesWithLocation,
                                    style: textTheme.smallFaint,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        switchInCurve: Curves.easeInOutExpo,
                        switchOutCurve: Curves.easeInOutExpo,
                        child: Gallery(
                          key: ValueKey(images),
                          asyncLoader:
                              (
                                creationStartTime,
                                creationEndTime, {
                                limit,
                                asc,
                              }) async {
                                FileLoadResult result;
                                result = FileLoadResult(images, false);
                                return result;
                              },
                          reloadEvent: Bus.instance
                              .on<LocalPhotosUpdatedEvent>(),
                          removalEventTypes: const {
                            EventType.deletedFromRemote,
                            EventType.deletedFromEverywhere,
                          },
                          tagPrefix: "map_gallery",
                          showSelectAll: true,
                          selectedFiles: _selectedFiles,
                        ),
                      );
                    },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DraggableHeader extends StatelessWidget {
  const DraggableHeader({
    super.key,
    required this.scrollController,
    required this.bottomSheetDraggableAreaHeight,
  });
  static const indicatorHeight = 4.0;
  final ScrollController scrollController;
  final double bottomSheetDraggableAreaHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      controller: scrollController,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          color: colorScheme.backgroundElevated2,
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical:
                  bottomSheetDraggableAreaHeight / 2 - indicatorHeight / 2,
            ),
            child: Container(
              height: indicatorHeight,
              width: 72,
              decoration: BoxDecoration(
                color: colorScheme.fillBase,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
