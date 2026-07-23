import "package:flutter/material.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

/// Holds collection info with comment count for the collection selector
class CollectionCommentInfo {
  final Collection collection;
  final int commentCount;
  final EnteFile? thumbnail;

  const CollectionCommentInfo({
    required this.collection,
    required this.commentCount,
    this.thumbnail,
  });
}

/// Holds collection info with like count for the likes bottom sheet
class CollectionLikeInfo {
  final Collection collection;
  final int likeCount;
  final EnteFile? thumbnail;

  const CollectionLikeInfo({
    required this.collection,
    required this.likeCount,
    this.thumbnail,
  });
}

class CollectionSelectorWidget extends StatefulWidget {
  final List<CollectionCommentInfo> sharedCollections;
  final int selectedCollectionID;
  final ValueChanged<int> onCollectionSelected;

  const CollectionSelectorWidget({
    required this.sharedCollections,
    required this.selectedCollectionID,
    required this.onCollectionSelected,
    super.key,
  });

  @override
  State<CollectionSelectorWidget> createState() =>
      _CollectionSelectorWidgetState();
}

class _CollectionSelectorWidgetState extends State<CollectionSelectorWidget> {
  final GlobalKey _widgetKey = GlobalKey();
  bool _isMenuOpen = false;

  CollectionCommentInfo get _selectedCollection =>
      widget.sharedCollections.firstWhere(
        (c) => c.collection.id == widget.selectedCollectionID,
        orElse: () => widget.sharedCollections.first,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final containerColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFF0F0F0);
    final borderColor = isDarkMode
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);

    return GestureDetector(
      onTap: () => _showCollectionMenu(context, containerColor, borderColor),
      child: Container(
        key: _widgetKey,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isMenuOpen ? borderColor : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThumbnailWithBadge(
              thumbnail: _selectedCollection.thumbnail,
              badgeCount: _selectedCollection.commentCount,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _selectedCollection.collection.displayName,
                style: textTheme.smallBold.copyWith(height: 20 / 14.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colorScheme.textBase,
              size: 16,
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  void _showCollectionMenu(
    BuildContext context,
    Color bgColor,
    Color borderColor,
  ) {
    setState(() => _isMenuOpen = true);

    final textTheme = getEnteTextTheme(context);
    final renderBox =
        _widgetKey.currentContext!.findRenderObject()! as RenderBox;
    final widgetPosition = renderBox.localToGlobal(Offset.zero);
    final widgetSize = renderBox.size;
    final screenSize = MediaQuery.sizeOf(context);

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        widgetPosition.dx,
        widgetPosition.dy + widgetSize.height + 10,
        screenSize.width - widgetPosition.dx - widgetSize.width,
        0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 184),
      menuPadding: const EdgeInsets.symmetric(horizontal: 6),
      items: widget.sharedCollections.map((info) {
        return PopupMenuItem<int>(
          height: 40,
          padding: EdgeInsets.zero,
          value: info.collection.id,
          child: Row(
            children: [
              _ThumbnailWithBadge(
                thumbnail: info.thumbnail,
                badgeCount: info.commentCount,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  info.collection.displayName,
                  style: textTheme.miniBold.copyWith(height: 20 / 12.0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedID) {
      setState(() => _isMenuOpen = false);
      if (selectedID != null && selectedID != widget.selectedCollectionID) {
        widget.onCollectionSelected(selectedID);
      }
    });
  }
}

class _ThumbnailWithBadge extends StatelessWidget {
  final EnteFile? thumbnail;
  final int badgeCount;

  const _ThumbnailWithBadge({
    required this.thumbnail,
    required this.badgeCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: thumbnail != null
                ? ThumbnailWidget(thumbnail!)
                : Container(color: colorScheme.fillMuted),
          ),
          Positioned(
            bottom: -4,
            right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: colorScheme.backgroundColour,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                style: TextStyle(
                  color: colorScheme.textBase,
                  fontSize: 8,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LikesCollectionSelectorWidget extends StatefulWidget {
  final List<CollectionLikeInfo> sharedCollections;
  final int selectedCollectionID;
  final ValueChanged<int> onCollectionSelected;

  const LikesCollectionSelectorWidget({
    required this.sharedCollections,
    required this.selectedCollectionID,
    required this.onCollectionSelected,
    super.key,
  });

  @override
  State<LikesCollectionSelectorWidget> createState() =>
      _LikesCollectionSelectorWidgetState();
}

class _LikesCollectionSelectorWidgetState
    extends State<LikesCollectionSelectorWidget> {
  final GlobalKey _widgetKey = GlobalKey();
  bool _isMenuOpen = false;

  CollectionLikeInfo get _selectedCollection =>
      widget.sharedCollections.firstWhere(
        (c) => c.collection.id == widget.selectedCollectionID,
        orElse: () => widget.sharedCollections.first,
      );

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final containerColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFF0F0F0);
    final borderColor = isDarkMode
        ? const Color(0x14FFFFFF)
        : const Color(0x14000000);

    return GestureDetector(
      onTap: () => _showCollectionMenu(context, containerColor, borderColor),
      child: Container(
        key: _widgetKey,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isMenuOpen ? borderColor : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ThumbnailWithBadge(
              thumbnail: _selectedCollection.thumbnail,
              badgeCount: _selectedCollection.likeCount,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _selectedCollection.collection.displayName,
                style: textTheme.smallBold.copyWith(height: 20 / 14.0),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: colorScheme.textBase,
              size: 16,
            ),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }

  void _showCollectionMenu(
    BuildContext context,
    Color bgColor,
    Color borderColor,
  ) {
    setState(() => _isMenuOpen = true);

    final textTheme = getEnteTextTheme(context);
    final renderBox =
        _widgetKey.currentContext!.findRenderObject()! as RenderBox;
    final widgetPosition = renderBox.localToGlobal(Offset.zero);
    final widgetSize = renderBox.size;
    final screenSize = MediaQuery.sizeOf(context);

    showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        widgetPosition.dx,
        widgetPosition.dy + widgetSize.height + 10,
        screenSize.width - widgetPosition.dx - widgetSize.width,
        0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      color: bgColor,
      elevation: 0,
      constraints: const BoxConstraints(minWidth: 184),
      menuPadding: const EdgeInsets.symmetric(horizontal: 6),
      items: widget.sharedCollections.map((info) {
        return PopupMenuItem<int>(
          height: 40,
          padding: EdgeInsets.zero,
          value: info.collection.id,
          child: Row(
            children: [
              _ThumbnailWithBadge(
                thumbnail: info.thumbnail,
                badgeCount: info.likeCount,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  info.collection.displayName,
                  style: textTheme.miniBold.copyWith(height: 20 / 12.0),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    ).then((selectedID) {
      setState(() => _isMenuOpen = false);
      if (selectedID != null && selectedID != widget.selectedCollectionID) {
        widget.onCollectionSelected(selectedID);
      }
    });
  }
}
