import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";

class AlbumActionBarWidget extends StatelessWidget {
  const AlbumActionBarWidget({
    required this.selectedAlbums,
    this.onCancel,
    super.key,
  });
  final SelectedAlbums selectedAlbums;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selectedAlbums,
    builder: (context, _) => SelectionControlChip(
      label: selectedAlbums.albums.length.toString(),
      semanticLabel:
          "${context.strings.cancel}, ${context.strings.selectedAlbums(count: selectedAlbums.albums.length)}",
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: IconSizes.small,
      ),
      onTap: onCancel,
    ),
  );
}
