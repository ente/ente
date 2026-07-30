import "dart:async";
import 'dart:math';

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/clear_album_selections_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/collections/album/list_item.dart";
import "package:photos/ui/collections/album/new_list_item.dart";
import "package:photos/ui/collections/album/new_row_item.dart";
import "package:photos/ui/collections/album/row_item.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/utils/dialog_util.dart";

class AlbumGridLayout {
  const AlbumGridLayout({
    this.horizontalPadding = 8,
    this.crossAxisSpacing = 8,
    this.mainAxisSpacing = 24,
    this.titleToSubtitleSpacing = 2,
  });

  static const standard = AlbumGridLayout();
  static const dense = AlbumGridLayout(
    horizontalPadding: 16,
    crossAxisSpacing: 10,
    mainAxisSpacing: 8,
    titleToSubtitleSpacing: 4,
  );

  final double horizontalPadding;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double titleToSubtitleSpacing;

  double thumbnailSideFor({required double width, required int columnCount}) {
    final totalSpacing = (columnCount - 1) * crossAxisSpacing;
    return (width - horizontalPadding * 2 - totalSpacing) / columnCount;
  }
}

typedef AlbumSelectionCallbacks = ({
  bool Function(Collection) isSelected,
  ValueChanged<Collection> toggle,
});

class CollectionsFlexiGridViewWidget extends StatefulWidget {
  /*
  Aspect ratio 1:1
  Width changes dynamically with screen width
  */

  static const maxThumbnailWidth = 224.0;
  static const _thumbnailToTextSpacing = 8.0;
  final List<Collection>? collections;

  // If true, the GridView will shrink-wrap its contents.
  final bool shrinkWrap;
  final String tag;

  final AlbumViewType albumViewType;
  final bool enableSelectionMode;
  final bool shouldShowCreateAlbum;
  final SelectedAlbums? selectedAlbums;
  final bool onlyAllowSelection;
  final AlbumSelectionCallbacks? selectionCallbacks;
  final Widget? Function(BuildContext, Collection)? gridTopLeftOverlayBuilder;
  final UISectionType? sectionType;
  final double topPadding;
  final double bottomPadding;
  final AlbumGridLayout gridLayout;

  const CollectionsFlexiGridViewWidget(
    this.collections, {
    this.shrinkWrap = false,
    this.tag = "",
    this.enableSelectionMode = false,
    super.key,
    this.albumViewType = AlbumViewType.grid,
    this.shouldShowCreateAlbum = false,
    this.selectedAlbums,
    this.onlyAllowSelection = false,
    this.selectionCallbacks,
    this.gridTopLeftOverlayBuilder,
    this.sectionType,
    this.topPadding = 16,
    this.bottomPadding = 200,
    this.gridLayout = AlbumGridLayout.standard,
  }) : assert(selectedAlbums == null || selectionCallbacks == null);

  @override
  State<CollectionsFlexiGridViewWidget> createState() =>
      _CollectionsFlexiGridViewWidgetState();
}

