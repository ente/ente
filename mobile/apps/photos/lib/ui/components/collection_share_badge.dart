import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";

const double kCollectionBadgeSize = 20.0;
const double kCollectionBadgeIconSize = 12.0;
const double kCollectionBadgeStrokeWidth = 2.0;
const double kCollectionBadgeBorderWidth = 1.0;

class CollectionStatusBadge extends StatelessWidget {
  final Widget child;

  const CollectionStatusBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kCollectionBadgeSize,
      height: kCollectionBadgeSize,
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: Center(child: child),
    );
  }
}

class CollectionSelectedBadge extends StatelessWidget {
  const CollectionSelectedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return SelectAllStatusIcon(
      isSelected: true,
      size: 18,
      tickIconSize: kCollectionBadgeIconSize,
      tickStrokeWidth: kCollectionBadgeStrokeWidth,
      selectedFillColor: colorScheme.primary700,
      selectedTickColor: Colors.white,
    );
  }
}

class CollectionFavoriteBadge extends StatelessWidget {
  const CollectionFavoriteBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const CollectionStatusBadge(
      child: Icon(
        EnteIcons.favoriteFilled,
        size: kCollectionBadgeIconSize,
        color: Colors.white,
      ),
    );
  }
}

class CollectionPinnedBadge extends StatelessWidget {
  const CollectionPinnedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const CollectionStatusBadge(
      child: ImageIcon(
        AssetImage("assets/collection_pin.png"),
        size: kCollectionBadgeIconSize,
        color: Colors.white,
      ),
    );
  }
}

class CollectionArchivedBadge extends StatelessWidget {
  const CollectionArchivedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const CollectionStatusBadge(
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedArchive03,
        size: kCollectionBadgeIconSize,
        color: Colors.white,
        strokeWidth: kCollectionBadgeStrokeWidth,
      ),
    );
  }
}

enum CollectionShareBadgeVariant { filled, outlined }

class CollectionShareBadge extends StatelessWidget {
  final bool isOutgoing;
  final CollectionShareBadgeVariant variant;

  const CollectionShareBadge({
    super.key,
    required this.isOutgoing,
    this.variant = CollectionShareBadgeVariant.filled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isOutlined = variant == CollectionShareBadgeVariant.outlined;
    final outlinedColor = colorScheme.textBase;
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: isOutlined ? Colors.transparent : colorScheme.greenBase,
        shape: BoxShape.circle,
        border: Border.all(
          color: isOutlined ? outlinedColor : colorScheme.fill,
          width: isOutlined ? 1.0 : kCollectionBadgeBorderWidth,
        ),
      ),
      child: Center(
        child: HugeIcon(
          icon: isOutgoing
              ? HugeIcons.strokeRoundedArrowUpRight01
              : HugeIcons.strokeRoundedArrowDownLeft01,
          strokeWidth: kCollectionBadgeStrokeWidth,
          color: isOutlined ? outlinedColor : Colors.white,
          size: 8,
        ),
      ),
    );
  }
}

class CollectionLinkBadge extends StatelessWidget {
  final CollectionShareBadgeVariant variant;

  const CollectionLinkBadge({
    super.key,
    this.variant = CollectionShareBadgeVariant.filled,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isOutlined = variant == CollectionShareBadgeVariant.outlined;
    if (isOutlined) {
      return HugeIcon(
        icon: HugeIcons.strokeRoundedLink02,
        strokeWidth: kCollectionBadgeStrokeWidth,
        color: colorScheme.textBase,
        size: kCollectionBadgeIconSize,
      );
    }

    return Container(
      width: kCollectionBadgeSize,
      height: kCollectionBadgeSize,
      decoration: BoxDecoration(
        color: colorScheme.greenBase,
        shape: BoxShape.circle,
        border: Border.all(
          color: colorScheme.fill,
          width: kCollectionBadgeBorderWidth,
        ),
      ),
      child: const Center(
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedLink02,
          strokeWidth: kCollectionBadgeStrokeWidth,
          color: Colors.white,
          size: kCollectionBadgeIconSize,
        ),
      ),
    );
  }
}

class CollectionUnSyncedBadge extends StatelessWidget {
  static const Color _backgroundColor = Color.fromRGBO(242, 72, 34, 1);

  final bool showBorder;

  const CollectionUnSyncedBadge({super.key, this.showBorder = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Container(
      width: kCollectionBadgeSize,
      height: kCollectionBadgeSize,
      decoration: BoxDecoration(
        color: _backgroundColor,
        shape: BoxShape.circle,
        border: showBorder
            ? Border.all(
                color: colorScheme.fill,
                width: kCollectionBadgeBorderWidth,
              )
            : null,
      ),
      child: const Center(
        child: Icon(
          Icons.cloud_off_outlined,
          size: kCollectionBadgeIconSize,
          color: Colors.white,
        ),
      ),
    );
  }
}
