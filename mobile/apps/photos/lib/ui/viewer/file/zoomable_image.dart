import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show Uint8List;

import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import "package:flutter_image_compress/flutter_image_compress.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/cache/thumbnail_in_memory_cache.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/events/files_updated_event.dart";
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/events/reset_zoom_of_photo_view_event.dart";
import "package:photos/events/retry_failed_image_load_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/module/download/download_error.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/download/thumbnail.dart';
import "package:photos/module/metadata/exif.dart";
import "package:photos/service_locator.dart" show flagService;
import "package:photos/src/rust/api/image_processing_api.dart" as rust_image;
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:photos/utils/image_util.dart';
import "package:photos/utils/ram_check_util.dart";

class ZoomableImage extends StatefulWidget {
  final EnteFile photo;
  final Function(bool)? shouldDisableScroll;
  final String? tagPrefix;
  final Decoration? backgroundDecoration;
  final bool shouldCover;
  final bool isGuestView;
  final bool isFromMemories;
  final bool enableVerticalSwipeActions;
  final Function({required int memoryDuration})? onFinalFileLoad;
  final ValueChanged<File>? onFinalImageLoaded;

  const ZoomableImage(
    this.photo, {
    super.key,
    this.shouldDisableScroll,
    required this.tagPrefix,
    this.backgroundDecoration,
    this.shouldCover = false,
    this.isGuestView = false,
    this.isFromMemories = false,
    this.enableVerticalSwipeActions = true,
    this.onFinalFileLoad,
    this.onFinalImageLoaded,
  });

  @override
  State<ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<ZoomableImage> {
  late Logger _logger;
  late EnteFile _photo;
  ImageProvider? _imageProvider;
  bool _loadedSmallThumbnail = false;
  bool _loadingLargeThumbnail = false;
  bool _loadedLargeThumbnail = false;
  bool _loadingFinalImage = false;
  bool _loadedFinalImage = false;
  bool _finalImageDecryptionFailed = false;
  // Downloads cannot be cancelled. Defer a retry until the current attempt
  // fails.
  bool _pendingFinalImageRetry = false;
  bool _convertToSupportedFormat = false;
  bool _showingThumbnailFallback = false;
  // Start the memory slideshow timer when any image is ready, without waiting
  // for the original.
  bool _firedOnReady = false;
  bool _interactionLocked = false;
  final _imageZoomController = ImageZoomController();
  late final StreamSubscription<ResetZoomOfPhotoView> _resetZoomSubscription;
  late final StreamSubscription<RetryFailedImageLoadEvent>
  _retryFailedLoadSubscription;

  // Flutter can crash while decoding very large images.
  // https://github.com/flutter/flutter/issues/110331
  static const int _defaultMaxPixels = 100000000; // 100MP
  static const int _lowRamMaxPixels = 24000000; // 24MP

  int get _maxImagePixels =>
      hasLessThan5GBRAM ? _lowRamMaxPixels : _defaultMaxPixels;

  bool get isTooLargeImage => _photo.width * _photo.height > _maxImagePixels;

  @override
  void initState() {
    super.initState();
    _photo = widget.photo;
    _logger = Logger("ZoomableImage");
    _logger.info('initState for ${_photo.generatedID} with tag ${_photo.tag}');
    // Render a cached thumbnail on first paint so prefetched files never
    // flash the spinner while the async load resolves.
    final cachedThumbnail =
        ThumbnailInMemoryLruCache.get(_photo, thumbnailLargeSize) ??
        ThumbnailInMemoryLruCache.get(_photo, thumbnailSmallSize);
    if (cachedThumbnail != null) {
      _imageProvider = Image.memory(cachedThumbnail).image;
      _loadedSmallThumbnail = true;
      _notifyReadyOnce();
    }
    _imageZoomController.addListener(_onZoomChanged);

    _resetZoomSubscription = Bus.instance.on<ResetZoomOfPhotoView>().listen((
      event,
    ) {
      if (event.isSamePhoto(
        uploadedFileID: widget.photo.uploadedFileID,
        localID: widget.photo.localID,
      )) {
        unawaited(_imageZoomController.reset());
      }
    });

    _retryFailedLoadSubscription = Bus.instance
        .on<RetryFailedImageLoadEvent>()
        .listen((_) {
          if (!mounted || _loadedFinalImage) return;
          _finalImageDecryptionFailed = false;
          if (!_loadedSmallThumbnail && _photo.isRemoteOnlyFile) {
            // Thumbnail requests are deduplicated. Evict the failed request
            // before retrying.
            removePendingGetThumbnailRequestIfAny(_photo);
          }
          if (_loadingFinalImage) {
            _pendingFinalImageRetry = true;
          }
          setState(() {});
        });
  }

  void _onZoomChanged() {
    if (!mounted) return;
    final transform = _imageZoomController.transform;
    final isZooming = _imageZoomController.isZoomed;
    final state = InheritedDetailPageState.maybeOf(context);
    state?.isZoomedNotifier.value = isZooming;
    state?.zoomTransformNotifier.value = isZooming
        ? ZoomTransform(scale: transform.scale, offset: transform.offset)
        : ZoomTransform.identity;
  }

  void _onInteractionLockChanged(bool isLocked) {
    widget.shouldDisableScroll?.call(isLocked);
    if (_interactionLocked == isLocked || !mounted) return;
    setState(() => _interactionLocked = isLocked);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_imageZoomController.isZoomed) return;
    if (details.delta.dy > dragSensitivity) {
      unawaited(Navigator.maybePop(context));
    } else if (details.delta.dy < -dragSensitivity) {
      showDetailsSheet(context, widget.photo);
    }
  }