class _CollectionsFlexiGridViewWidgetState
    extends State<CollectionsFlexiGridViewWidget> {
  bool isAnyAlbumSelected = false;
  late StreamSubscription<ClearAlbumSelectionsEvent>
  _clearAlbumSelectionSubscription;

  @override
  void initState() {
    _clearAlbumSelectionSubscription = Bus.instance
        .on<ClearAlbumSelectionsEvent>()
        .listen((event) {
          if (mounted) {
            setState(() {
              isAnyAlbumSelected = false;
            });
          }
        });
    super.initState();
  }

  @override
  void dispose() {
    _clearAlbumSelectionSubscription.cancel();
    super.dispose();
  }

  Future<void> _toggleAlbumSelection(Collection c) async {
    await HapticFeedback.lightImpact();
    final callbacks = widget.selectionCallbacks;
    if (callbacks != null) {
      callbacks.toggle(c);
      return;
    }
    widget.selectedAlbums!.toggleSelection(c);
    setState(() {
      isAnyAlbumSelected = widget.selectedAlbums!.albums.isNotEmpty;
    });
  }

  bool get _togglesSelectionOnTap =>
      widget.selectionCallbacks != null ||
      isAnyAlbumSelected ||
      widget.onlyAllowSelection;

  void _handleCollectionTap(Collection collection) {
    unawaited(
      _togglesSelectionOnTap
          ? _toggleAlbumSelection(collection)
          : _navigateToCollectionPage(collection),
    );
  }

  void _handleCollectionLongPress(Collection collection) {
    if (widget.selectionCallbacks != null) {
      unawaited(_toggleAlbumSelection(collection));
      return;
    }
    unawaited(
      _togglesSelectionOnTap
          ? _navigateToCollectionPage(collection)
          : _toggleAlbumSelection(collection),
    );
  }

  Future<void> _navigateToCollectionPage(Collection c) async {
    final thumbnail = await CollectionsService.instance.getCover(c);
    final bool isOwner = c.isOwner(Configuration.instance.getUserID()!);
    final String tagPrefix =
        (isOwner ? "collection" : "shared_collection") +
        widget.tag +
        "_" +
        c.id.toString();
    final bool hasVerifiedLock =
        widget.sectionType == UISectionType.hiddenCollections;
    if (!mounted) return;
    // ignore: unawaited_futures
    routeToPage(
      context,
      CollectionPage(
        tagPrefix: tagPrefix,
        CollectionWithThumbnail(c, thumbnail),
        hasVerifiedLock: hasVerifiedLock,
      ),
    );
  }

  Future<void> _createAlbum() async {
    final result = await showBottomSheetComponent<Object?>(
      context: context,
      builder: (_) => const _CreateAlbumBottomSheet(),
    );

    if (!mounted || result == null) {
      return;
    }
    if (result is Collection) {
      await routeToPage(
        context,
        CollectionPage(CollectionWithThumbnail(result, null)),
      );
    } else {
      await showGenericErrorDialog(context: context, error: result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final usesExternalSelection = widget.selectionCallbacks != null;
    return PopScope(
      canPop: usesExternalSelection || !isAnyAlbumSelected,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || usesExternalSelection) {
          return;
        }
        if (isAnyAlbumSelected) {
          widget.selectedAlbums?.clearAll();
          setState(() {
            isAnyAlbumSelected = false;
          });
        }
      },
      child: widget.albumViewType == AlbumViewType.grid
          ? _buildGridView(context, const ValueKey("grid_view"))
          : _buildListView(context, const ValueKey("list_view")),
    );
  }

  Widget _buildGridView(BuildContext context, Key key) {
    final selectionCallbacks = widget.selectionCallbacks;
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final int albumsCountInCrossAxis = max(
      screenWidth ~/ CollectionsFlexiGridViewWidget.maxThumbnailWidth,
      3,
    );
    final double sideOfThumbnail = widget.gridLayout.thumbnailSideFor(
      width: screenWidth,
      columnCount: albumsCountInCrossAxis,
    );
    final double gridItemTextHeight = _gridItemTextHeight(context);
    final int totalCollections = widget.collections!.length;
    final bool showCreateAlbum = widget.shouldShowCreateAlbum;
    final int displayItemCount = totalCollections + (showCreateAlbum ? 1 : 0);

    return SliverPadding(
      key: key,
      padding: EdgeInsets.only(
        top: widget.topPadding,
        left: widget.gridLayout.horizontalPadding,
        right: widget.gridLayout.horizontalPadding,
        bottom: widget.bottomPadding,
      ),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (showCreateAlbum && index == 0) {
            return NewAlbumRowItemWidget(
              height: sideOfThumbnail,
              width: sideOfThumbnail,
              onTap: (_) => _createAlbum(),
            );
          }
          final collectionIndex = showCreateAlbum ? index - 1 : index;
          return AlbumRowItemWidget(
            widget.collections![collectionIndex],
            sideOfThumbnail,
            key: ValueKey(
              '${widget.tag}_${widget.collections![collectionIndex].id}',
            ),
            tag: widget.tag,
            selectedAlbums: widget.selectedAlbums,
            isSelected: selectionCallbacks?.isSelected(
              widget.collections![collectionIndex],
            ),
            topLeftOverlayBuilder: widget.gridTopLeftOverlayBuilder,
            titleToSubtitleSpacing: widget.gridLayout.titleToSubtitleSpacing,
            onTapCallback: _handleCollectionTap,
            onLongPressCallback: widget.enableSelectionMode
                ? _handleCollectionLongPress
                : null,
          );
        }, childCount: displayItemCount),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: albumsCountInCrossAxis,
          mainAxisSpacing: widget.gridLayout.mainAxisSpacing,
          crossAxisSpacing: widget.gridLayout.crossAxisSpacing,
          childAspectRatio:
              sideOfThumbnail / (sideOfThumbnail + gridItemTextHeight),
        ),
      ),
    );
  }

  double _gridItemTextHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return (CollectionsFlexiGridViewWidget._thumbnailToTextSpacing +
            _scaledLineHeight(textScaler, TextStyles.body) +
            widget.gridLayout.titleToSubtitleSpacing +
            _scaledLineHeight(textScaler, TextStyles.mini))
        .ceilToDouble();
  }

  double _scaledLineHeight(TextScaler textScaler, TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    return textScaler.scale(fontSize) * (style.height ?? 1);
  }

  Widget _buildListView(BuildContext context, Key key) {
    final selectionCallbacks = widget.selectionCallbacks;
    final int totalCollections = widget.collections?.length ?? 0;
    final bool showCreateAlbum =
        widget.shouldShowCreateAlbum && !isAnyAlbumSelected;
    final int displayItemCount = totalCollections + (showCreateAlbum ? 1 : 0);
    if (displayItemCount == 0) {
      return SliverToBoxAdapter(key: key, child: const SizedBox.shrink());
    }

    return SliverPadding(
      key: key,
      padding: EdgeInsets.only(
        top: widget.topPadding,
        left: 8,
        right: 8,
        bottom: widget.bottomPadding,
      ),
      sliver: SliverList.builder(
        itemBuilder: (context, index) {
          Widget item;
          Key itemKey;

          if (showCreateAlbum && index == 0) {
            itemKey = ValueKey("${widget.tag}_new_album_list_item");
            item = NewAlbumListItemWidget(onTap: (_) => _createAlbum());
          } else {
            final collectionIndex = showCreateAlbum ? index - 1 : index;
            final collection = widget.collections![collectionIndex];
            itemKey = ValueKey("${widget.tag}_list_${collection.id}");

            item = AlbumListItemWidget(
              collection,
              selectedAlbums: widget.selectedAlbums,
              isSelected: selectionCallbacks?.isSelected(collection) ?? false,
              onTapCallback: _handleCollectionTap,
              onLongPressCallback: widget.enableSelectionMode
                  ? _handleCollectionLongPress
                  : null,
            );
          }

          return Padding(
            key: itemKey,
            padding: const EdgeInsets.symmetric(
              vertical: ThumbnailListItem.defaultItemSpacing / 2,
            ),
            child: item,
          );
        },
        itemCount: displayItemCount,
      ),
    );
  }
}

