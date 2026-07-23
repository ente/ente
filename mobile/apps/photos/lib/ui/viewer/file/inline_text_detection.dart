import "dart:async";
import "dart:io";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:mobile_ocr/mobile_ocr.dart"
    show
        DisplayImageHelper,
        MobileOcr,
        OcrModelComponent,
        TextDetectorController,
        TextDetectorStrings,
        TextDetectorWidget,
        TextRegionDetectionResult,
        ZoomedInteractionPolicy;
import "package:photos/core/event_bus.dart";
import "package:photos/events/reset_zoom_of_photo_view_event.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/viewer/file/ocr/ocr_dot_wave_overlay.dart";
import "package:photos/ui/viewer/file/ocr/text_region_hit_test.dart";
import "package:photos/utils/image_util.dart";

/// Routes still-photo gestures from the viewer to its OCR overlay.
class InlineTextDetectionController {
  _InlineTextDetectionState? _state;

  void _attach(_InlineTextDetectionState state) => _state = state;

  void _detach(_InlineTextDetectionState state) {
    if (identical(_state, state)) {
      _state = null;
    }
  }

  void startTextSelectionAt(EnteFile file, Offset globalPosition) {
    final state = _state;
    if (state == null || state._didFileChange(file, state.widget.file)) return;
    state._handleLongPressAt(globalPosition);
  }
}

/// Inline on-demand text selection for the photo viewer.
///
/// Still images use long press as the signal to start recognition. Live and
/// motion photos precompute detector-only regions so a long press on text
/// starts selection, while a long press elsewhere continues to play video.
class InlineTextDetection extends StatefulWidget {
  final EnteFile file;
  final InlineTextDetectionController controller;
  final bool isGuestView;

  const InlineTextDetection({
    required this.file,
    required this.controller,
    required this.isGuestView,
    super.key,
  });

  @override
  State<InlineTextDetection> createState() => _InlineTextDetectionState();
}

class _InlineTextDetectionState extends State<InlineTextDetection> {
  static const int _maxCacheSize = 200;
  static const int _maxRegionDetectionAttempts = 2;
  static const Duration _regionDetectionTimeout = Duration(seconds: 15);
  static const Duration _regionDetectionRetryDelay = Duration(seconds: 1);
  static const double _globalGestureSlop = 18.0;
  static const double _photoGestureEdgeSlop = 8.0;
  static const double _textRegionHitSlop = 8.0;
  static final Map<String, _RegionCacheEntry> _regionCache = {};
  final Logger _logger = Logger("InlineTextDetection");
  final MobileOcr _mobileOcr = MobileOcr();
  final TextDetectorController _detectorController = TextDetectorController();

