import "dart:async";
import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:mobile_ocr/mobile_ocr.dart" show MobileOcr;
import "package:photos/core/event_bus.dart";
import "package:photos/events/reset_zoom_of_photo_view_event.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/viewer/file/ocr/display_image_helper.dart";
import "package:photos/ui/viewer/file/ocr/ocr_dot_wave_overlay.dart";
import "package:photos/ui/viewer/file/ocr/text_detector_widget.dart";
import "package:photos/ui/viewer/file/ocr/text_overlay_widget.dart"
    show ZoomedInteractionPolicy;
import "package:photos/utils/image_util.dart";

/// Inline text detection widget that mimics Apple's Live Text behavior:
///
/// 1. Quick `hasText()` check runs silently when the image loads.
/// 2. If text is found and the user stays on the image for 1 second, full
///    detection runs automatically and text boundaries appear as a
///    transparent overlay.
/// 3. Long press on detected text lets users select and copy.
/// 4. Taps and swipes pass through to the underlying image viewer.
class InlineTextDetection extends StatefulWidget {
  final EnteFile file;
  final ValueListenable<bool> enableFullScreenNotifier;
  final bool isGuestView;

  const InlineTextDetection({
    required this.file,
    required this.enableFullScreenNotifier,
    required this.isGuestView,
    super.key,
  });

  @override
  State<InlineTextDetection> createState() => _InlineTextDetectionState();
}

class _InlineTextDetectionState extends State<InlineTextDetection> {
  static const int _maxCacheSize = 200;
  static const Duration _hasTextTimeout = Duration(seconds: 15);
  static const Duration _autoActivateDelay = Duration(seconds: 1);
  static const double _globalGestureSlop = 18.0;
  static const double _photoGestureEdgeSlop = 8.0;
  static const double _visibleBottomControlsHeight = 120.0;
  static final Map<String, _HasTextResult> _hasTextCache = {};
  final Logger _logger = Logger("InlineTextDetection");
  final MobileOcr _mobileOcr = MobileOcr();
  final TextDetectorController _detectorController = TextDetectorController();

