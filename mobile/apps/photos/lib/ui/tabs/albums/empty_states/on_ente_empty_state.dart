import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_layout.dart";

class OnEnteEmptyState extends StatelessWidget {
  const OnEnteEmptyState({super.key});

  static const _illustrationHeight = 112.7;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return EmptyStateLayout(
      assetPath: "assets/on_ente.png",
      assetHeight: _illustrationHeight,
      title: strings.albumsOnEnteEmptyTitle,
      description: strings.albumsOnEnteEmptyDescription,
      action: ButtonComponent(
        label: strings.albumsOnEnteEmptyCta,
        shouldSurfaceExecutionStates: false,
        onTap: () => handleFolderSelectionBackupFlow(context),
      ),
    );
  }
}