  bool _isEligible = false;
  String? _localFilePath;
  int _evaluationGeneration = 0;
  int _regionDetectionAttempt = 0;
  String? _activeRegionRequestId;
  Timer? _regionRetryTimer;
  TextRegionDetectionResult? _detectedRegions;
  bool _overlayActive = false;
  bool _isPreparingOnDemand = false;
  Offset? _pendingLongPressPosition;
  bool _zoomGestureSettled = false;
  Timer? _zoomSettleTimer;
  ZoomTransform? _lastSeenTransform;
  int _activePointers = 0;
  bool _isPinching = false;
  bool _isCurrentlyZoomed = false;
  int _globalActivePointers = 0;
  int? _trackedGlobalPointer;
  Offset? _trackedGlobalPointerDownPosition;
  bool _trackedGlobalPointerMoved = false;
  bool _trackedGlobalLongPressTriggered = false;
  Timer? _globalLongPressTimer;
  final Set<int> _ocrHitPointers = <int>{};
  String? _resolvedImageSizePath;
  Size? _resolvedImageSize;
  int _imageSizeRequestId = 0;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _evaluateFile();
  }

  @override
  void didUpdateWidget(covariant InlineTextDetection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._detach(this);
      widget.controller._attach(this);
    }
    if (_didFileChange(oldWidget.file, widget.file) ||
        oldWidget.isGuestView != widget.isGuestView) {
      _resetState();
      _evaluateFile();
    }
  }

  @override
  void dispose() {
    _cancelActiveRegionRequest();
    _regionRetryTimer?.cancel();
    _zoomSettleTimer?.cancel();
    _globalLongPressTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    widget.controller._detach(this);
    _detectorController.dispose();
    super.dispose();
  }

  void _resetState() {
    _evaluationGeneration++;
    _cancelActiveRegionRequest();
    _regionRetryTimer?.cancel();
    _regionRetryTimer = null;
    _regionDetectionAttempt = 0;
    _cancelTrackedGlobalPointer();
    _ocrHitPointers.clear();
    _imageSizeRequestId++;
    setState(() {
      _localFilePath = null;
      _detectedRegions = null;
      _overlayActive = false;
      _isPreparingOnDemand = false;
      _pendingLongPressPosition = null;
      _resolvedImageSizePath = null;
      _resolvedImageSize = null;
    });
  }

  bool _didFileChange(EnteFile oldFile, EnteFile newFile) {
    if ((oldFile is TrashFile) != (newFile is TrashFile)) return true;
    if (oldFile.generatedID != newFile.generatedID) return true;
    if (oldFile.uploadedFileID != newFile.uploadedFileID) return true;
    if (oldFile.localID != newFile.localID) return true;
    return false;
  }

  String _cacheKey(EnteFile file) {
    if (file.uploadedFileID != null) return "uploaded_${file.uploadedFileID}";
    if (file.localID != null) return "local_${file.localID}";
    return "generated_${file.generatedID}";
  }

  static void _cacheRegionResult(String key, _RegionCacheEntry result) {
    if (_regionCache.length >= _maxCacheSize) {
      _regionCache.remove(_regionCache.keys.first);
    }
    _regionCache[key] = result;
  }

  bool _isFileEligible(EnteFile file) {
    if (widget.isGuestView || file is TrashFile) return false;
    return file.fileType == FileType.image ||
        file.fileType == FileType.livePhoto;
  }

  bool get _requiresRegionRouting => widget.file.isLiveOrMotionPhoto;

  void _cancelActiveRegionRequest() {
    final requestId = _activeRegionRequestId;
    _activeRegionRequestId = null;
    if (requestId != null) {
      unawaited(_mobileOcr.cancelRequest(requestId).catchError((_) {}));
    }
  }

  Future<void> _evaluateFile({bool isRetry = false}) async {
    final bool isEligible = _isFileEligible(widget.file);
    final int generation = isRetry
        ? _evaluationGeneration
        : ++_evaluationGeneration;
    _logger.info(
      "evaluateFile: eligible=$isEligible, type=${widget.file.fileType}",
    );

    if (!isEligible) {
      if (!isRetry) {
        setState(() {
          _isEligible = false;
          _localFilePath = null;
          _detectedRegions = null;
        });
      }
      return;
    }

    if (!isRetry) {
      _regionDetectionAttempt = 0;
      setState(() {
        _isEligible = true;
        _localFilePath = null;
        _detectedRegions = null;
      });
    }
    if (!_requiresRegionRouting) {
      return;
    }

    final String cacheKey = _cacheKey(widget.file);
    if (!isRetry) {
      final _RegionCacheEntry? cached = _regionCache[cacheKey];
      if (cached != null && File(cached.localPath).existsSync()) {
        if (!mounted || generation != _evaluationGeneration) return;
        setState(() {
          _localFilePath = cached.localPath;
          _detectedRegions = cached.result;
        });
        return;
      }
      if (cached != null) {
        _regionCache.remove(cacheKey);
      }
    }

    _regionDetectionAttempt++;
    try {
      final File? localFile = await getFile(widget.file);
      if (!mounted || generation != _evaluationGeneration) return;
      if (localFile == null || !localFile.existsSync()) {
        throw StateError("Live-photo still is unavailable");
      }

      setState(() {
        _localFilePath = localFile.path;
      });
      final detectorStatus = await _mobileOcr.prepareModels(
        components: {OcrModelComponent.detector},
      );
      if (!mounted || generation != _evaluationGeneration) return;
      if (!detectorStatus.isReady) {
        throw StateError("OCR detector is not ready");
      }

      final regionRequestId = "photos-$cacheKey-$generation";
      _activeRegionRequestId = regionRequestId;
      late final TextRegionDetectionResult result;
      try {
        result = await _mobileOcr
            .detectTextRegions(
              imagePath: localFile.path,
              requestId: regionRequestId,
            )
            .timeout(_regionDetectionTimeout);
      } on TimeoutException {
        await _mobileOcr.cancelRequest(regionRequestId);
        rethrow;
      } finally {
        if (_activeRegionRequestId == regionRequestId) {
          _activeRegionRequestId = null;
        }
      }
      if (!mounted || generation != _evaluationGeneration) return;

      _cacheRegionResult(
        cacheKey,
        _RegionCacheEntry(localPath: localFile.path, result: result),
      );
      setState(() {
        _detectedRegions = result;
      });
      _logger.info("Detected ${result.regions.length} live-photo text regions");
    } catch (error, stackTrace) {
      if (!mounted || generation != _evaluationGeneration) return;
      _logger.warning(
        "Live-photo text region detection failed",
        error,
        stackTrace,
      );
      _scheduleRegionRetry(generation);
    }
  }

  void _scheduleRegionRetry(int generation) {
    if (_regionDetectionAttempt >= _maxRegionDetectionAttempts ||
        _regionRetryTimer != null) {
      return;
    }

    _regionRetryTimer = Timer(_regionDetectionRetryDelay, () {
      _regionRetryTimer = null;
      if (!mounted || generation != _evaluationGeneration) return;
      _logger.info("Retrying live-photo text region detection");
      unawaited(_evaluateFile(isRetry: true));
    });
  }

  void _activateOverlay() {
    if (_overlayActive) return;
    setState(() {
      _overlayActive = true;
    });
  }

  Size? get _displayImageSize {
    final regionImageSize = _detectedRegions?.imageSize;
    if (regionImageSize != null &&
        regionImageSize.width > 0 &&
        regionImageSize.height > 0) {
      return regionImageSize;
    }
    if (widget.file.hasDimensions &&
        widget.file.width > 0 &&
        widget.file.height > 0) {
      return Size(widget.file.width.toDouble(), widget.file.height.toDouble());
    }
    return _resolvedImageSize;
  }

  Future<void> _resolveDisplayImageSize(String localPath) async {
    if (widget.file.hasDimensions) return;
    if (_resolvedImageSizePath == localPath && _resolvedImageSize != null) {
      return;
    }

    final int requestId = ++_imageSizeRequestId;
    if (_resolvedImageSizePath != localPath || _resolvedImageSize != null) {
      setState(() {
        _resolvedImageSizePath = localPath;
        _resolvedImageSize = null;
      });
    }

    try {
      final displayPath = await DisplayImageHelper.ensureDisplayablePath(
        localPath,
      );
      final imageInfo = await getImageInfo(FileImage(File(displayPath)));
      if (!mounted ||
          requestId != _imageSizeRequestId ||
          _localFilePath != localPath) {
        return;
      }
      setState(() {
        _resolvedImageSize = Size(
          imageInfo.image.width.toDouble(),
          imageInfo.image.height.toDouble(),
        );
      });
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to resolve image dimensions for OCR overlay",
        error,
        stackTrace,
      );
    }
  }

  void _handleLongPressAt(Offset globalPosition) {
    if (!_isEligible) return;
    if (_overlayActive) return; // Already active, let overlay handle it
    if (!_isGlobalPointEligibleForOcrGesture(globalPosition)) return;
    if (_isPreparingOnDemand) return;
    setState(() {
      _pendingLongPressPosition = globalPosition;
    });
    if (_localFilePath != null) {
      _activateOverlay();
    } else {
      unawaited(_prepareStillImageOnDemand());
    }
  }

  Future<void> _prepareStillImageOnDemand() async {
    final generation = _evaluationGeneration;
    setState(() {
      _isPreparingOnDemand = true;
    });
    try {
      final localFile = await getFile(widget.file);
      if (!mounted || generation != _evaluationGeneration) return;
      if (localFile == null || !localFile.existsSync()) {
        throw StateError("Could not resolve image for OCR");
      }
      setState(() {
        _localFilePath = localFile.path;
        _isPreparingOnDemand = false;
      });
      unawaited(_resolveDisplayImageSize(localFile.path));
      _activateOverlay();
    } catch (error, stackTrace) {
      if (!mounted || generation != _evaluationGeneration) return;
      _logger.warning("Could not prepare image for OCR", error, stackTrace);
      setState(() {
        _isPreparingOnDemand = false;
        _pendingLongPressPosition = null;
      });
    }
  }

  void _handleLongPress(LongPressStartDetails details) {
    _handleLongPressAt(details.globalPosition);
  }

  bool get _canTrackTapToClearSelection =>
      _overlayActive && _detectorController.hasActiveSelection;

  bool get _canTrackZoomedPanFirstLongPress =>
      _overlayActive &&
      _isCurrentlyZoomed &&
      _zoomGestureSettled &&
      !_isPinching;

  bool _isPrimaryGlobalPointer(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse) {
      return event.buttons == kPrimaryMouseButton;
    }
    return true;
  }

  void _cancelTrackedGlobalPointer() {
    _globalLongPressTimer?.cancel();
    _globalLongPressTimer = null;
    _trackedGlobalPointer = null;
    _trackedGlobalPointerDownPosition = null;
    _trackedGlobalPointerMoved = false;
    _trackedGlobalLongPressTriggered = false;
  }

  void _handleGlobalPointerDown(PointerDownEvent event) {
    _globalActivePointers++;
    if (!_isPrimaryGlobalPointer(event)) {
      return;
    }
    if (_globalActivePointers != 1) {
      _cancelTrackedGlobalPointer();
      return;
    }

    final bool tapCanClearSelection = _canTrackTapToClearSelection;
    final bool pointOnInteractiveUi = _detectorController
        .isPointOnInteractiveSelectionUi(event.position);
    final bool pointEligibleForOcr = _isGlobalPointEligibleForOcrGesture(
      event.position,
    );
    final bool longPressCanSelect =
        pointEligibleForOcr &&
        _canTrackZoomedPanFirstLongPress &&
        !pointOnInteractiveUi &&
        _detectorController.isPointOnSelectableText(event.position);

    if (!tapCanClearSelection && !longPressCanSelect) {
      return;
    }

    if (pointOnInteractiveUi) {
      _cancelTrackedGlobalPointer();
      return;
    }

    _trackedGlobalPointer = event.pointer;
    _trackedGlobalPointerDownPosition = event.position;
    _trackedGlobalPointerMoved = false;
    _trackedGlobalLongPressTriggered = false;

    if (longPressCanSelect) {
      final Offset position = event.position;
      final int pointer = event.pointer;
      _globalLongPressTimer = Timer(kLongPressTimeout, () {
        if (!mounted ||
            _trackedGlobalPointer != pointer ||
            _trackedGlobalPointerMoved ||
            _globalActivePointers != 1 ||
            !_ocrHitPointers.contains(pointer) ||
            (longPressCanSelect && !_canTrackZoomedPanFirstLongPress)) {
          return;
        }
        _trackedGlobalLongPressTriggered = _detectorController
            .selectTextAtPosition(position);
      });
    }
  }

  void _handleGlobalPointerMove(PointerMoveEvent event) {
    if (event.pointer != _trackedGlobalPointer) {
      return;
    }
    final Offset? initialPosition = _trackedGlobalPointerDownPosition;
    if (initialPosition == null) {
      return;
    }
    if ((event.position - initialPosition).distance > _globalGestureSlop) {
      _trackedGlobalPointerMoved = true;
      _globalLongPressTimer?.cancel();
      _globalLongPressTimer = null;
    }
  }

  void _handleGlobalPointerEnd(PointerEvent event) {
    if (event.pointer == _trackedGlobalPointer) {
      final bool shouldClearSelection =
          !_trackedGlobalLongPressTriggered &&
          !_trackedGlobalPointerMoved &&
          _canTrackTapToClearSelection &&
          !_detectorController.isPointOnInteractiveSelectionUi(event.position);
      if (shouldClearSelection) {
        _detectorController.clearSelection();
      }
      _cancelTrackedGlobalPointer();
    }
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is PointerDownEvent) {
      _handleGlobalPointerDown(event);
      return;
    }

    if (event is PointerMoveEvent) {
      _handleGlobalPointerMove(event);
      return;
    }

    if (event is PointerUpEvent) {
      _globalActivePointers = _globalActivePointers > 0
          ? _globalActivePointers - 1
          : 0;
      _handleGlobalPointerEnd(event);
      return;
    }

    if (event is PointerCancelEvent) {
      _globalActivePointers = _globalActivePointers > 0
          ? _globalActivePointers - 1
          : 0;
      _handleGlobalPointerEnd(event);
    }
  }

  Rect _displayedPhotoRect(
    Size viewportSize, {
    bool allowViewportFallback = true,
  }) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return Rect.zero;
    }
    final Size? imageSize = _displayImageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return allowViewportFallback ? Offset.zero & viewportSize : Rect.zero;
    }

    return containedImageRect(viewportSize, imageSize);
  }

  bool _isLocalPointInDetectedTextRegion(
    Offset localPosition,
    Size viewportSize,
    ZoomTransform zoomTransform,
  ) {
    final detection = _detectedRegions;
    if (detection == null || detection.regions.isEmpty) {
      return false;
    }
    return isZoomedViewportPointInTextRegions(
      point: localPosition,
      viewportSize: viewportSize,
      imageSize: detection.imageSize,
      regions: detection.regions,
      scale: zoomTransform.scale,
      offset: zoomTransform.offset,
      hitSlop: _textRegionHitSlop,
    );
  }

  bool _isLocalPointEligibleForOcrGesture(
    Offset localPosition,
    Size viewportSize,
    ZoomTransform zoomTransform,
  ) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return false;
    }
    if (zoomTransform.scale <= 0 || !zoomTransform.scale.isFinite) {
      return false;
    }
    final point = viewportPointBeforeZoom(
      point: localPosition,
      viewportSize: viewportSize,
      scale: zoomTransform.scale,
      offset: zoomTransform.offset,
    );
    return _displayedPhotoRect(
      viewportSize,
    ).inflate(_photoGestureEdgeSlop / zoomTransform.scale).contains(point);
  }

  bool _isGlobalPointEligibleForOcrGesture(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is RenderBox &&
        renderObject.hasSize &&
        renderObject.size.width > 0 &&
        renderObject.size.height > 0) {
      return _isLocalPointEligibleForOcrGesture(
        renderObject.globalToLocal(globalPosition),
        renderObject.size,
        InheritedDetailPageState.of(context).zoomTransformNotifier.value,
      );
    }

    final Size? viewportSize = MediaQuery.maybeOf(context)?.size;
    if (viewportSize == null) {
      return false;
    }
    return _isLocalPointEligibleForOcrGesture(
      globalPosition,
      viewportSize,
      InheritedDetailPageState.of(context).zoomTransformNotifier.value,
    );
  }

  Widget _buildOcrGestureRegion(Widget child, {bool textRegionsOnly = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size viewportSize = constraints.biggest;
        return _OcrGestureHitTestBox(
          hitTest: (localPosition, globalPosition) {
            if (textRegionsOnly &&
                _detectorController.isPointOnInteractiveSelectionUi(
                  globalPosition,
                )) {
              return true;
            }
            final zoomTransform = InheritedDetailPageState.of(
              context,
            ).zoomTransformNotifier.value;
            if (!_isLocalPointEligibleForOcrGesture(
              localPosition,
              viewportSize,
              zoomTransform,
            )) {
              return false;
            }
            return !textRegionsOnly ||
                _detectorController.isPointOnSelectableText(globalPosition) ||
                _isLocalPointInDetectedTextRegion(
                  localPosition,
                  viewportSize,
                  zoomTransform,
                );
          },
          child: child,
        );
      },
    );
  }

  Widget _buildInactiveGestureLayer() {
    return Positioned.fill(
      child: _buildOcrGestureRegion(
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: _handleLongPress,
          child: const SizedBox.expand(),
        ),
        textRegionsOnly: _requiresRegionRouting,
      ),
    );
  }

  Widget _buildActiveGestureLayer(Widget overlay, {required bool ignoring}) {
    return Positioned.fill(
      child: _buildOcrGestureRegion(
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            _ocrHitPointers.add(event.pointer);
            _activePointers++;
            if (_activePointers >= 2 && !_isPinching) {
              setState(() {
                _isPinching = true;
                _zoomGestureSettled = false;
              });
            }
          },
          onPointerUp: (event) {
            _ocrHitPointers.remove(event.pointer);
            if (_activePointers > 0) _activePointers--;
            if (_activePointers < 2 && _isPinching) {
              setState(() => _isPinching = false);
            }
          },
          onPointerCancel: (event) {
            _ocrHitPointers.remove(event.pointer);
            if (_activePointers > 0) _activePointers--;
            if (_activePointers < 2 && _isPinching) {
              setState(() => _isPinching = false);
            }
          },
          child: IgnorePointer(ignoring: ignoring, child: overlay),
        ),
        textRegionsOnly: _requiresRegionRouting,
      ),
    );
  }

  Widget _buildImageBoundedProcessingOverlay() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Rect photoRect = _displayedPhotoRect(
          constraints.biggest,
          allowViewportFallback: false,
        );
        if (photoRect.isEmpty) {
          return const SizedBox.shrink();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fromRect(
              rect: photoRect,
              child: const IgnorePointer(child: OcrDotWaveOverlay()),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEligible) {
      return const SizedBox.shrink();
    }

    final detailState = InheritedDetailPageState.of(context);
    final isZoomedNotifier = detailState.isZoomedNotifier;

    if (!_overlayActive) {
      if (!_requiresRegionRouting) {
        return _isPreparingOnDemand
            ? _buildImageBoundedProcessingOverlay()
            : const SizedBox.shrink();
      }
      if (_localFilePath == null) {
        return const SizedBox.shrink();
      }
      if (_detectedRegions?.regions.isEmpty ?? true) {
        return const SizedBox.shrink();
      }
      return _buildInactiveGestureLayer();
    }
    if (_localFilePath == null) {
      return const SizedBox.shrink();
    }

    final zoomTransformNotifier = detailState.zoomTransformNotifier;

    return ValueListenableBuilder<bool>(
      valueListenable: isZoomedNotifier,
      builder: (context, isZoomed, _) {
        _isCurrentlyZoomed = isZoomed;
        if (!isZoomed) {
          _zoomGestureSettled = false;
          _zoomSettleTimer?.cancel();
          _lastSeenTransform = null;
        }
        return ValueListenableBuilder<ZoomTransform>(
          valueListenable: zoomTransformNotifier,
          builder: (context, transform, _) {
            // Only reset the debounce when the transform has genuinely changed.
            // Guarding on value change prevents the setState rebuild from the
            // timer itself from re-entering this block and restarting the timer,
            // which would create an infinite loop where _zoomGestureSettled
            // can never stay true.
            if (isZoomed && transform != _lastSeenTransform) {
              _lastSeenTransform = transform;
              _zoomGestureSettled = false;
              _zoomSettleTimer?.cancel();
              _zoomSettleTimer = Timer(const Duration(milliseconds: 200), () {
                if (mounted) {
                  setState(() {
                    _zoomGestureSettled = true;
                  });
                }
              });
            }

            Widget overlay = _buildInlineOverlay(
              context,
              isZoomed: isZoomed,
              uiScale: transform.scale,
              uiOffset: transform.offset,
            );

            // Always apply the Transform, even when not zoomed.
            // When not zoomed, transform == ZoomTransform.identity (scale=1,
            // offset=zero), so this is a no-op visually. Applying it
            // unconditionally means teardrops and text boundaries immediately
            // track zoom from the very first stream event, with no flash at
            // the unscaled position that occurs when the Transform was only
            // added after isZoomedNotifier fired.
            overlay = Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..translateByDouble(
                  transform.offset.dx,
                  transform.offset.dy,
                  0.0,
                  1.0,
                )
                ..scaleByDouble(
                  transform.scale,
                  transform.scale,
                  transform.scale,
                  1.0,
                ),
              child: overlay,
            );

            // Ignore pointer events when:
            // - Actively pinching (2+ fingers down) — let PhotoView handle zoom
            // - Zoomed but gesture not yet settled — transform is still changing
            final shouldIgnore =
                _isPinching || (isZoomed && !_zoomGestureSettled);

            return _buildActiveGestureLayer(overlay, ignoring: shouldIgnore);
          },
        );
      },
    );
  }

  Widget _buildInlineOverlay(
    BuildContext context, {
    required bool isZoomed,
    double uiScale = 1.0,
    Offset uiOffset = Offset.zero,
  }) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: _detectorController,
      builder: (context, child) {
        final bool isProcessing =
            _detectorController.userAttemptedInteraction &&
            _detectorController.isProcessing &&
            !_detectorController.hasSelectableText;
        return IgnorePointer(
          ignoring: isProcessing,
          child: Stack(
            fit: StackFit.expand,
            children: [
              child!,
              if (isProcessing) _buildImageBoundedProcessingOverlay(),
            ],
          ),
        );
      },
      child: TextDetectorWidget(
        key: ValueKey("ocr_$_localFilePath"),
        imagePath: _localFilePath!,
        autoDetect: true,
        backgroundColor: Colors.transparent,
        showUnselectedBoundaries: false,
        overlayOnly: true,
        showProcessingOverlay: false,
        showScanAnimation: false,
        showEditorHint: false,
        showNoTextMessageOnAutoDetect: false,
        initialInteractionPosition: _pendingLongPressPosition,
        controller: _detectorController,
        isImageZoomed: isZoomed,
        onDoubleTapWhenZoomed: isZoomed
            ? () {
                Bus.instance.fire(
                  ResetZoomOfPhotoView(
                    uploadedFileID: widget.file.uploadedFileID,
                    localID: widget.file.localID,
                  ),
                );
              }
            : null,
        uiScale: uiScale,
        uiOffset: uiOffset,
        zoomedInteractionPolicy: ZoomedInteractionPolicy.panFirst,
        strings: TextDetectorStrings(
          processingOverlayMessage: l10n.ocrProcessingOverlayMessage,
          selectionHint: l10n.ocrSelectionHint,
          noTextDetected: l10n.ocrNoTextDetected,
          retryButtonLabel: l10n.ocrRetryButtonLabel,
          modelsNetworkRequiredError: l10n.ocrModelsNetworkRequiredError,
          modelsPrepareFailed: l10n.ocrModelsPrepareFailed,
          imageNotFoundError: l10n.ocrImageNotFoundError,
          imageDecodeFailedError: l10n.ocrImageDecodeFailedError,
          genericDetectError: l10n.ocrGenericDetectError,
        ),
        onTextCopied: (text) {
          HapticFeedback.lightImpact();
        },
      ),
    );
  }
}

class _RegionCacheEntry {
  final String localPath;
  final TextRegionDetectionResult result;

  const _RegionCacheEntry({required this.localPath, required this.result});
}

class _OcrGestureHitTestBox extends SingleChildRenderObjectWidget {
  final bool Function(Offset localPosition, Offset globalPosition) hitTest;

  const _OcrGestureHitTestBox({required this.hitTest, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderOcrGestureHitTestBox(hitTest);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderOcrGestureHitTestBox renderObject,
  ) {
    renderObject.hitTestCallback = hitTest;
  }
}

class _RenderOcrGestureHitTestBox extends RenderProxyBox {
  bool Function(Offset localPosition, Offset globalPosition) hitTestCallback;

  _RenderOcrGestureHitTestBox(this.hitTestCallback);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.width <= 0 ||
        size.height <= 0 ||
        !hitTestCallback(position, localToGlobal(position))) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
