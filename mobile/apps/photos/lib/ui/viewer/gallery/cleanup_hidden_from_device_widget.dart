import 'package:ente_components/ente_components.dart';
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
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
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 12),
      child: Column(
        children: [
          MenuComponent(
            title: context.strings.deleteHiddenFilesFromDevice,
            leading: const Icon(Icons.phone_android_outlined),
            trailing: const Icon(Icons.chevron_right),
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
            content: context.strings.deleteHiddenFilesFromDeviceDescription,
          ),
        ],
      ),
    );
  }
}
