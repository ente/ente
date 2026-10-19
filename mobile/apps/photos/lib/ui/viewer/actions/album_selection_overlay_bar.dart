import "package:ente_components/ente_components.dart" as components;
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:photos/models/collection/collection.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/bottom_action_bar/album_bottom_action_bar_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";

class AlbumSelectionOverlayBar extends StatefulWidget {
  final VoidCallback? onClose;
  final SelectedAlbums selectedAlbums;
  final List<Collection> collections;
  final Color? backgroundColor;
  final UISectionType sectionType;
  final bool showSelectAllButton;
  final ScrollController? backgroundScrollController;

  const AlbumSelectionOverlayBar(
    this.selectedAlbums,
    this.sectionType,
    this.collections, {
    super.key,
    this.onClose,
    this.backgroundColor,
    this.showSelectAllButton = false,
    this.backgroundScrollController,
  });

  @override
  State<AlbumSelectionOverlayBar> createState() =>
      _AlbumSelectionOverlayBarState();
}

class _AlbumSelectionOverlayBarState extends State<AlbumSelectionOverlayBar> {
  final ValueNotifier<bool> _hasSelectedAlbumsNotifier = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    widget.selectedAlbums.addListener(_selectedAlbumsListener);
    _selectedAlbumsListener();
  }

  @override
  void dispose() {
    widget.selectedAlbums.removeListener(_selectedAlbumsListener);
    _hasSelectedAlbumsNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _hasSelectedAlbumsNotifier,
      builder: (context, value, child) {
        return AnimatedCrossFade(
          alignment: Alignment.bottomCenter,
          firstCurve: Curves.easeOutCubic,
          secondCurve: Curves.easeOutCubic,
          sizeCurve: Curves.easeOutCubic,
          crossFadeState: _hasSelectedAlbumsNotifier.value
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : components.Motion.slow,
          firstChild: AlbumBottomActionBarWidget(
            widget.selectedAlbums,
            widget.sectionType,
            onCancel: widget.selectedAlbums.clearAll,
            backgroundColor: widget.backgroundColor,
            backgroundScrollController: widget.backgroundScrollController,
            selectAllButton: widget.showSelectAllButton
                ? SelectAllAlbumsButton(
                    widget.selectedAlbums,
                    widget.collections,
                  )
                : null,
          ),
          secondChild: const SizedBox(width: double.infinity),
        );
      },
    );
  }

  void _selectedAlbumsListener() {
    _hasSelectedAlbumsNotifier.value = widget.selectedAlbums.albums.isNotEmpty;
  }
}

class SelectAllAlbumsButton extends StatelessWidget {
  final SelectedAlbums selectedAlbums;
  final List<Collection> collections;
  const SelectAllAlbumsButton(
    this.selectedAlbums,
    this.collections, {
    super.key,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selectedAlbums,
    builder: (context, _) {
      final allSelected = selectedAlbums.albums.length == collections.length;
      return SelectionControlChip(
        label: context.strings.selectAllShort,
        semanticLabel: context.strings.selectAll,
        isSelected: allSelected,
        icon: SelectAllStatusIcon(
          isSelected: allSelected,
          size: components.IconSizes.small,
          unselectedColor: components.ComponentTheme.colorsOf(
            context,
          ).textLighter,
        ),
        onTap: collections.isEmpty
            ? null
            : () {
                if (allSelected) {
                  selectedAlbums.clearAll();
                } else {
                  selectedAlbums.select(collections.toSet());
                }
              },
      );
    },
  );
}
