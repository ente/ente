import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_layout.dart";

class ReceivedEmptyState extends StatelessWidget {
  const ReceivedEmptyState({super.key});

  static const _illustrationHeight = 158.0;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return EmptyStateLayout(
      assetPath: "assets/received.png",
      assetHeight: _illustrationHeight,
      title: strings.albumsReceivedEmptyTitle,
      description: strings.albumsReceivedEmptyDescription,
      action: ButtonComponent(
        label: strings.shareAnAlbum,
        shouldSurfaceExecutionStates: false,
        onTap: () => showCollectionActionSheet(
          context,
          actionType: CollectionActionType.shareCollection,
        ),
      ),
    );
  }
}
