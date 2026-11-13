import "dart:ui" as ui;

import "package:flutter/widgets.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/viewer/file/hero_image.dart";

class GalleryThumbnailSnapshots {
  final _tiles = Map<EnteFile, BuildContext>.identity();

  void register(EnteFile file, BuildContext context) => _tiles[file] = context;

  void unregister(EnteFile file, BuildContext context) {
    if (_tiles[file] == context) _tiles.remove(file);
  }

  Map<EnteFile, ui.Image> capture() {
    final images = Map<EnteFile, ui.Image>.identity();
    for (final entry in _tiles.entries) {
      if (entry.value.mounted) {
        final image = imageFromHero(entry.value);
        if (image != null) images[entry.key] = image.clone();
      }
    }
    return images;
  }
}

class GalleryThumbnailSnapshotScope extends InheritedWidget {
  const GalleryThumbnailSnapshotScope({
    required this.snapshots,
    required super.child,
    super.key,
  });

  final GalleryThumbnailSnapshots snapshots;

  static GalleryThumbnailSnapshots? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GalleryThumbnailSnapshotScope>()
      ?.snapshots;

  @override
  bool updateShouldNotify(GalleryThumbnailSnapshotScope oldWidget) =>
      snapshots != oldWidget.snapshots;
}
