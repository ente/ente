import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/tabs/albums/empty_states/empty_state_layout.dart";

class FeedEmptyState extends StatelessWidget {
  const FeedEmptyState({this.reservesBottomNavigationSpace = true, super.key});

  final bool reservesBottomNavigationSpace;

  static const _illustrationHeight = 122.0;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;

    return EmptyStateLayout(
      assetPath: "assets/feed.png",
      assetHeight: _illustrationHeight,
      title: strings.albumsSharedEmptyTitle,
      description: strings.albumsSharedEmptyDescription,
      reservesBottomNavigationSpace: reservesBottomNavigationSpace,
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
