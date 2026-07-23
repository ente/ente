import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/services/hidden_service.dart";
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/captioned_text_widget.dart';
import 'package:photos/ui/components/menu_item_widget/menu_item_widget.dart';
import 'package:photos/ui/components/menu_section_description_widget.dart';

class CleanupHiddenFilesWidget extends StatelessWidget {
  final VoidCallback onCleanupComplete;

  const CleanupHiddenFilesWidget({required this.onCleanupComplete, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 24),
      child: Column(
        children: [
          MenuItemWidget(
            captionedTextWidget: CaptionedTextWidget(
              title: AppLocalizations.of(context).cleanupHiddenFiles,
            ),
            singleBorderRadius: 8.0,
            menuItemColor: colorScheme.fillFaint,
            leadingIcon: Icons.cleaning_services_outlined,
            alwaysShowSuccessState: true,
            onTap: () async {
              await CollectionsService.instance.cleanupHiddenFiles(context);
              onCleanupComplete();
            },
          ),
          MenuSectionDescriptionWidget(
            content: AppLocalizations.of(context).cleanupHiddenFilesDescription,
          ),
        ],
      ),
    );
  }
}
