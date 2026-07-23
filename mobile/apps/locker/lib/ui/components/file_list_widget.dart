import "package:ente_components/ente_components.dart";
import "package:ente_sharing/models/user.dart";
import "package:ente_sharing/user_avator_widget.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/models/selected_files.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/db/locker_db.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/services/info_file_service.dart";
import "package:locker/services/trash/models/trash_file.dart";
import "package:locker/utils/file_icon_utils.dart";
import "package:locker/utils/file_util.dart";
import "package:locker/utils/info_item_utils.dart";

class FileListWidget extends StatelessWidget {
  final EnteFile file;
  final SelectedFiles? selectedFiles;
  final void Function(EnteFile)? onTapCallback;
  final void Function(EnteFile)? onLongPressCallback;

  const FileListWidget({
    super.key,
    required this.file,
    this.selectedFiles,
    this.onTapCallback,
    this.onLongPressCallback,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    final collection = file.collectionID != null
        ? CollectionService.instance.getFromCache(file.collectionID!)
        : null;

    final int? currentUserID = Configuration.instance.getUserID();
    final bool isOwner =
        collection != null &&
        currentUserID != null &&
        collection.isOwner(currentUserID);
    final List<User> sharees =
        collection?.sharees.whereType<User>().toList() ?? const [];
    final bool hasSharees = sharees.isNotEmpty;
    final bool isOutgoing = isOwner && hasSharees;
    final bool isIncoming = collection != null && !isOwner;
    final bool isTrashFile = file is TrashFile;
    final bool showSharingIndicator =
        !isTrashFile && (isOutgoing || isIncoming);
    final isMarkedOffline = LockerDB.instance.isFileMarkedOffline(file);

    final fileRowWidget = Flexible(
      flex: 6,
      child: Row(
        children: [
          SizedBox(
            height: 40,
            width: 40,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _buildFileIcon(context, backgroundColor: colors.backgroundBase),
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
                  file.displayName,
                  style: TextStyles.body,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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
          onTapCallback!(file);
        } else {
          FileUtil.openFile(context, file);
        }
      },
      onLongPress: () {
        if (onLongPressCallback != null) {
          onLongPressCallback!(file);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: ListenableBuilder(
        listenable: selectedFiles ?? ValueNotifier(false),
        builder: (context, _) {
          final bool isSelected = selectedFiles?.isFileSelected(file) ?? false;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? colors.strokeDark : colors.fillLight,
                width: 1.5,
              ),
              color: colors.fillLight,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
            ),
            child: Row(
              children: [
                fileRowWidget,
                const SizedBox(width: 12),
                SizedBox(
                  width: 24,
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
                    child: _buildTrailingIndicator(
                      color: colors.textLight,
                      isSelected: isSelected,
                      isIncoming: isIncoming,
                      isMarkedOffline: !isTrashFile && isMarkedOffline,
                      owner: collection?.owner,
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

  Widget _buildFileIcon(
    BuildContext context, {
    required Color backgroundColor,
  }) {
    if (InfoFileService.instance.isInfoFile(file)) {
      try {
        final infoItem = InfoFileService.instance.extractInfoFromFile(file);
        if (infoItem != null) {
          return InfoItemUtils.getInfoIcon(
            context,
            infoItem.type,
            backgroundColor: backgroundColor,
          );
        }
      } catch (e) {
        // Fallback to default icon if extraction fails
      }
    }

    return FileIconUtils.getFileIcon(
      context,
      file.displayName,
      backgroundColor: backgroundColor,
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

  Widget _buildTrailingIndicator({
    required Color color,
    required bool isSelected,
    required bool isIncoming,
    required bool isMarkedOffline,
    required User? owner,
  }) {
    if (isSelected) {
      return const SelectionCheckBadge(key: ValueKey("selected"));
    }

    if (isMarkedOffline) {
      return SvgPicture.asset(
        "assets/svg/keep_offline.svg",
        key: const ValueKey("offline"),
        width: 20.0,
        height: 20.0,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
    }

    if (isIncoming && owner != null) {
      return _buildOwnerAvatar(owner);
    }

    return const SizedBox(key: ValueKey("unselected"));
  }
}
