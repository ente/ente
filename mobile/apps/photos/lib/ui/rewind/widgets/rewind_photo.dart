import "dart:async";
import "dart:math";
import "dart:ui" as ui;

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
    this.decoded,
    super.key,
  });

  final EnteFile file;
  final Color placeholder;
  final Alignment focus;
  final bool zoomable;
  final ui.Image? decoded;

  @override
  State<RewindPhoto> createState() => RewindPhotoState();
}

class RewindPhotoState extends State<RewindPhoto> {
  var _lifted = false;
  var _zooming = false;
  var _failures = 0;
  var _reloads = 0;

  @override
  void didUpdateWidget(RewindPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.file != oldWidget.file) _failures = 0;
  }

  Future<void> _reload() async {
    final file = widget.file;
    final cache = RewindThumbnailCache();
    bool shows() => mounted && widget.file == file;
    do {
      await Future<void>.delayed(rewindRetryAfter(_failures++));
      if (!shows()) return;
    } while (file.isUploaded && !await cache.save(file));
    if (shows()) setState(() => _reloads++);
  }

  Widget _thumbnail({VoidCallback? onLoadFailed}) => switch (widget.decoded) {
    final decoded? => RawImage(
      image: decoded,
      fit: BoxFit.cover,
      alignment: widget.focus,
    ),
    null => ThumbnailWidget(
      widget.file,
      key: ValueKey((widget.file.tag, _reloads)),
      alignment: widget.focus,
      rawThumbnail: true,
      shouldShowSyncStatus: false,
      shouldShowFavoriteIcon: false,
      shouldShowVideoOverlayIcon: false,
      thumbnailSize: thumbnailLargeSize,
      useRequestedThumbnailSizeForLocalCache: true,
      placeholderColor: widget.placeholder,
      onLoadFailed: onLoadFailed,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final thumbnail = _thumbnail(onLoadFailed: () => unawaited(_reload()));
    if (!widget.zoomable) return thumbnail;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: zoom,
      child: Opacity(opacity: _lifted ? 0 : 1, child: thumbnail),
    );
  }

  Future<void> zoom() async {
    if (_zooming) return;
    _zooming = true;
    await showRewindPhotoZoom(
      context,
      file: widget.file,
      focus: widget.focus,
      placeholder: _thumbnail(),
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

const _retryAfterSeconds = [3, 6, 12, 24, 48];
const _libraryPatience = Duration(seconds: 10);
const _serverPatience = Duration(seconds: 20);

Duration rewindRetryAfter(int attempt) => Duration(
  seconds: _retryAfterSeconds[min(attempt, _retryAfterSeconds.length - 1)],
);

Future<bool> loadRewindPhoto(EnteFile file) async {
  final isOnDevice =
      !file.isRemoteOnlyFile &&
      await getThumbnailFromLocal(file, size: thumbnailLargeSize) != null;
  if (isOnDevice) return true;
  if (!file.isUploaded) return false;
  await getThumbnailFromServer(file);
  return true;
}

void preloadRewindPhoto(EnteFile file) => loadRewindPhoto(file).ignore();

class RewindThumbnailCache {
  RewindThumbnailCache({this.stopsAfterServerStall = false});

  final bool stopsAfterServerStall;
  var _libraryStalled = false;
  var _serverStalled = false;

  bool get serverStalled => _serverStalled;

  Future<bool> save(EnteFile file) async {
    if (!file.isUploaded) return false;
    try {
      if (await cachedThumbnailPath(file).exists()) return true;
    } catch (_) {
      return false;
    }
    if (!file.isRemoteOnlyFile &&
        !_libraryStalled &&
        await _savesFromLibrary(file)) {
      return true;
    }
    if (stopsAfterServerStall && _serverStalled) return false;
    return _savesFromServer(file);
  }

  Future<bool> _savesFromLibrary(EnteFile file) async {
    try {
      final saved = await getThumbnailForUploadedFile(
        file,
      ).timeout(_libraryPatience);
      return saved != null;
    } on TimeoutException {
      _libraryStalled = true;
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _savesFromServer(EnteFile file) async {
    try {
      await getThumbnailFromServer(file).timeout(_serverPatience);
      return true;
    } on TimeoutException {
      _serverStalled = true;
      return false;
    } catch (_) {
      return false;
    }
  }
}
