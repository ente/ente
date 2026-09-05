import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:photos/models/device_collection.dart';
import "package:photos/service_locator.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/ui/viewer/gallery/device/device_folder_page.dart';

class DeviceFolderListItem extends StatelessWidget {
  final DeviceCollection deviceCollection;
  final VoidCallback? onTap;

  const DeviceFolderListItem(this.deviceCollection, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final componentColors = context.componentColors;
    final isBackedUp = deviceCollection.shouldBackup;

    return ThumbnailListItem(
      backgroundColor: thumbnailListItemBackgroundColor(context),
      onTap:
          onTap ??
          () {
            routeToPage(context, DeviceFolderPage(deviceCollection));
          },
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(
              ThumbnailListItem.defaultLeadingRadius,
            ),
            child: ThumbnailWidget(
              deviceCollection.thumbnail!,
              shouldShowSyncStatus: false,
              key: Key(
                "device_folder:" +
                    deviceCollection.name +
                    deviceCollection.thumbnail!.tag,
              ),
            ),
          ),
          if (!isBackedUp && !isLocalGalleryMode)
            const Positioned(
              right: -4,
              bottom: -4,
              child: CollectionUnSyncedBadge(showBorder: true),
            ),
        ],
      ),
      title: Text(
        deviceCollection.name,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyles.body.copyWith(color: componentColors.textBase),
      ),
      subtitle: Text(
        context.strings.itemCount(count: deviceCollection.count),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: TextStyles.mini.copyWith(color: componentColors.textLight),
      ),
    );
  }
}
