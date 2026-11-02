import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/hide_shared_items_from_home_gallery_event.dart";
import "package:photos/service_locator.dart";

class HideSharedItemsSetting extends StatelessWidget {
  const HideSharedItemsSetting({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsItem(
      title: context.strings.hideSharedItemsFromHomeGallery,
      showChevron: false,
      trailing: ToggleSwitchComponent.async(
        value: () => localSettings.hideSharedItemsFromHomeGallery,
        onChanged: () async {
          final nextValue = !localSettings.hideSharedItemsFromHomeGallery;
          await localSettings.setHideSharedItemsFromHomeGallery(nextValue);
          Bus.instance.fire(HideSharedItemsFromHomeGalleryEvent(nextValue));
        },
      ),
    );
  }
}
