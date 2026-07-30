import "package:ente_components/ente_components.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/extensions/collection_extension.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/models/selected_collections.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/collections/models/collection.dart";
import "package:locker/services/configuration.dart";
import "package:locker/ui/pages/collection_page.dart";
import "package:locker/ui/sharing/album_share_info_widget.dart";
import "package:locker/utils/file_icon_utils.dart";

class CollectionListWidget extends StatelessWidget {
  final Collection collection;
  final SelectedCollections? selectedCollections;
  final void Function(Collection)? onTapCallback;
  final void Function(Collection)? onLongPressCallback;

  const CollectionListWidget({
    super.key,
    required this.collection,
    this.selectedCollections,
    this.onTapCallback,
    this.onLongPressCallback,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final bool isFavourite = collection.type == CollectionType.favorites;
    final bool hasSharees = collection.sharees.isNotEmpty;

    final int? currentUserID = Configuration.instance.getUserID();
    final bool isOwner =
        currentUserID != null && collection.isOwner(currentUserID);
    final bool isOutgoing = isOwner && hasSharees;
    final bool isIncoming = !isOwner;
    final bool showSharingIndicator = isOutgoing || isIncoming;

    final collectionRowWidget = Flexible(
      flex: 6,
      child: Row(
        children: [
          SizedBox(
            height: 40,
            width: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                IconTile(
                  backgroundColor: colors.backgroundBase,
                  icon: collection.type == CollectionType.favorites
                      ? HugeIcon(
                          icon: HugeIcons.strokeRoundedStar,
                          color: colors.primary,
                        )
                      : HugeIcon(
                          icon: HugeIcons.strokeRoundedWallet05,
                          color: colors.textBase,
                        ),
                ),
                if (showSharingIndicator)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.fillLight,
                      ),
                      padding: const EdgeInsets.all(1.0),
                      child: HugeIcon(
                        icon: isOutgoing
                            ? HugeIcons.strokeRoundedCircleArrowUpRight
                            : HugeIcons.strokeRoundedCircleArrowDownLeft,
                        strokeWidth: 2.0,
                        color: colors.primary,
                        size: 16.0,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  collection.displayName ?? 'Unnamed Collection',
                  style: TextStyles.body,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                FutureBuilder<int>(
                  future: CollectionService.instance.getFileCount(collection),
                  builder: (context, snapshot) {
                    final fileCount = snapshot.data ?? 0;
                    return Text(
                      context.l10n.items(fileCount),
                      style: TextStyles.mini.copyWith(color: colors.textLight),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      onTap: () {
        if (onTapCallback != null) {
          onTapCallback!(collection);
        } else {
          _openCollection(context);
        }
      },
      onLongPress: () {
        if (onLongPressCallback != null) {
          onLongPressCallback!(collection);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: selectedCollections ?? ValueNotifier(false),
        builder: (context, _) {
          final bool isSelected =
              selectedCollections?.isCollectionSelected(collection) ?? false;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            padding: const EdgeInsets.only(left: 12, top: 12, bottom: 12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? colors.strokeDark : colors.fillLight,
                width: 1.5,
              ),
              color: colors.fillLight,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                collectionRowWidget,
                if (!isFavourite)
                  Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: SizedBox(
                      width: 44,
                      height: 24,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerRight,
                            children: [...previousChildren, ?currentChild],
                          );
                        },
                        child: isSelected
                            ? const SelectionCheckBadge(
                                key: ValueKey("selected"),
                              )
                            : showSharingIndicator
                            ? (isIncoming
                                  ? _buildOwnerAvatar(collection.owner)
                                  : (hasSharees
                                        ? _buildShareesAvatars(
                                            collection.sharees
                                                .whereType<User>()
                                                .toList(),
                                          )
                                        : const SizedBox(
                                            key: ValueKey("unselected"),
                                          )))
                            : const SizedBox(key: ValueKey("unselected")),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _openCollection(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CollectionPage(collection: collection),
      ),
    );
  }

  Widget _buildOwnerAvatar(User owner) {
    const double avatarSize = 24.0;

    return SizedBox(
      height: avatarSize,
      width: avatarSize,
      child: UserAvatarWidget(
        owner,
        type: AvatarType.mini,
        thumbnailView: true,
        config: Configuration.instance,
      ),
    );
  }

  Widget _buildShareesAvatars(List<User> sharees) {
    if (sharees.isEmpty) {
      return const SizedBox.shrink();
    }

    const int limitCountTo = 1;
    const double avatarSize = 24.0;
    const double overlapPadding = 20.0;

    final hasMore = sharees.length > limitCountTo;

    final double totalWidth = hasMore
        ? avatarSize + overlapPadding
        : avatarSize;

    return SizedBox(
      height: avatarSize,
      width: totalWidth,
      child: AlbumSharesIcons(
        sharees: sharees,
        padding: EdgeInsets.zero,
        limitCountTo: limitCountTo,
        type: AvatarType.mini,
        removeBorder: true,
      ),
    );
  }
}