  @override
  void dispose() {
    _imageZoomController
      ..removeListener(_onZoomChanged)
      ..dispose();
    _resetZoomSubscription.cancel();
    _retryFailedLoadSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_photo.isRemoteOnlyFile) {
      _loadNetworkImage();
    } else {
      _loadLocalImage(context);
    }
    Widget content;

    if (_imageProvider != null) {
      content = ImageZoomViewer(
        imageProvider: _imageProvider!,
        controller: _imageZoomController,
        imageSizeHint: _photo.width > 0 && _photo.height > 0
            ? Size(_photo.width.toDouble(), _photo.height.toDouble())
            : null,
        heroTag: widget.tagPrefix! + _photo.tag,
        backgroundDecoration: widget.backgroundDecoration,
        initialFit: widget.shouldCover ? BoxFit.cover : BoxFit.contain,
        // Collage already owns its transform with an outer InteractiveViewer.
        gesturesEnabled: !widget.shouldCover,
        onInteractionLockChanged: _onInteractionLockChanged,
        loadingBuilder: (context, event) {
          // Match the loading state to the image's on-screen size during the
          // hero animation.
          final screenSize = MediaQuery.sizeOf(context);
          final fittedSize = _photo.width > 0 && _photo.height > 0
              ? applyBoxFit(
                  BoxFit.contain,
                  Size(_photo.width.toDouble(), _photo.height.toDouble()),
                  screenSize,
                ).destination
              : screenSize;

          return Center(
            child: SizedBox(
              width: fittedSize.width,
              height: fittedSize.height,
              child: widget.isFromMemories
                  ? const _DelayedLoadingIndicator()
                  : const EnteLoadingWidget(color: Colors.white),
            ),
          );
        },
      );
    } else if (_showingThumbnailFallback) {
      content = Center(
        child: ThumbnailWidget(
          _photo,
          rawThumbnail: true,
          thumbnailSize: thumbnailLargeSize,
          fit: BoxFit.contain,
        ),
      );
    } else {
      content = widget.isFromMemories
          ? const _DelayedLoadingIndicator()
          : const EnteLoadingWidget(color: Colors.white);
    }

