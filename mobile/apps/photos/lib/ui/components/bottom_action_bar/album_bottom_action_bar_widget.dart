import "package:ente_components/ente_components.dart" as components;
import "package:flutter/material.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/bottom_action_bar/album_action_bar_widget.dart";
import "package:photos/ui/viewer/actions/album_selection_action_widget.dart";

class AlbumBottomActionBarWidget extends StatelessWidget {
  final SelectedAlbums selectedAlbums;
  final VoidCallback? onCancel;
  final Color? backgroundColor;
  final ScrollController? backgroundScrollController;
  final Widget? selectAllButton;
  final UISectionType sectionType;

  const AlbumBottomActionBarWidget(
    this.selectedAlbums,
    this.sectionType, {
    super.key,
    this.backgroundColor,
    this.onCancel,
    this.backgroundScrollController,
    this.selectAllButton,
  });

  @override
  Widget build(BuildContext context) {
    return AlbumSelectionActionWidget(
      selectedAlbums,
      sectionType,
      backgroundColor: backgroundColor,
      backgroundScrollController: backgroundScrollController,
      selectionControls: Padding(
        padding: const EdgeInsets.symmetric(horizontal: components.Spacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (selectAllButton != null) Flexible(child: selectAllButton!),
            const SizedBox(width: components.Spacing.sm),
            Flexible(
              child: AlbumActionBarWidget(
                selectedAlbums: selectedAlbums,
                onCancel: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
