import "package:flutter/widgets.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class RewindPhoto extends StatelessWidget {
  const RewindPhoto(
    this.file, {
    this.placeholder = const Color(0xFFE4DCCD),
    this.focus = Alignment.center,
    super.key,
  });

  final EnteFile file;
  final Color placeholder;
  final Alignment focus;

  @override
  Widget build(BuildContext context) {
    return ThumbnailWidget(
      file,
      key: ValueKey(file.tag),
      alignment: focus,
      rawThumbnail: true,
      shouldShowSyncStatus: false,
      shouldShowFavoriteIcon: false,
      shouldShowVideoOverlayIcon: false,
      thumbnailSize: thumbnailLargeSize,
      useRequestedThumbnailSizeForLocalCache: true,
      placeholderColor: placeholder,
    );
  }
}

void preloadRewindPhoto(EnteFile file) {
  if (file.isRemoteOnlyFile) {
    getThumbnailFromServer(file).ignore();
  } else {
    getThumbnailFromLocal(file, size: thumbnailLargeSize).ignore();
  }
}
