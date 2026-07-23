import "package:ente_components/ente_components.dart" as components;
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/bottom_action_bar/album_bottom_action_bar_widget.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";

class AlbumSelectionOverlayBar extends StatefulWidget {
  final VoidCallback? onClose;
  final SelectedAlbums selectedAlbums;
  final List<Collection> collections;
  final Color? backgroundColor;
  final UISectionType sectionType;
  final bool showSelectAllButton;

  const AlbumSelectionOverlayBar(
    this.selectedAlbums,
    this.sectionType,
    this.collections, {
    super.key,
    this.onClose,
    this.backgroundColor,
    this.showSelectAllButton = false,
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
  }

  @override
  void dispose() {
    widget.selectedAlbums.removeListener(_selectedAlbumsListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: _hasSelectedAlbumsNotifier,
      builder: (context, value, child) {
        return AnimatedCrossFade(
          firstCurve: Curves.easeInOutExpo,
          secondCurve: Curves.easeInOutExpo,
          sizeCurve: Curves.easeInOutExpo,
          crossFadeState: _hasSelectedAlbumsNotifier.value
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 400),
          firstChild: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.showSelectAllButton)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: SelectAllAlbumsButton(
                    widget.selectedAlbums,
                    widget.collections,
                    backgroundColor: widget.backgroundColor,
                  ),
                ),
              const SizedBox(height: 8),
              AlbumBottomActionBarWidget(
                widget.selectedAlbums,
                widget.sectionType,
                onCancel: () {
                  if (widget.selectedAlbums.albums.isNotEmpty) {
                    widget.selectedAlbums.clearAll();
                  }
                },
                backgroundColor: widget.backgroundColor,
              ),
            ],
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

class SelectAllAlbumsButton extends StatefulWidget {
  final SelectedAlbums selectedAlbums;
  final List<Collection> collections;
  final Color? backgroundColor;

  const SelectAllAlbumsButton(
    this.selectedAlbums,
    this.collections, {
    super.key,
    this.backgroundColor,
  });

  @override
  State<SelectAllAlbumsButton> createState() => _SelectAllAlbumsButtonState();
}

class _SelectAllAlbumsButtonState extends State<SelectAllAlbumsButton> {
  bool _allSelected = false;

  @override
  Widget build(BuildContext context) {
    final colors = components.ComponentTheme.colorsOf(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_allSelected) {
            widget.selectedAlbums.clearAll();
          } else {
            widget.selectedAlbums.select(widget.collections.toSet());
          }
          _allSelected = !_allSelected;
        });
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: widget.backgroundColor ?? colors.backgroundBase,
            border: Border.all(color: colors.strokeDark),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppLocalizations.of(context).selectAllShort,
                style: components.TextStyles.mini.copyWith(
                  color: colors.textBase,
                ),
              ),
              const SizedBox(width: 4),
              ListenableBuilder(
                listenable: widget.selectedAlbums,
                builder: (context, _) {
                  if (widget.selectedAlbums.albums.length ==
                      widget.collections.length) {
                    _allSelected = true;
                  } else {
                    _allSelected = false;
                  }
                  return SelectAllStatusIcon(
                    isSelected: _allSelected,
                    size: 16,
                    unselectedColor: colors.textLighter,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
