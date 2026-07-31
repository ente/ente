import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/services/collections_service.dart';
import "package:photos/services/hidden_service.dart";
import 'package:photos/ui/components/menu_section_description_widget.dart';

class CleanupHiddenFilesWidget extends StatelessWidget {
  final VoidCallback onCleanupComplete;

  const CleanupHiddenFilesWidget({required this.onCleanupComplete, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 24),
      child: Column(
        children: [
          MenuComponent(
            title: AppLocalizations.of(context).cleanupHiddenFiles,
            leading: const Icon(Icons.cleaning_services_outlined),
            shouldSurfaceExecutionStates: true,
            shouldShowSuccessConfirmation: true,
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