    final GestureDragUpdateCallback? verticalDragCallback =
        _interactionLocked ||
            widget.isGuestView ||
            !widget.enableVerticalSwipeActions
        ? null
        : _onVerticalDragUpdate;
    return GestureDetector(
      onVerticalDragUpdate: verticalDragCallback,
      child: content,
    );
  }

  // Cached images can call this during build. Defer the parent callback until
  // the build is complete.
  void _notifyReadyOnce() {
    if (_firedOnReady) return;
    _firedOnReady = true;
    scheduleMicrotask(() {
      if (!mounted) return;
      widget.onFinalFileLoad?.call(memoryDuration: 5);
    });
  }

  void _loadNetworkImage() {
    if (!_loadedSmallThumbnail && !_loadedFinalImage) {
      final cachedThumbnail = ThumbnailInMemoryLruCache.get(_photo);
      if (cachedThumbnail != null) {
        _imageProvider = Image.memory(cachedThumbnail).image;
        _loadedSmallThumbnail = true;
        _notifyReadyOnce();
      } else {
        getThumbnailFromServer(_photo)
            .then((file) {
              final imageProvider = Image.memory(file).image;
              if (mounted) {
                precacheImage(imageProvider, context)
                    .then((value) {
                      if (mounted) {
                        setState(() {
                          _imageProvider = imageProvider;
                          _loadedSmallThumbnail = true;
                        });
                        _notifyReadyOnce();
                      }
                    })
                    .catchError((e) {
                      _logger.severe(
                        "Could not load image " + _photo.toString(),
                      );
                      _loadedSmallThumbnail = true;
                    });
              }
            })
            .catchError((e, s) {
              _logger.warning(
                "Failed to fetch thumbnail from server for ${_photo.tag}",
                e,
                s,
              );
            });
      }
    }
    if (!_loadedFinalImage &&
        !_loadingFinalImage &&
        !_finalImageDecryptionFailed) {
      _loadingFinalImage = true;
      getFileFromServer(_photo, throwOnDecryptionFailure: true)
          .then((file) {
            if (file != null) {
              _onFileLoaded(file);
            } else {
              // Most network failures return null; retry them like exceptions.
              _onFinalImageFetchFailed();
            }
          })
          .catchError((e, s) {
            _logger.warning(
              "Failed to fetch final image from server for ${_photo.tag}",
              e,
              s,
            );
            if (e is DownloadDecryptionFailedError) {
              _onFinalImageDecryptionFailed();
            } else {
              _onFinalImageFetchFailed();
            }
          });
    }
  }

  void _loadLocalImage(BuildContext context) {
    if (!_loadedSmallThumbnail &&
        !_loadedLargeThumbnail &&
        !_loadedFinalImage) {
      final cachedThumbnail = ThumbnailInMemoryLruCache.get(
        _photo,
        thumbnailSmallSize,
      );
      if (cachedThumbnail != null) {
        _imageProvider = Image.memory(cachedThumbnail).image;
        _loadedSmallThumbnail = true;
        _notifyReadyOnce();
      }
    }

    if (!_loadingLargeThumbnail &&
        !_loadedLargeThumbnail &&
        !_loadedFinalImage) {
      _loadingLargeThumbnail = true;
      getThumbnailFromLocal(
        _photo,
        size: thumbnailLargeSize,
        quality: 100,
      ).then((cachedThumbnail) {
        if (cachedThumbnail != null) {
          if (!context.mounted) return;
          _onLargeThumbnailLoaded(Image.memory(cachedThumbnail).image, context);
        }
      });
    }

    if (!_loadingFinalImage && !_loadedFinalImage && !_photo.isDeviceTrash) {
      _loadingFinalImage = true;
      getFile(
        _photo,
        isOrigin:
            Platform.isIOS &&
            _isGIF(), // since on iOS GIFs playback only when origin-files are loaded
      ).then((file) {
        if (file != null && file.existsSync()) {
          _onFileLoaded(file);
        } else {
          _logger.info("File was deleted " + _photo.toString());
          if (_photo.uploadedFileID != null) {
            _photo.localID = null;
            FilesDB.instance.update(_photo);
            _loadNetworkImage();
          } else {
            FilesDB.instance.deleteLocalFile(_photo);
            Bus.instance.fire(
              LocalPhotosUpdatedEvent(
                [_photo],
                type: EventType.deletedFromDevice,
                source: "zoomPreview",
              ),
            );
          }
        }
      });
    }
  }

  void _onLargeThumbnailLoaded(
    ImageProvider imageProvider,
    BuildContext context,
  ) {
    if (mounted && !_loadedFinalImage) {
      precacheImage(imageProvider, context).then((value) {
        if (mounted && !_loadedFinalImage) {
          setState(() {
            _imageProvider = imageProvider;
            _loadedLargeThumbnail = true;
          });
          _notifyReadyOnce();
        }
      });
    }
  }

  void _onFileLoaded(File file) {
    // Android's HEIC decoder can produce a glitched image without throwing.
    // Use Rust when the image dimensions make it safe.
    if (_isAndroidHeic()) {
      unawaited(_loadAndroidHeic(file));
      return;
    }

    _loadWithPlatformDecoder(file);
  }

  Future<void> _loadAndroidHeic(File file) async {
    if (_shouldUseRustHeicDecoder()) {
      await _loadHeicWithRust(file);
      return;
    }

    if (!mounted) {
      return;
    }

    // Android's HEIC decoder ignores EXIF orientation. Rotate through
    // FlutterImageCompress when needed.
    if (await _heicNeedsExifRotation(file)) {
      await _loadInSupportedFormat(file, "HEIC requires EXIF rotation");
      return;
    }

    _loadWithPlatformDecoder(file);
  }

  Future<bool> _heicNeedsExifRotation(File file) async {
    try {
      final exif = await readExifAsync(file);
      final orientation = exif['Image Orientation']?.values.firstAsInt() ?? 1;
      return orientation > 1;
    } catch (e, s) {
      _logger.warning(
        "Failed to read EXIF orientation for ${_photo.displayName}",
        e,
        s,
      );
      return false;
    }
  }

  void _loadWithPlatformDecoder(File file) {
    ImageProvider imageProvider;
    if (isTooLargeImage) {
      _logger.info(
        "Handling very large image (${_photo.width}x${_photo.height}) by decreasing resolution to ${_maxImagePixels ~/ 1000000}MP to prevent crash",
      );
      final aspectRatio = _photo.width / _photo.height;
      final maxPixels = min(50000000, _maxImagePixels);
      final targetHeight = sqrt(maxPixels / aspectRatio);
      final targetWidth = aspectRatio * targetHeight;

      imageProvider = Image.file(
        file,
        gaplessPlayback: true,
        cacheWidth: targetWidth.round(),
        cacheHeight: targetHeight.round(),
      ).image;
    } else {
      imageProvider = Image.file(file, gaplessPlayback: true).image;
    }

    if (mounted) {
      precacheImage(
        imageProvider,
        context,
        onError: (exception, s) async {
          _logger.warning(
            "Failed to load image ${_photo.displayName} with error: $exception, attempting fallback",
          );
          unawaited(_loadInSupportedFormat(file, exception));
        },
      ).then((value) {
        if (mounted && !_loadedFinalImage && !_convertToSupportedFormat) {
          _updateViewWithFinalImage(imageProvider, file);
        }
      });
    }
  }

  void _onFinalImageFetchFailed() {
    _loadingFinalImage = false;
    if (_pendingFinalImageRetry && mounted && !_loadedFinalImage) {
      _pendingFinalImageRetry = false;
      setState(() {});
    }
  }

  void _onFinalImageDecryptionFailed() {
    _loadingFinalImage = false;
    _finalImageDecryptionFailed = true;
    if (!mounted) return;
    unawaited(showDownloadDecryptionFailedDialog(context: context));
  }

  Future<void> _loadHeicWithRust(File file) async {
    final imageProvider = await _tryDecodeHeicWithRust(file);
    if (imageProvider != null) {
      await _tryDisplayRustDecodedImage(
        file,
        imageProvider,
        fallbackToSupportedFormatOnFailure: true,
      );
      return;
    }

    unawaited(
      _loadInSupportedFormat(
        file,
        "Rust HEIC decode failed",
        skipRustDecoder: true,
      ),
    );
  }

  Future<void> _updateViewWithFinalImage(
    ImageProvider imageProvider,
    File file,
  ) async {
    setState(() {
      _imageProvider = imageProvider;
      _loadedFinalImage = true;
      _logger.info("Final image loaded");
    });
    _notifyReadyOnce();
    widget.onFinalImageLoaded?.call(file);
  }

  bool _isGIF() => _photo.displayName.toLowerCase().endsWith(".gif");

  bool _isAndroidHeic() => Platform.isAndroid && _isHeic();

  bool _shouldUseRustHeicDecoder() {
    if (!_isAndroidHeic()) {
      return false;
    }
    if (!flagService.useRustForHeicDecoder) {
      return false;
    }
    if (!_photo.hasDimensions) {
      return false;
    }
    if (isTooLargeImage) {
      return false;
    }

    return true;
  }

  Future<ImageProvider<Object>?> _tryDecodeHeicWithRust(
    File file, {
    int? quality,
  }) async {
    if (!_shouldUseRustHeicDecoder()) {
      return null;
    }

    try {
      _logger.info("Using Rust HEIC decoder for ${_photo.generatedID}");
      final Uint8List rustBytes = await rust_image.decodeToJpeg(
        imagePath: file.path,
        quality: quality,
      );
      final MemoryImage imageProvider = MemoryImage(rustBytes);
      _logger.info("Rust HEIC decode succeeded for ${_photo.generatedID}");
      return imageProvider;
    } catch (e) {
      _logger.warning("Rust HEIC decode failed for ${_photo.generatedID}: $e");
      return null;
    }
  }

  Future<bool> _tryDisplayRustDecodedImage(
    File file,
    ImageProvider<Object> imageProvider, {
    required bool fallbackToSupportedFormatOnFailure,
  }) async {
    try {
      if (!mounted) {
        return false;
      }

      await precacheImage(imageProvider, context);
      if (mounted && !_loadedFinalImage) {
        await _updateViewWithFinalImage(imageProvider, file);
      }
      return true;
    } catch (e) {
      _logger.warning(
        "Flutter failed to decode Rust JPEG bytes for ${_photo.generatedID}: $e",
      );
      if (fallbackToSupportedFormatOnFailure) {
        unawaited(_loadInSupportedFormat(file, e, skipRustDecoder: true));
      }
      return false;
    }
  }

  bool _isHeic() {
    final ext = _photo.displayName.toLowerCase().split('.').last;
    return ext == 'heic' || ext == 'heif';
  }

  bool _isRawFile() {
    final extension = _photo.displayName.toLowerCase().split('.').last;
    return isRawImageExtension(extension);
  }

  Future<void> _loadInSupportedFormat(
    File file,
    Object unsupportedErr, {
    bool skipRustDecoder = false,
  }) async {
    // FlutterImageCompress crashes on RAW files. Show the thumbnail instead.
    if (_isRawFile()) {
      _logger.info(
        "Skipping compression for RAW file ${_photo.displayName}, using thumbnail fallback",
      );
      _convertToSupportedFormat = true;
      if (mounted) {
        setState(() {
          _showingThumbnailFallback = true;
        });
        InheritedDetailPageState.maybeOf(
          context,
        )?.showingThumbnailFallbackNotifier.value = detailPageFileIdentifier(
          _photo,
        );
        _notifyReadyOnce();
      }
      return;
    }

    _logger.info(
      "Compressing ${_photo.displayName} to viewable format due to $unsupportedErr",
    );
    _convertToSupportedFormat = true;

    if (!skipRustDecoder) {
      final imageProvider = await _tryDecodeHeicWithRust(file);
      final didDisplayRustImage =
          imageProvider != null &&
          await _tryDisplayRustDecodedImage(
            file,
            imageProvider,
            fallbackToSupportedFormatOnFailure: false,
          );
      if (didDisplayRustImage) {
        return;
      }
    }

    Uint8List? compressedFile;
    if (isTooLargeImage) {
      _logger.info(
        "Compressing very large image (${_photo.width}x${_photo.height}) more aggressively down to ${_maxImagePixels ~/ 1000000}MP",
      );
      final aspectRatio = _photo.width / _photo.height;
      final maxPixels = min(50000000, _maxImagePixels);
      final targetHeight = sqrt(maxPixels / aspectRatio);
      final targetWidth = aspectRatio * targetHeight;

      compressedFile = await FlutterImageCompress.compressWithFile(
        file.path,
        minWidth: targetWidth.round(),
        minHeight: targetHeight.round(),
        quality: 85,
      );
    } else {
      compressedFile = await FlutterImageCompress.compressWithFile(
        file.path,
        minHeight: 8000,
        minWidth: 8000,
      );
    }

    if (!mounted) {
      return;
    }

    if (compressedFile != null) {
      final imageProvider = MemoryImage(compressedFile);

      unawaited(
        precacheImage(imageProvider, context).then((value) {
          if (mounted) {
            _updateViewWithFinalImage(imageProvider, file);
          }
        }),
      );
    } else {
      _logger.severe(
        "Failed to compress image ${_photo.displayName} to viewable format",
      );
      if (mounted) {
        setState(() {
          _showingThumbnailFallback = true;
        });
        InheritedDetailPageState.maybeOf(
          context,
        )?.showingThumbnailFallbackNotifier.value = detailPageFileIdentifier(
          _photo,
        );
        _notifyReadyOnce();
      }
    }
  }
}

// Delay the spinner so prefetched memory images do not flash it between slides.
class _DelayedLoadingIndicator extends StatefulWidget {
  const _DelayedLoadingIndicator();

  @override
  State<_DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<_DelayedLoadingIndicator> {
  static const Duration _delay = Duration(milliseconds: 400);
  Timer? _timer;
  bool _showSpinner = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_delay, () {
      if (mounted) setState(() => _showSpinner = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSpinner) return const SizedBox.expand();
    return const EnteLoadingWidget(color: Colors.white);
  }
}