  bool _isEligible = false;
  String? _localFilePath;
  int _requestId = 0;
  bool _overlayActive = false;
  Offset? _pendingLongPressPosition;
  Timer? _autoActivateTimer;
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
  String? _resolvedImageSizePath;
  Size? _resolvedImageSize;
  int _imageSizeRequestId = 0;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _evaluateFile();
  }

  @override
  void didUpdateWidget(covariant InlineTextDetection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_didFileChange(oldWidget.file, widget.file)) {
      _resetState();
      _evaluateFile();
    }
  }

  @override
  void dispose() {
    _autoActivateTimer?.cancel();
    _zoomSettleTimer?.cancel();
    _globalLongPressTimer?.cancel();
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _detectorController.dispose();
    super.dispose();
  }

  void _resetState() {
    _autoActivateTimer?.cancel();
    _cancelTrackedGlobalPointer();
    _imageSizeRequestId++;
    setState(() {
      _localFilePath = null;
      _overlayActive = false;
      _pendingLongPressPosition = null;
      _resolvedImageSizePath = null;
      _resolvedImageSize = null;
    });
  }

  bool _didFileChange(EnteFile oldFile, EnteFile newFile) {
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

  static void _cacheResult(String key, _HasTextResult result) {
    if (_hasTextCache.length >= _maxCacheSize) {
      _hasTextCache.remove(_hasTextCache.keys.first);
    }
    _hasTextCache[key] = result;
  }

  bool _isFileEligible(EnteFile file) {
    return file.fileType == FileType.image ||
        file.fileType == FileType.livePhoto;
  }

  Future<bool?> _checkHasText(File localFile) async {
    _logger.info("running hasText check");
    try {
      final bool hasText = await _mobileOcr
          .hasText(imagePath: localFile.path)
          .timeout(_hasTextTimeout);
      _logger.info("hasText result: $hasText");
      return hasText;
    } on TimeoutException {
      _logger.info("hasText timed out");
      return null;
    } catch (error, stackTrace) {
      _logger.warning("hasText failed", error, stackTrace);
      return null;
    }
  }

  Future<void> _evaluateFile() async {
    final bool isEligible = _isFileEligible(widget.file);
    final int requestId = ++_requestId;
    _logger.info(
      "evaluateFile: eligible=$isEligible, type=${widget.file.fileType}",
    );

    if (!isEligible) {
      setState(() {
        _isEligible = false;
        _localFilePath = null;
      });
      return;
    }

    setState(() {
      _isEligible = true;
      _localFilePath = null;
    });

    // Check cache first
    final String cacheKey = _cacheKey(widget.file);
    final _HasTextResult? cached = _hasTextCache[cacheKey];
    if (cached != null) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _localFilePath = cached.localPath;
        if (!cached.hasText) {
          _pendingLongPressPosition = null;
        }
      });
      if (cached.hasText) {
        final localPath = cached.localPath;
        if (localPath != null) {
          unawaited(_resolveDisplayImageSize(localPath));
        }
        _scheduleAutoActivate(requestId);
      }
      return;
    }

    // Resolve local file
    try {
      final File? localFile = await getFile(widget.file);
      if (!mounted || requestId != _requestId) return;
      if (localFile == null || !localFile.existsSync()) {
        _cacheResult(cacheKey, const _HasTextResult(hasText: false));
        setState(() {
          _pendingLongPressPosition = null;
        });
        return;
      }

      final bool? hasText = await _checkHasText(localFile);
      if (!mounted || requestId != _requestId) return;
      if (hasText == null) {
        setState(() {
          _pendingLongPressPosition = null;
        });
        return;
      }

      final result = _HasTextResult(
        hasText: hasText,
        localPath: hasText ? localFile.path : null,
      );
      _cacheResult(cacheKey, result);

      setState(() {
        _localFilePath = result.localPath;
        if (!hasText) {
          _pendingLongPressPosition = null;
        }
      });

      if (hasText) {
        unawaited(_resolveDisplayImageSize(localFile.path));
        if (_pendingLongPressPosition != null) {
          _activateOverlay();
        } else {
          _scheduleAutoActivate(requestId);
        }
      }
    } catch (error, stackTrace) {
      _logger.severe("Text detection pre-check failed", error, stackTrace);
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _pendingLongPressPosition = null;
      });
    }
  }

  void _activateOverlay() {
    _autoActivateTimer?.cancel();
    if (_overlayActive) return;
    setState(() {
      _overlayActive = true;
    });
  }

  void _scheduleAutoActivate(int requestId) {
    _autoActivateTimer?.cancel();
    _autoActivateTimer = Timer(_autoActivateDelay, () {
      if (!mounted || requestId != _requestId) return;
      if (_localFilePath == null || _overlayActive) return;
      _activateOverlay();
    });
  }

  Size? get _displayImageSize {
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
    if (_overlayActive) return; // Already active, let overlay handle it
    if (!_isGlobalPointEligibleForOcrGesture(globalPosition)) return;
    _autoActivateTimer?.cancel();
    setState(() {
      _pendingLongPressPosition = globalPosition;
    });
    // If hasText already completed and file path is ready, activate now
    if (_localFilePath != null) {
      _activateOverlay();
      return;
    }
    unawaited(_evaluateFile());
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

  bool get _canRetryHasTextFromLongPress =>
      _isEligible &&
      !_overlayActive &&
      _localFilePath == null &&
      _pendingLongPressPosition == null &&
      widget.file is! TrashFile &&
      !widget.isGuestView;

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
    final bool longPressCanRetry =
        pointEligibleForOcr &&
        widget.enableFullScreenNotifier.value &&
        _canRetryHasTextFromLongPress;
    final bool longPressCanSelect =
        pointEligibleForOcr &&
        _canTrackZoomedPanFirstLongPress &&
        !pointOnInteractiveUi &&
        _detectorController.isPointOnSelectableText(event.position);

    if (!tapCanClearSelection && !longPressCanSelect && !longPressCanRetry) {
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

    if (longPressCanSelect || longPressCanRetry) {
      final Offset position = event.position;
      final int pointer = event.pointer;
      _globalLongPressTimer = Timer(kLongPressTimeout, () {
        if (!mounted ||
            _trackedGlobalPointer != pointer ||
            _trackedGlobalPointerMoved ||
            _globalActivePointers != 1 ||
            (longPressCanSelect && !_canTrackZoomedPanFirstLongPress)) {
          return;
        }
        if (longPressCanSelect) {
          _trackedGlobalLongPressTriggered = _detectorController
              .selectTextAtPosition(position);
        } else if (_canRetryHasTextFromLongPress) {
          _trackedGlobalLongPressTriggered = true;
          _handleLongPressAt(position);
        }
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

    final double imageAspect = imageSize.width / imageSize.height;
    final double viewportAspect = viewportSize.width / viewportSize.height;
    late final double displayWidth;
    late final double displayHeight;
    if (imageAspect > viewportAspect) {
      displayWidth = viewportSize.width;
      displayHeight = displayWidth / imageAspect;
    } else {
      displayHeight = viewportSize.height;
      displayWidth = displayHeight * imageAspect;
    }

    return Rect.fromLTWH(
      (viewportSize.width - displayWidth) / 2,
      (viewportSize.height - displayHeight) / 2,
      displayWidth,
      displayHeight,
    );
  }

  bool _isLocalPointInVisibleControls(Offset localPosition, Size viewportSize) {
    if (widget.enableFullScreenNotifier.value) {
      return false;
    }

    final EdgeInsets padding =
        MediaQuery.maybeOf(context)?.padding ?? EdgeInsets.zero;
    final double topControlsHeight = padding.top + kToolbarHeight;
    final double bottomControlsHeight =
        padding.bottom + _visibleBottomControlsHeight;

    return localPosition.dy < topControlsHeight ||
        localPosition.dy > viewportSize.height - bottomControlsHeight;
  }

  bool _isLocalPointEligibleForOcrGesture(
    Offset localPosition,
    Size viewportSize,
  ) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) {
      return false;
    }
    if (_isLocalPointInVisibleControls(localPosition, viewportSize)) {
      return false;
    }
    return _displayedPhotoRect(
      viewportSize,
    ).inflate(_photoGestureEdgeSlop).contains(localPosition);
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
      );
    }

    final Size? viewportSize = MediaQuery.maybeOf(context)?.size;
    if (viewportSize == null) {
      return false;
    }
    return _isLocalPointEligibleForOcrGesture(globalPosition, viewportSize);
  }

  Widget _buildOcrGestureRegion(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final Size viewportSize = constraints.biggest;
        return _OcrGestureHitTestBox(
          hitTest: (localPosition) =>
              _isLocalPointEligibleForOcrGesture(localPosition, viewportSize),
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
      ),
    );
  }

  Widget _buildActiveGestureLayer(Widget overlay, {required bool ignoring}) {
    return Positioned.fill(
      child: _buildOcrGestureRegion(
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) {
            _activePointers++;
            if (_activePointers >= 2 && !_isPinching) {
              setState(() {
                _isPinching = true;
                _zoomGestureSettled = false;
              });
            }
          },
          onPointerUp: (_) {
            if (_activePointers > 0) _activePointers--;
            if (_activePointers < 2 && _isPinching) {
              setState(() => _isPinching = false);
            }
          },
          onPointerCancel: (_) {
            if (_activePointers > 0) _activePointers--;
            if (_activePointers < 2 && _isPinching) {
              setState(() => _isPinching = false);
            }
          },
          child: IgnorePointer(ignoring: ignoring, child: overlay),
        ),
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
    if (!_isEligible || widget.file is TrashFile || widget.isGuestView) {
      return const SizedBox.shrink();
    }

    final detailState = InheritedDetailPageState.of(context);
    final isZoomedNotifier = detailState.isZoomedNotifier;

    if (_localFilePath == null) {
      return const SizedBox.shrink();
    }
    if (!_overlayActive) {
      return _buildInactiveGestureLayer();
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

class _HasTextResult {
  final bool hasText;
  final String? localPath;

  const _HasTextResult({required this.hasText, this.localPath});
}

class _OcrGestureHitTestBox extends SingleChildRenderObjectWidget {
  final bool Function(Offset localPosition) hitTest;

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
  bool Function(Offset localPosition) hitTestCallback;

  _RenderOcrGestureHitTestBox(this.hitTestCallback);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (size.width <= 0 || size.height <= 0 || !hitTestCallback(position)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
