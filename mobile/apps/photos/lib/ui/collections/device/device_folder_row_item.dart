import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:figma_squircle/figma_squircle.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/device_collection.dart';
import "package:photos/service_locator.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/ui/viewer/gallery/device/device_folder_page.dart';

class DeviceFolderRowItem extends StatelessWidget {
  final DeviceCollection deviceCollection;
  final double sideOfThumbnail;

  static const _cornerRadius = 20.0;
  static const _cornerSmoothing = 0.6;
  static const _overlayPadding = 8.0;
  static const _thumbnailToTextSpacing = 8.0;
  static const _titleToSubtitleSpacing = 2.0;

  const DeviceFolderRowItem(
    this.deviceCollection, {

    ///120 is default for the 'on device' scrollview in albums section
    this.sideOfThumbnail = 120,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isBackedUp = deviceCollection.shouldBackup;
    final colors = context.componentColors;
    return GestureDetector(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: sideOfThumbnail,
            width: sideOfThumbnail,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                ClipSmoothRect(
                  radius: SmoothBorderRadius(
                    cornerRadius: _cornerRadius,
                    cornerSmoothing: _cornerSmoothing,
                  ),
                  child: SizedBox(
                    height: sideOfThumbnail,
                    width: sideOfThumbnail,
                    child: Hero(
                      tag:
                          "device_folder:" +
                          deviceCollection.name +
                          deviceCollection.thumbnail!.tag,
                      transitionOnUserGestures: true,
                      child: Stack(
                        children: [
                          ThumbnailWidget(
                            deviceCollection.thumbnail!,
                            shouldShowSyncStatus: false,
                            key: Key(
                              "device_folder:" +
                                  deviceCollection.name +
                                  deviceCollection.thumbnail!.tag,
                            ),
                          ),
                          if (!isBackedUp && !isLocalGalleryMode)
                            const Positioned(
                              right: _overlayPadding,
                              bottom: _overlayPadding,
                              child: CollectionUnSyncedBadge(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _thumbnailToTextSpacing),
          SizedBox(
            width: sideOfThumbnail,
            child: Text(
              deviceCollection.name,
              textAlign: TextAlign.left,
              style: TextStyles.body.copyWith(color: colors.textBase),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: _titleToSubtitleSpacing),
          SizedBox(
            width: sideOfThumbnail,
            child: Text(
              AppLocalizations.of(
                context,
              ).itemCount(count: deviceCollection.count),
              textAlign: TextAlign.left,
              style: TextStyles.mini.copyWith(color: colors.textLight),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      onTap: () {
        routeToPage(context, DeviceFolderPage(deviceCollection));
      },
    );
  }
}
