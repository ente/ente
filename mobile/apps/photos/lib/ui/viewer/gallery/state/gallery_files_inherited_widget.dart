import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";

// ignore: must_be_immutable
class GalleryFilesState extends InheritedWidget {
  GalleryFilesState({super.key, required super.child});

  // Keep the same file objects used by galleryGroups so mutations stay in sync.
  List<EnteFile>? _galleryFiles;
  ({int oldest, int newest})? _captureDateRange;
  bool _hasComputedDateRange = false;

  set setGalleryFiles(List<EnteFile> galleryFiles) {
    _galleryFiles = galleryFiles;
    invalidateCaptureDateRange();
  }

  void removeFile(EnteFile file) {
    _galleryFiles!.remove(file);
    invalidateCaptureDateRange();
  }

  void invalidateCaptureDateRange() => _hasComputedDateRange = false;

  ({int oldest, int newest})? get captureDateRange {
    if (_hasComputedDateRange) return _captureDateRange;
    int? oldest;
    int? newest;
    for (final file in _galleryFiles ?? const <EnteFile>[]) {
      final time = file.creationTime;
      if (time == null || time == 0) continue;
      if (oldest == null || time < oldest) oldest = time;
      if (newest == null || time > newest) newest = time;
    }
    _captureDateRange = oldest == null || newest == null
        ? null
        : (oldest: oldest, newest: newest);
    _hasComputedDateRange = true;
    return _captureDateRange;
  }

  List<EnteFile>? get galleryFilesOrNull => _galleryFiles;

  List<EnteFile> get galleryFiles {
    assert(
      _galleryFiles != null,
      "Gallery files not set yet. Should be set in the gallery widget",
    );
    return _galleryFiles!;
  }

  static GalleryFilesState? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GalleryFilesState>();
  }

  static GalleryFilesState of(BuildContext context) {
    final GalleryFilesState? result = maybeOf(context);
    assert(
      result != null,
      'No GalleryFiles found in context. GalleryFilesState should be an ancestor of the GalleryWidget, preferably over the Scaffold of Gallery.',
    );
    return result!;
  }

  @override
  bool updateShouldNotify(GalleryFilesState oldWidget) => false;
}
