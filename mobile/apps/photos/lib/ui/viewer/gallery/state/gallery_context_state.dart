import "package:flutter/material.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GalleryContextState extends InheritedWidget {
  final bool sortOrderAsc;
  final bool inSelectionMode;
  final GroupType type;
  final GalleryType? galleryType;

  const GalleryContextState({
    this.inSelectionMode = false,
    this.type = GroupType.day,
    this.galleryType,
    required this.sortOrderAsc,
    required super.child,
    super.key,
  });

  static GalleryContextState? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<GalleryContextState>();
  }

  @override
  bool updateShouldNotify(GalleryContextState oldWidget) {
    return sortOrderAsc != oldWidget.sortOrderAsc ||
        inSelectionMode != oldWidget.inSelectionMode ||
        type != oldWidget.type ||
        galleryType != oldWidget.galleryType;
  }
}
