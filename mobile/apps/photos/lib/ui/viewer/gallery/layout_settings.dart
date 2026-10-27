import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/viewer/gallery/gallery_layout_controls.dart";

class GalleryLayoutSettings extends StatefulWidget {
  const GalleryLayoutSettings({super.key, this.onPreviewVisibilityChanged});

  final void Function(ModalRoute<dynamic> route, bool visible)?
  onPreviewVisibilityChanged;

  @override
  State<GalleryLayoutSettings> createState() => _GalleryLayoutSettingsState();
}

class _GalleryLayoutSettingsState extends State<GalleryLayoutSettings> {
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    if (_route != null) {
      widget.onPreviewVisibilityChanged?.call(_route!, _route!.isCurrent);
    }
  }

  @override
  void dispose() {
    if (_route != null) {
      widget.onPreviewVisibilityChanged?.call(_route!, false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.strings.layout,
      content: const GalleryLayoutControls(keepHeight: true),
    );
  }
}
