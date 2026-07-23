import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/captioned_text_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget.dart";
import "package:photos/ui/components/menu_section_description_widget.dart";
import "package:photos/ui/viewer/gallery/cleanup_hidden_from_device_page.dart";

class CleanupHiddenFromDeviceWidget extends StatelessWidget {
  final VoidCallback onCleanupComplete;

  const CleanupHiddenFromDeviceWidget({
    required this.onCleanupComplete,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
      child: Column(
        children: [
          MenuItemWidget(
            captionedTextWidget: CaptionedTextWidget(
              title: AppLocalizations.of(context).deleteHiddenFilesFromDevice,
            ),
            singleBorderRadius: 8.0,
            menuItemColor: colorScheme.fillFaint,
            leadingIcon: Icons.phone_android_outlined,
            trailingIcon: Icons.chevron_right,
            onTap: () async {
              await routeToPage(
                context,
                CleanupHiddenFromDevicePage(
                  onCleanupComplete: onCleanupComplete,
                ),
              );
            },
          ),
          MenuSectionDescriptionWidget(
            content: AppLocalizations.of(
              context,
            ).deleteHiddenFilesFromDeviceDescription,
          ),
        ],
      ),
    );
  }
}
