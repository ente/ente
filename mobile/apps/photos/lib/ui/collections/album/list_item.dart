import "package:ente_components/ente_components.dart";
import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/sharing/album_share_info_widget.dart";
import "package:photos/ui/sharing/user_avator_widget.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class AlbumListItemWidget extends StatelessWidget {
  static final double _trailingWidth =
      getAvatarSize(AvatarType.medium) + getOverlapPadding(AvatarType.medium);

  final Collection collection;
  final void Function(Collection)? onTapCallback;
  final void Function(Collection)? onLongPressCallback;
  final SelectedAlbums? selectedAlbums;
  final bool isSelected;

  const AlbumListItemWidget(
    this.collection, {
    super.key,
    this.onTapCallback,
    this.onLongPressCallback,
    this.selectedAlbums,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedAlbums == null) {
      return _buildItem(context, isSelected: isSelected);
    }
    return ListenableBuilder(
      listenable: selectedAlbums!,
      builder: (context, _) {
        return _buildItem(
          context,
          isSelected: selectedAlbums!.isAlbumSelected(collection),
        );
      },
    );
  }

  Widget _buildItem(BuildContext context, {required bool isSelected}) {
    final bool isOwner = collection.isOwner(
      Configuration.instance.getUserID() ?? -1,
    );
    final bool isOutgoing = isOwner && collection.hasSharees;
    final bool isIncoming = !isOwner;
    final bool showSharingIndicator = isOutgoing || isIncoming;
    final bool showLinkIndicator = isOwner && collection.hasLink;
    final bool isFavoriteAlbum = collection.type == CollectionType.favorites;
    final bool showPin = isOwner
        ? collection.isPinned
        : collection.hasShareePinned();
    final bool showArchive = isOwner
        ? collection.isArchived()
        : collection.hasShareeArchived();

    final colors = context.componentColors;
    return ThumbnailListItem(
      backgroundColor: thumbnailListItemBackgroundColor(context),
      selectedBorderColor: colors.strokeDark,
      isSelected: isSelected,
      onTap: onTapCallback == null ? null : () => onTapCallback!(collection),
      onLongPress: onLongPressCallback == null
          ? null
          : () => onLongPressCallback!(collection),
      leading: _AlbumListItemCover(collection: collection),
      title: _buildTitle(
        context,
        showSharingIndicator: showSharingIndicator,
        isOutgoing: isOutgoing,
        showLinkIndicator: showLinkIndicator,
      ),
      subtitle: FutureBuilder<int>(
        future: CollectionsService.instance.getFileCount(collection),
        initialData: CollectionsService.instance.getCachedFileCount(collection),
        builder: (context, snapshot) {
          String countText = "";
          if (snapshot.hasData) {
            countText = AppLocalizations.of(
              context,
            ).itemCount(count: snapshot.data!);
          } else if (snapshot.hasError) {
            Logger("AlbumListItemWidget").severe(
              "Failed to fetch file count of collection",
              snapshot.error,
            );
          } else {
            final cachedCount = CollectionsService.instance.getCachedFileCount(
              collection,
            );
            if (cachedCount != null) {
              countText = AppLocalizations.of(
                context,
              ).itemCount(count: cachedCount);
            }
          }
          return _buildSubtitle(
            context,
            text: countText,
            showPin: showPin,
            showArchive: showArchive,
            isFavoriteAlbum: isFavoriteAlbum,
          );
        },
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: SizedBox(
          width: _trailingWidth,
          height: getAvatarSize(AvatarType.medium),
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
            child: _buildTrailingIndicator(
              context,
              isSelected: isSelected,
              isOwner: isOwner,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(
    BuildContext context, {
    required bool showSharingIndicator,
    required bool isOutgoing,
    required bool showLinkIndicator,
  }) {
    final colors = context.componentColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            collection.displayName,
            style: TextStyles.body.copyWith(color: colors.textBase),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showSharingIndicator) ...[
          const SizedBox(width: 6),
          CollectionShareBadge(
            isOutgoing: isOutgoing,
            variant: CollectionShareBadgeVariant.outlined,
          ),
        ],
        if (showLinkIndicator) ...[
          const SizedBox(width: 4),
          const CollectionLinkBadge(
            variant: CollectionShareBadgeVariant.outlined,
          ),
        ],
      ],
    );
  }

  Widget _buildSubtitle(
    BuildContext context, {
    required String text,
    required bool showPin,
    required bool showArchive,
    required bool isFavoriteAlbum,
  }) {
    final colors = context.componentColors;
    final textStyle = TextStyles.mini.copyWith(color: colors.textLight);
    final hasStatus = showPin || showArchive || isFavoriteAlbum;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: Text(
            text,
            style: textStyle,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hasStatus) ...[
          Text(" \u2022 ", style: textStyle),
          if (showPin)
            ImageIcon(
              const AssetImage("assets/collection_pin.png"),
              size: 12,
              color: colors.textBase,
            ),
          if (showArchive)
            HugeIcon(
              icon: HugeIcons.strokeRoundedArchive03,
              size: 12,
              color: colors.textBase,
              strokeWidth: 2.0,
            ),
          if (isFavoriteAlbum)
            Icon(EnteIcons.favoriteFilled, size: 12, color: colors.textBase),
        ],
      ],
    );
  }

  Widget _buildTrailingIndicator(
    BuildContext context, {
    required bool isSelected,
    required bool isOwner,
  }) {
    final double avatarSize = getAvatarSize(AvatarType.medium);
    final double slotOverlap = getOverlapPadding(AvatarType.medium);

    if (isSelected) {
      return const CollectionSelectedBadge(key: ValueKey("selected"));
    }
    if (!isOwner) {
      return UserAvatarWidget(
        key: const ValueKey("owner"),
        collection.owner,
        type: AvatarType.medium,
        thumbnailView: true,
      );
    }
    if (collection.hasSharees) {
      final sharees = collection.getSharees();
      final int total = sharees.length;
      final int limit = total > 2 ? 1 : 2;
      final int displayCount = total.clamp(1, limit).toInt();
      final bool hasMore = total > limit;
      final double contentWidth =
          avatarSize + (displayCount - 1 + (hasMore ? 1 : 0)) * slotOverlap;
      return SizedBox(
        key: const ValueKey("sharees"),
        width: contentWidth,
        height: avatarSize,
        child: AlbumSharesIcons(
          sharees: sharees,
          type: AvatarType.medium,
          limitCountTo: limit,
          padding: EdgeInsets.zero,
        ),
      );
    }
    return const SizedBox.shrink(key: ValueKey("unselected"));
  }
}

class _AlbumListItemCover extends StatelessWidget {
  final Collection collection;

  const _AlbumListItemCover({required this.collection});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(
            ThumbnailListItem.defaultLeadingRadius,
          ),
          child: SizedBox.expand(
            child: FutureBuilder<EnteFile?>(
              future: CollectionsService.instance.getCover(collection),
              initialData: CollectionsService.instance.getCoverCache(
                collection,
              ),
              builder: (context, snapshot) {
                final thumbnail =
                    snapshot.data ??
                    CollectionsService.instance.getCoverCache(collection);
                if (thumbnail != null) {
                  return ThumbnailWidget(
                    thumbnail,
                    shouldShowFavoriteIcon: false,
                    shouldShowOwnerAvatar: false,
                    shouldShowSyncStatus: false,
                    key: Key("album_list:${collection.id}:${thumbnail.tag}"),
                  );
                }
                return const NoThumbnailWidget(
                  borderRadius: ThumbnailListItem.defaultLeadingRadius,
                  addBorder: false,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
