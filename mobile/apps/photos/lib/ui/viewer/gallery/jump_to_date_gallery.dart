import "dart:async";

import 'package:flutter/material.dart';
import "package:photos/core/configuration.dart";
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import 'package:photos/services/search_service.dart';
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/viewer/actions/file_selection_overlay_bar.dart';
import 'package:photos/ui/viewer/gallery/component/group/type.dart';
import 'package:photos/ui/viewer/gallery/gallery.dart';
import 'package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart';
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";

enum GalleryLoadState {
  loadingFiles,
  waitingForGalleryFinalBuildToComplete,
  galleryReady,
}

class JumpToDateGallery extends StatefulWidget {
  final EnteFile fileToJumpTo;
  final String tagPrefix;

  static const GalleryType appBarType = GalleryType.searchResults;
  static const GalleryType overlayType = GalleryType.searchResults;

  const JumpToDateGallery({
    required this.fileToJumpTo,
    this.tagPrefix = "jump_to_date",
    super.key,
  });

  @override
  State<JumpToDateGallery> createState() => _JumpToDateGalleryState();
}

class _JumpToDateGalleryState extends State<JumpToDateGallery> {
  final _selectedFiles = SelectedFiles();
  late final List<EnteFile> files;
  late final StreamSubscription<LocalPhotosUpdatedEvent> _filesUpdatedEvent;
  GalleryLoadState _loadState = GalleryLoadState.loadingFiles;

  @override
  void initState() {
    super.initState();
    files = [];
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

    // Load files asynchronously
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    final startTime = DateTime.now();
    final onlyUploadedFiles =
        !(isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount());
    final allFiles = await SearchService.instance.getAllFilesForGenericGallery(
      onlyUploadedFiles: onlyUploadedFiles,
    );

    // Ensure minimum loading duration to mask Gallery initialization jank
    final elapsed = DateTime.now().difference(startTime).inMilliseconds;
    const minLoadingDuration = 200;

    if (elapsed < minLoadingDuration) {
      await Future.delayed(
        Duration(milliseconds: minLoadingDuration - elapsed),
      );
    }

    if (!mounted) return;

    setState(() {
      files.clear();
      files.addAll(allFiles);
      _loadState = GalleryLoadState.waitingForGalleryFinalBuildToComplete;
    });

    // Wait for gallery to build, then make it visible
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _loadState = GalleryLoadState.galleryReady;
        });
      }
    });
  }

  @override
  void dispose() {
    _filesUpdatedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      JumpToDateGallery.appBarType,
      "",
      _selectedFiles,
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: _loadState == GalleryLoadState.loadingFiles
              ? CustomScrollView(
                  slivers: [
                    appBar.buildSliver(context),
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EnteLoadingWidget(
                        color: getEnteColorScheme(context).strokeMuted,
                      ),
                    ),
                  ],
                )
              : AnimatedOpacity(
                  opacity: _loadState == GalleryLoadState.galleryReady
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutQuad,
                  child: SelectionState(
                    selectedFiles: _selectedFiles,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        Gallery(
                          appBar: appBar,
                          asyncLoader:
                              (
                                creationStartTime,
                                creationEndTime, {
                                limit,
                                asc,
                              }) {
                                final result = files
                                    .where(
                                      (file) =>
                                          file.creationTime! >=
                                              creationStartTime &&
                                          file.creationTime! <= creationEndTime,
                                    )
                                    .toList();
                                return Future.value(
                                  FileLoadResult(
                                    result,
                                    result.length < files.length,
                                  ),
                                );
                              },
                          reloadEvent: Bus.instance
                              .on<LocalPhotosUpdatedEvent>(),
                          removalEventTypes: const {
                            EventType.deletedFromRemote,
                            EventType.deletedFromEverywhere,
                            EventType.hide,
                          },
                          tagPrefix: widget.tagPrefix,
                          selectedFiles: _selectedFiles,
                          enableFileGrouping: true,
                          fileToJumpTo: widget.fileToJumpTo,
                          groupType: GroupType.day,
                        ),
                        FileSelectionOverlayBar(
                          JumpToDateGallery.overlayType,
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
