import "package:flutter/widgets.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_zoom.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class RewindPhoto extends StatefulWidget {
  const RewindPhoto(
    this.file, {
    this.placeholder = const Color(0xFFE4DCCD),
    this.focus = Alignment.center,
    this.zoomable = true,
    super.key,
  });

  final EnteFile file;
  final Color placeholder;
  final Alignment focus;
  final bool zoomable;

  @override
  State<RewindPhoto> createState() => _RewindPhotoState();
}

class _RewindPhotoState extends State<RewindPhoto> {
  var _lifted = false;
  var _zooming = false;

  Widget get _thumbnail => ThumbnailWidget(
    widget.file,
    key: ValueKey(widget.file.tag),
    alignment: widget.focus,
    rawThumbnail: true,
    shouldShowSyncStatus: false,
    shouldShowFavoriteIcon: false,
    shouldShowVideoOverlayIcon: false,
    thumbnailSize: thumbnailLargeSize,
    useRequestedThumbnailSizeForLocalCache: true,
    placeholderColor: widget.placeholder,
  );

  @override
  Widget build(BuildContext context) {
    final thumbnail = _thumbnail;
    if (!widget.zoomable) return thumbnail;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _zoom,
      child: Opacity(opacity: _lifted ? 0 : 1, child: thumbnail),
    );
  }

  Future<void> _zoom() async {
    if (_zooming) return;
    _zooming = true;
    await showRewindPhotoZoom(
      context,
      file: widget.file,
      focus: widget.focus,
      placeholder: _thumbnail,
      placement: () => mounted ? rewindPhotoPlacement(context) : null,
      onLifted: () => setState(() => _lifted = true),
      onReturned: _settle,
    );
    _settle();
  }

  void _settle() {
    _zooming = false;
    if (mounted && _lifted) setState(() => _lifted = false);
  }
}

void preloadRewindPhoto(EnteFile file) {
  if (file.isRemoteOnlyFile) {
    getThumbnailFromServer(file).ignore();
  } else {
    getThumbnailFromLocal(file, size: thumbnailLargeSize).ignore();
  }
}
