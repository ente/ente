import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/hide_shared_items_setting.dart";
import "package:photos/ui/viewer/gallery/gallery_layout_controls.dart";

class GallerySettingsScreen extends StatelessWidget {
  final bool fromGalleryLayoutSettingsCTA;
  const GallerySettingsScreen({
    super.key,
    required this.fromGalleryLayoutSettingsCTA,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: context.strings.gallery,
      children: [
        const GalleryLayoutControls(showHeading: true),
        if (!fromGalleryLayoutSettingsCTA && !isLocalGalleryMode) ...[
          const SizedBox(height: 8),
          const HideSharedItemsSetting(),
        ],
      ],
    );
  }
}
