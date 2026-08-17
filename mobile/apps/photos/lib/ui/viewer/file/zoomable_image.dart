import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show Uint8List;

import 'package:ente_ui/components/loading_widget.dart';
import 'package:flutter/material.dart';
import "package:flutter_image_compress/flutter_image_compress.dart";
import 'package:logging/logging.dart';
import 'package:photo_view/photo_view.dart';
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
import 'package:photos/module/download/file.dart';
import 'package:photos/module/download/thumbnail.dart';
import "package:photos/module/metadata/exif.dart";
import "package:photos/service_locator.dart" show flagService;
import "package:photos/src/rust/api/image_processing_api.dart" as rust_image;
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/actions/file/file_actions.dart";
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
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
  // Downloads cannot be cancelled. Defer a retry until the current attempt
  // fails.
  bool _pendingFinalImageRetry = false;
  bool _convertToSupportedFormat = false;
  bool _showingThumbnailFallback = false;
  // Start the memory slideshow timer when any image is ready, without waiting
  // for the original.
  bool _firedOnReady = false;
  ValueChanged<PhotoViewScaleState>? _scaleStateChangedCallback;
  bool _isZooming = false;
  PhotoViewController _photoViewController = PhotoViewController();
  final _scaleStateController = PhotoViewScaleStateController();
  StreamSubscription<dynamic>? _zoomStreamSubscription;

  // Baseline PhotoView scale for the current image/controller when the image
  // is at its contained size. ZoomTransform.scale is reported relative to this.
  double? _initialScale;
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
    _scaleStateChangedCallback = (value) {
      if (widget.shouldDisableScroll != null) {
        widget.shouldDisableScroll!(value != PhotoViewScaleState.initial);
      }
      _isZooming = value != PhotoViewScaleState.initial;
      final state = InheritedDetailPageState.maybeOf(context);
      state?.isZoomedNotifier.value = _isZooming;
      if (!_isZooming) {
        _initialScale = _photoViewController.scale ?? _initialScale;
        state?.zoomTransformNotifier.value = ZoomTransform.identity;
      }
    };

    _subscribeToZoomStream();

    _resetZoomSubscription = Bus.instance.on<ResetZoomOfPhotoView>().listen((
      event,
    ) {
      if (event.isSamePhoto(
        uploadedFileID: widget.photo.uploadedFileID,
        localID: widget.photo.localID,
      )) {
        _scaleStateController.scaleState = PhotoViewScaleState.initial;
      }
    });

    _retryFailedLoadSubscription = Bus.instance
        .on<RetryFailedImageLoadEvent>()
        .listen((_) {
          if (!mounted || _loadedFinalImage) return;
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

  void _subscribeToZoomStream() {
    _zoomStreamSubscription = _photoViewController.outputStateStream.listen((
      value,
    ) {
      if (!mounted) return;
      final state = InheritedDetailPageState.maybeOf(context);
      if (value.scale == null) return;
      if (!_isZooming) {
        _initialScale = value.scale;
        state?.zoomTransformNotifier.value = ZoomTransform.identity;
        return;
      }
      _initialScale ??= value.scale;
      state?.zoomTransformNotifier.value = ZoomTransform(
        scale: value.scale! / _initialScale!,
        offset: value.position,
      );
    });
  }

  @override
  void dispose() {
    _zoomStreamSubscription?.cancel();
    _photoViewController.dispose();
    _scaleStateController.dispose();
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
      content = PhotoViewGestureDetectorScope(
        axis: Axis.vertical,
        child: PhotoView(
          // Rebuild PhotoView when the original replaces a zoomed thumbnail so
          // the adjusted zoom takes effect. Memories do not zoom; a stable key
          // lets gaplessPlayback replace the image without flashing the layer
          // underneath.
          key: widget.isFromMemories ? null : ValueKey(_loadedFinalImage),
          imageProvider: _imageProvider,
          controller: _photoViewController,
          filterQuality: FilterQuality.high,
          scaleStateController: _scaleStateController,
          scaleStateChangedCallback: _scaleStateChangedCallback,
          minScale: widget.shouldCover
              ? PhotoViewComputedScale.covered
              : PhotoViewComputedScale.contained,
          gaplessPlayback: true,
          heroAttributes: PhotoViewHeroAttributes(
            tag: widget.tagPrefix! + _photo.tag,
          ),
          backgroundDecoration: widget.backgroundDecoration as BoxDecoration?,
          loadingBuilder: (context, event) {
            // Match the loading state to the image's on-screen size during the
            // hero animation.
            final screenDimensions = MediaQuery.sizeOf(context);
            late final double screenRelativeImageWidth;
            late final double screenRelativeImageHeight;
            final screenWidth = screenDimensions.width;
            final screenHeight = screenDimensions.height;

            final aspectRatioOfScreen = screenWidth / screenHeight;
            final aspectRatioOfImage = _photo.width / _photo.height;

            if (aspectRatioOfImage > aspectRatioOfScreen) {
              screenRelativeImageWidth = screenWidth;
              screenRelativeImageHeight = screenWidth / aspectRatioOfImage;
            } else if (aspectRatioOfImage < aspectRatioOfScreen) {
              screenRelativeImageHeight = screenHeight;
              screenRelativeImageWidth = screenHeight * aspectRatioOfImage;
            } else {
              screenRelativeImageWidth = screenWidth;
              screenRelativeImageHeight = screenHeight;
            }

            return Center(
              child: SizedBox(
                width: screenRelativeImageWidth,
                height: screenRelativeImageHeight,
                child: widget.isFromMemories
                    ? const _DelayedLoadingIndicator()
                    : const EnteLoadingWidget(color: Colors.white),
              ),
            );
          },
        ),
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
        _isZooming || widget.isGuestView
        ? null
        : (d) => {
            if (!_isZooming)
              {
                if (d.delta.dy > dragSensitivity)
                  {
                    {unawaited(Navigator.maybePop(context))},
                  }
                else if (d.delta.dy < (dragSensitivity * -1))
                  {showDetailsSheet(context, widget.photo)},
              },
          };
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
    if (!_loadedFinalImage && !_loadingFinalImage) {
      _loadingFinalImage = true;
      getFileFromServer(_photo)
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
            _onFinalImageFetchFailed();
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

    if (!_loadingFinalImage && !_loadedFinalImage) {
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
    await _updatePhotoViewController(
      previewImageProvider: _imageProvider,
      finalImageProvider: imageProvider,
    );
    setState(() {
      _imageProvider = imageProvider;
      _loadedFinalImage = true;
      _logger.info("Final image loaded");
    });
    _notifyReadyOnce();
    widget.onFinalImageLoaded?.call(file);
  }

  Future<void> _updatePhotoViewController({
    required ImageProvider? previewImageProvider,
    required ImageProvider finalImageProvider,
  }) async {
    final bool shouldFixPosition =
        previewImageProvider != null &&
        _isZooming &&
        _photoViewController.scale != null;
    ImageInfo? finalImageInfo;
    if (shouldFixPosition) {
      final prevImageInfo = await getImageInfo(previewImageProvider);
      finalImageInfo = await getImageInfo(finalImageProvider);
      final previousScale = _photoViewController.scale!;
      final previousRelativeScale = _initialScale != null && _initialScale! > 0
          ? previousScale / _initialScale!
          : null;
      final scale =
          previousScale /
          (finalImageInfo.image.width / prevImageInfo.image.width);
      final currentPosition = _photoViewController.value.position;
      unawaited(_zoomStreamSubscription?.cancel());
      _photoViewController = PhotoViewController(
        initialPosition: currentPosition,
        initialScale: scale,
      );
      if (previousRelativeScale != null &&
          previousRelativeScale.isFinite &&
          previousRelativeScale > 0) {
        _initialScale = scale / previousRelativeScale;
      } else {
        _initialScale = null;
      }
      _subscribeToZoomStream();
      // Prevent auto-zoom when the original loads after two double taps.
      _scaleStateController.scaleState = PhotoViewScaleState.zoomedIn;
    }
    final bool canUpdateMetadata = _photo.canEditMetaInfo;
    if (finalImageInfo == null && canUpdateMetadata && !_photo.hasDimensions) {
      finalImageInfo = await getImageInfo(finalImageProvider);
    }
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