class _CreateAlbumBottomSheet extends StatefulWidget {
  const _CreateAlbumBottomSheet();

  @override
  State<_CreateAlbumBottomSheet> createState() =>
      _CreateAlbumBottomSheetState();
}

class _CreateAlbumBottomSheetState extends State<_CreateAlbumBottomSheet> {
  final _controller = TextEditingController();
  bool _hasAlbumName = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return BottomSheetComponent(
      title: strings.newAlbum,
      isKeyboardAware: true,
      content: TextInputComponent(
        controller: _controller,
        hintText: strings.enterAlbumName,
        autofocus: true,
        isClearable: true,
        textCapitalization: TextCapitalization.words,
        onSubmit: (_) => _createAlbum(),
        onChanged: (_) {
          final hasAlbumName = _controller.text.trim().isNotEmpty;
          if (_hasAlbumName == hasAlbumName) {
            return;
          }
          setState(() {
            _hasAlbumName = hasAlbumName;
          });
        },
      ),
      actions: [
        ButtonComponent(
          label: strings.create,
          isDisabled: !_hasAlbumName,
          onTap: _createAlbum,
        ),
      ],
    );
  }

  Future<void> _createAlbum() async {
    final albumName = _controller.text.trim();
    if (albumName.isEmpty) {
      return;
    }

    try {
      final collection = await CollectionsService.instance.createAlbum(
        albumName,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(collection);
    } catch (e, s) {
      Logger("CreateAlbumBottomSheet").severe("Failed to create album", e, s);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(e);
    }
  }
}
