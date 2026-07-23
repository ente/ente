import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";

// ignore: must_be_immutable
class GalleryFilesState extends InheritedWidget {
  GalleryFilesState({super.key, required super.child});

  ///Should be assigned later in gallery when files are loaded.
  ///Note: EnteFiles in this list should be references of the same EnteFiles
  ///that are grouped in gallery, so that when files are added/deleted,
  ///both lists are in sync.
  List<EnteFile>? _galleryFiles;

  set setGalleryFiles(List<EnteFile> galleryFiles) {
    _galleryFiles = galleryFiles;
  }

  void removeFile(EnteFile file) {
    _galleryFiles!.remove(file);
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
