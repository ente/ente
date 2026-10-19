import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/viewer/gallery/gallery_layout_controls.dart";

class GalleryLayoutSettings extends StatelessWidget {
  const GalleryLayoutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.strings.layout,
      content: const GalleryLayoutControls(keepHeight: true),
    );
  }
}
