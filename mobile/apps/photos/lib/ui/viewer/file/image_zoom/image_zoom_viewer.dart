import "dart:async";

import "package:flutter/material.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_geometry.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_stage_policy.dart";

export "package:photos/ui/viewer/file/image_zoom/image_zoom_stage_policy.dart"
    show ImageZoomStage;

const double _kZoomEpsilon = 0.001;

// At the initial transform, parent PageView/dismiss gestures own one-finger
// drags and this widget handles the first two-finger pinch manually. Once the
// image is zoomed, InteractiveViewer owns pan and subsequent pinch gestures.
// Published transforms are relative to the initial fit, not the raw matrix.

typedef ImageZoomLoadingBuilder =
    Widget Function(BuildContext context, ImageChunkEvent? progress);

@immutable
class ImageZoomTransform {
  static const identity = ImageZoomTransform(scale: 1.0, offset: Offset.zero);

  final double scale;
  final Offset offset;

  const ImageZoomTransform({required this.scale, required this.offset});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageZoomTransform &&
          other.scale == scale &&
          other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

abstract interface class _ImageZoomControllerDelegate {
  Future<void> reset({required bool animated});
}

class ImageZoomController extends ChangeNotifier {
  ImageZoomTransform _transform = ImageZoomTransform.identity;
  ImageZoomStage _stage = ImageZoomStage.initial;
  _ImageZoomControllerDelegate? _delegate;

  ImageZoomTransform get transform => _transform;
  ImageZoomStage get stage => _stage;

  bool get isZoomed =>
      (_transform.scale - 1.0).abs() > _kZoomEpsilon ||
      _transform.offset.distanceSquared > _kZoomEpsilon * _kZoomEpsilon;

  Future<void> reset({bool animated = true}) async {
    await _delegate?.reset(animated: animated);
  }

  void _attach(_ImageZoomControllerDelegate delegate) {
    if (_delegate != null && !identical(_delegate, delegate)) {
      throw StateError(
        "An ImageZoomController cannot be attached to multiple viewers.",
      );
    }
    _delegate = delegate;
  }

  void _detach(_ImageZoomControllerDelegate delegate) {
    if (identical(_delegate, delegate)) {
      _delegate = null;
    }
  }

  void _update(ImageZoomTransform transform, ImageZoomStage stage) {
    if (_transform == transform && _stage == stage) return;
    _transform = transform;
    _stage = stage;
    notifyListeners();
  }
}

class ImageZoomViewer extends StatefulWidget {
  final ImageProvider imageProvider;
  final ImageZoomController? controller;
  final Size? imageSizeHint;
  final Object? heroTag;
  final Decoration? backgroundDecoration;
  final BoxFit initialFit;
  final double maxScaleOverCover;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final bool gesturesEnabled;
  final ImageZoomLoadingBuilder? loadingBuilder;
  final ImageErrorWidgetBuilder? errorBuilder;
  final String? semanticLabel;
  final ValueChanged<bool>? onInteractionLockChanged;
  final Duration animationDuration;

  const ImageZoomViewer({
    super.key,
    required this.imageProvider,
    this.controller,
    this.imageSizeHint,
    this.heroTag,
    this.backgroundDecoration,
    this.initialFit = BoxFit.contain,
    this.maxScaleOverCover = double.infinity,
    this.filterQuality = FilterQuality.high,
    this.gaplessPlayback = true,
    this.gesturesEnabled = true,
    this.loadingBuilder,
    this.errorBuilder,
    this.semanticLabel,
    this.onInteractionLockChanged,
    this.animationDuration = const Duration(milliseconds: 220),
  }) : assert(initialFit == BoxFit.contain || initialFit == BoxFit.cover),
       assert(maxScaleOverCover > 0);

  @override
  State<ImageZoomViewer> createState() => _ImageZoomViewerState();
}

class _ImageZoomViewerState extends State<ImageZoomViewer>
    with SingleTickerProviderStateMixin
    implements _ImageZoomControllerDelegate {
  late ImageZoomController _controller;
  late bool _ownsController;
  late final _BoundedTransformationController _transformationController;
  late final AnimationController _animationController;

  Animation<Matrix4>? _matrixAnimation;
  Completer<void>? _animationCompleter;
  ImageZoomStage _stage = ImageZoomStage.initial;

  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  Size? _resolvedImageSize;
  ImageChunkEvent? _loadingProgress;
  Object? _imageError;
  StackTrace? _imageErrorStack;
  bool _hasImageFrame = false;

  ImageZoomGeometry? _geometry;

  // This raw pointer state lets a second finger lock parent navigation before
  // either Flutter scale recognizer has accepted the gesture.
  final Map<int, Offset> _pointerPositions = <int, Offset>{};
  List<int> _manualPinchPointers = const <int>[];
  Matrix4? _manualPinchStartMatrix;
  Offset? _manualPinchScenePoint;
  double _manualPinchStartDistance = 0;
  bool _manualPinchActive = false;
  bool _programmaticAnimationActive = false;
  bool _interactionLocked = false;
  bool _interactiveViewerOwnsGestures = false;
  bool _interactiveGestureActive = false;
  int _interactiveViewerGeneration = 0;
  Offset? _doubleTapPosition;
  int _geometryGeneration = 0;

  bool get _hasGeometry => _geometry != null;

  @override
  void initState() {
    super.initState();
    _resolvedImageSize = _validSize(widget.imageSizeHint);
    _attachController(widget.controller);
    _transformationController = _BoundedTransformationController()
      ..addListener(_onTransformationChanged);
    _animationController =
        AnimationController(vsync: this, duration: widget.animationDuration)
          ..addListener(_onAnimationTick)
          ..addStatusListener(_onAnimationStatusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ImageZoomViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController();
      _attachController(widget.controller);
      _publishTransform();
    }
    if (oldWidget.imageProvider != widget.imageProvider) {
      final hint = _validSize(widget.imageSizeHint);
      if (!_hasImageFrame && hint != null) {
        _resolvedImageSize = hint;
      }
      _resolveImage();
      if (_stage != ImageZoomStage.initial) {
        _stage = ImageZoomStage.gesture;
      }
    } else if (oldWidget.imageSizeHint != widget.imageSizeHint &&
        !_hasImageFrame) {
      _resolvedImageSize = _validSize(widget.imageSizeHint);
    }
    if (oldWidget.animationDuration != widget.animationDuration) {
      _animationController.duration = widget.animationDuration;
    }
    if (oldWidget.gesturesEnabled && !widget.gesturesEnabled) {
      _pointerPositions.clear();
      _manualPinchActive = false;
      _updateInteractionLock();
    }
  }

  void _attachController(ImageZoomController? controller) {
    _ownsController = controller == null;
    _controller = controller ?? ImageZoomController();
    _controller._attach(this);
  }

  void _detachController() {
    _controller._detach(this);
    if (_ownsController) {
      _controller.dispose();
    }
  }

  @override
  void dispose() {
    _detachImageStreamListener();
    _animationController
      ..removeListener(_onAnimationTick)
      ..removeStatusListener(_onAnimationStatusChanged)
      ..dispose();
    _animationCompleter?.complete();
    _transformationController
      ..removeListener(_onTransformationChanged)
      ..dispose();
    _detachController();
    super.dispose();
  }

  void _resolveImage() {
    // The visible Image owns painting; this listener only resolves decoded
    // dimensions and loading/error state for transform geometry.
    final newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_imageStream?.key == newStream.key) return;
    _detachImageStreamListener();
    _imageStream = newStream;
    _imageStreamListener = ImageStreamListener(
      _handleImageFrame,
      onChunk: _handleImageChunk,
      onError: _handleImageError,
    );
    newStream.addListener(_imageStreamListener!);
  }

  void _detachImageStreamListener() {
    final listener = _imageStreamListener;
    if (_imageStream != null && listener != null) {
      _imageStream!.removeListener(listener);
    }
    _imageStreamListener = null;
  }

  void _handleImageFrame(ImageInfo imageInfo, bool synchronousCall) {
    final imageSize = Size(
      imageInfo.image.width.toDouble(),
      imageInfo.image.height.toDouble(),
    );
    final shouldUpdate =
        !_hasImageFrame ||
        _resolvedImageSize != imageSize ||
        _loadingProgress != null ||
        _imageError != null;
    if (!shouldUpdate) {
      imageInfo.dispose();
      return;
    }
    void update() {
      _resolvedImageSize = imageSize;
      _hasImageFrame = true;
      _loadingProgress = null;
      _imageError = null;
      _imageErrorStack = null;
    }

    if (synchronousCall) {
      update();
    } else if (mounted) {
      setState(update);
    }
    imageInfo.dispose();
  }

  void _handleImageChunk(ImageChunkEvent progress) {
    if (!mounted || _hasImageFrame) return;
    setState(() {
      _loadingProgress = progress;
      _imageError = null;
      _imageErrorStack = null;
    });
  }

  void _handleImageError(Object error, StackTrace? stackTrace) {
    if (!mounted || _hasImageFrame) return;
    setState(() {
      _imageError = error;
      _imageErrorStack = stackTrace;
      _loadingProgress = null;
    });
  }

  Size? _validSize(Size? size) =>
      size != null && size.isFinite && !size.isEmpty ? size : null;

  void _updateGeometry(Size viewportSize, Size imageSize) {
    final nextGeometry = ImageZoomGeometry.calculate(
      viewportSize: viewportSize,
      imageSize: imageSize,
      initialFit: widget.initialFit,
      maxScaleOverCover: widget.maxScaleOverCover,
    );
    if (nextGeometry == null) return;

    final previousGeometry = _geometry;
    final previousMatrix = _transformationController.value.clone();
    if (previousGeometry?.hasSameConfiguration(nextGeometry) ?? false) return;

    if (previousGeometry != null &&
        !nextGeometry.coordinatesMatch(previousGeometry) &&
        _programmaticAnimationActive) {
      _stopProgrammaticAnimationForGeometryChange();
    }

    _geometry = nextGeometry;
    _transformationController.configure(nextGeometry);

    if (previousGeometry == null) {
      _transformationController.setOwnerValue(
        nextGeometry.matrixForScaleAndOffset(
          nextGeometry.initialScale,
          Offset.zero,
        ),
      );
      _stage = ImageZoomStage.initial;
      _publishTransform();
      return;
    }

    final generation = ++_geometryGeneration;
    final rebase = ImageZoomRebase.capture(previousGeometry, previousMatrix);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _geometryGeneration) return;
      _transformationController.setOwnerValue(rebase.resolve(_geometry!));
      _stage = rebase.wasInitial
          ? ImageZoomStage.initial
          : ImageZoomStage.gesture;
      _publishTransform();
    });
  }

  void _onTransformationChanged() {
    if (!_hasGeometry) return;
    _publishTransform();
    _syncInteractiveViewerOwnership();
  }

  void _syncInteractiveViewerOwnership() {
    final shouldEnable =
        widget.gesturesEnabled &&
        !_manualPinchActive &&
        (_interactiveGestureActive ||
            !_geometry!.describe(_transformationController.value).isInitial);
    if (_interactiveViewerOwnsGestures != shouldEnable && mounted) {
      setState(() => _interactiveViewerOwnsGestures = shouldEnable);
    }
  }

  void _publishTransform() {
    if (!_hasGeometry) return;
    final matrixState = _geometry!.describe(_transformationController.value);
    if (matrixState.isInitial) {
      _stage = ImageZoomStage.initial;
    }
    _controller._update(
      matrixState.isInitial
          ? ImageZoomTransform.identity
          : ImageZoomTransform(
              scale: matrixState.relativeScale,
              offset: matrixState.semanticOffset,
            ),
      _stage,
    );
    _updateInteractionLock();
  }

  void _updateInteractionLock() {
    final shouldLock =
        widget.gesturesEnabled &&
        (_pointerPositions.length >= 2 ||
            _manualPinchActive ||
            _programmaticAnimationActive ||
            _controller.isZoomed);
    if (shouldLock == _interactionLocked) return;
    _interactionLocked = shouldLock;
    widget.onInteractionLockChanged?.call(shouldLock);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!widget.gesturesEnabled) return;
    _pointerPositions[event.pointer] = event.localPosition;
    if (_animationController.isAnimating) {
      _stopProgrammaticAnimation();
    }
    if (_manualPinchActive &&
        _pointerPositions.length >= 2 &&
        !_manualPinchPointers.every(_pointerPositions.containsKey)) {
      _beginManualPinch();
    } else if (_pointerPositions.length >= 2 &&
        !_manualPinchActive &&
        _geometry!.describe(_transformationController.value).isInitial) {
      _beginManualPinch();
    }
    _updateInteractionLock();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!widget.gesturesEnabled ||
        !_pointerPositions.containsKey(event.pointer)) {
      return;
    }
    _pointerPositions[event.pointer] = event.localPosition;
    if (_manualPinchActive) {
      _updateManualPinch();
    }
  }

  void _onPointerUp(PointerEvent event) {
    if (!widget.gesturesEnabled) return;
    _pointerPositions.remove(event.pointer);
    if (_manualPinchActive &&
        !_manualPinchPointers.every(_pointerPositions.containsKey)) {
      if (_pointerPositions.length >= 2) {
        _beginManualPinch();
      } else if (_pointerPositions.isEmpty) {
        _endManualPinch();
      }
    }
    _updateInteractionLock();
  }

  void _beginManualPinch() {
    if (_pointerPositions.length < 2) return;
    _transformationController.allowInteractiveWrites();
    _manualPinchActive = true;
    _manualPinchPointers = _pointerPositions.keys
        .take(2)
        .toList(growable: false);
    final first = _pointerPositions[_manualPinchPointers[0]]!;
    final second = _pointerPositions[_manualPinchPointers[1]]!;
    final focalPoint = (first + second) / 2;
    _manualPinchStartDistance = (first - second).distance;
    _manualPinchStartMatrix = _transformationController.value.clone();
    _manualPinchScenePoint = _geometry!.scenePoint(
      _manualPinchStartMatrix!,
      focalPoint,
    );
    if (mounted) setState(() {});
  }

  void _updateManualPinch() {
    if (!_hasGeometry ||
        _manualPinchStartDistance <= 0 ||
        _manualPinchStartMatrix == null ||
        _manualPinchScenePoint == null ||
        !_manualPinchPointers.every(_pointerPositions.containsKey)) {
      return;
    }
    final first = _pointerPositions[_manualPinchPointers[0]]!;
    final second = _pointerPositions[_manualPinchPointers[1]]!;
    final distance = (first - second).distance;
    final focalPoint = (first + second) / 2;
    final startScale = _manualPinchStartMatrix!.getMaxScaleOnAxis();
    final targetScale = _geometry!.clampScale(
      startScale * distance / _manualPinchStartDistance,
    );
    final translation = focalPoint - _manualPinchScenePoint! * targetScale;
    _stage = ImageZoomStage.gesture;
    _transformationController.setOwnerValue(
      _geometry!.matrixForScaleAndTranslation(targetScale, translation),
    );
  }

  void _endManualPinch() {
    _manualPinchActive = false;
    _manualPinchPointers = const <int>[];
    _manualPinchStartMatrix = null;
    _manualPinchScenePoint = null;
    if (_geometry!.describe(_transformationController.value).isInitial) {
      _stage = ImageZoomStage.initial;
      _transformationController.setOwnerValue(
        _geometry!.matrixForScaleAndOffset(
          _geometry!.initialScale,
          Offset.zero,
        ),
      );
    }
    _publishTransform();
    _syncInteractiveViewerOwnership();
  }

  void _onInteractionStart(ScaleStartDetails _) {
    _transformationController.allowInteractiveWrites();
    _interactiveGestureActive = true;
    if (_animationController.isAnimating) {
      _stopProgrammaticAnimation();
    }
  }

  void _onInteractionUpdate(ScaleUpdateDetails details) {
    if (_pointerPositions.length >= 2 &&
        (details.scale - 1.0).abs() > _kZoomEpsilon) {
      _stage = ImageZoomStage.gesture;
      _publishTransform();
    }
  }

  void _onInteractionEnd(ScaleEndDetails _) {
    _interactiveGestureActive = false;
    _syncInteractiveViewerOwnership();
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTapCancel() {
    _doubleTapPosition = null;
  }

  void _onDoubleTap() {
    final tapPosition = _doubleTapPosition;
    _doubleTapPosition = null;
    if (!_hasGeometry || tapPosition == null) return;

    final geometry = _geometry!;
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final stagePolicy = ImageZoomStagePolicy(
      initialScale: geometry.initialScale,
      coverScale: geometry.coverScale,
      originalScale: geometry.originalScale,
      maxScale: geometry.maxScale,
    );
    final nextStage = stagePolicy.nextDoubleTapStage(
      currentStage: _stage,
      currentScale: currentScale,
    );
    if (nextStage == null) return;
    final targetScale = stagePolicy.targetScale(nextStage);
    final target = nextStage == ImageZoomStage.initial
        ? geometry.matrixForScaleAndOffset(geometry.initialScale, Offset.zero)
        : geometry.matrixForFocalPoint(
            _transformationController.value,
            tapPosition,
            targetScale,
          );
    unawaited(_animateTo(target, nextStage));
  }

  @override
  Future<void> reset({required bool animated}) {
    if (!_hasGeometry) {
      _stage = ImageZoomStage.initial;
      _controller._update(ImageZoomTransform.identity, _stage);
      return Future<void>.value();
    }
    final geometry = _geometry!;
    final target = geometry.matrixForScaleAndOffset(
      geometry.initialScale,
      Offset.zero,
    );
    if (animated &&
        _matricesNearlyEqual(_transformationController.value, target)) {
      return Future<void>.value();
    }
    if (!animated) {
      _stopProgrammaticAnimation();
      _stage = ImageZoomStage.initial;
      _transformationController
        ..suppressInteractiveWrites()
        ..setOwnerValue(target);
      _publishTransform();
      return Future<void>.value();
    }
    return _animateTo(target, ImageZoomStage.initial);
  }

  Future<void> _animateTo(Matrix4 target, ImageZoomStage targetStage) {
    _animationController.stop();
    _animationCompleter?.complete();
    final completer = Completer<void>();
    _animationCompleter = completer;
    _stage = targetStage;
    _programmaticAnimationActive = true;
    _transformationController.suppressInteractiveWrites();
    _matrixAnimation =
        Matrix4Tween(
          begin: _transformationController.value.clone(),
          end: _transformationController.sanitize(target),
        ).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
    // InteractiveViewer owns its inertia simulation internally. Re-key it so
    // stale inertia cannot resume after an owner animation or reset.
    _interactiveViewerGeneration++;
    _updateInteractionLock();
    if (mounted) setState(() {});
    _animationController.forward(from: 0);
    return completer.future;
  }

  void _onAnimationTick() {
    final value = _matrixAnimation?.value;
    if (value != null) {
      _transformationController.setOwnerValue(value);
    }
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _programmaticAnimationActive = false;
    _matrixAnimation = null;
    _publishTransform();
    _animationCompleter?.complete();
    _animationCompleter = null;
  }

  void _stopProgrammaticAnimation() {
    if (!_animationController.isAnimating && !_programmaticAnimationActive) {
      return;
    }
    _animationController.stop();
    _programmaticAnimationActive = false;
    _matrixAnimation = null;
    _animationCompleter?.complete();
    _animationCompleter = null;
    _updateInteractionLock();
  }

  // Geometry is updated from LayoutBuilder. Avoid invoking the interaction
  // callback there; the post-frame geometry rebase publishes the new lock.
  void _stopProgrammaticAnimationForGeometryChange() {
    _animationController.stop();
    _programmaticAnimationActive = false;
    _matrixAnimation = null;
    _animationCompleter?.complete();
    _animationCompleter = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_imageError != null && !_hasImageFrame) {
      return widget.errorBuilder?.call(
            context,
            _imageError!,
            _imageErrorStack,
          ) ??
          const Center(child: Icon(Icons.broken_image_outlined));
    }
    if (!_hasImageFrame || _resolvedImageSize == null) {
      return widget.loadingBuilder?.call(context, _loadingProgress) ??
          const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = constraints.biggest;
        if (viewportSize.isEmpty || !viewportSize.isFinite) {
          return const SizedBox.shrink();
        }
        _updateGeometry(viewportSize, _resolvedImageSize!);
        final geometry = _geometry;
        if (geometry == null) return const SizedBox.shrink();
        final fittedSize = geometry.fittedImageSize;

        Widget image = Image(
          image: widget.imageProvider,
          width: fittedSize.width,
          height: fittedSize.height,
          fit: BoxFit.fill,
          gaplessPlayback: widget.gaplessPlayback,
          filterQuality: widget.filterQuality,
          semanticLabel: widget.semanticLabel,
          errorBuilder: widget.errorBuilder,
        );
        if (widget.heroTag != null) {
          image = Hero(tag: widget.heroTag!, child: image);
        }

        final transformedChild = SizedBox.expand(child: Center(child: image));
        final interactiveViewer = InteractiveViewer(
          key: ValueKey(_interactiveViewerGeneration),
          transformationController: _transformationController,
          alignment: null,
          minScale: geometry.initialScale,
          maxScale: geometry.maxScale,
          onInteractionStart: _onInteractionStart,
          onInteractionUpdate: _onInteractionUpdate,
          onInteractionEnd: _onInteractionEnd,
          child: transformedChild,
        );

        final content = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTapDown: widget.gesturesEnabled ? _onDoubleTapDown : null,
          onDoubleTap: widget.gesturesEnabled ? _onDoubleTap : null,
          onDoubleTapCancel: widget.gesturesEnabled ? _onDoubleTapCancel : null,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: widget.gesturesEnabled ? _onPointerDown : null,
            onPointerMove: widget.gesturesEnabled ? _onPointerMove : null,
            onPointerUp: widget.gesturesEnabled ? _onPointerUp : null,
            onPointerCancel: widget.gesturesEnabled ? _onPointerUp : null,
            child: IgnorePointer(
              ignoring:
                  !widget.gesturesEnabled ||
                  _manualPinchActive ||
                  !_interactiveViewerOwnsGestures,
              child: interactiveViewer,
            ),
          ),
        );

        return DecoratedBox(
          decoration:
              widget.backgroundDecoration ??
              const BoxDecoration(color: Colors.black),
          child: content,
        );
      },
    );
  }
}

class _BoundedTransformationController extends TransformationController {
  ImageZoomGeometry? _geometry;
  bool _ownerWrite = false;
  bool _suppressInteractiveWrites = false;

  void configure(ImageZoomGeometry geometry) => _geometry = geometry;

  void suppressInteractiveWrites() {
    _suppressInteractiveWrites = true;
  }

  void allowInteractiveWrites() {
    _suppressInteractiveWrites = false;
  }

  void setOwnerValue(Matrix4 matrix) {
    _ownerWrite = true;
    value = matrix;
    _ownerWrite = false;
  }

  @override
  set value(Matrix4 newValue) {
    if (_suppressInteractiveWrites && !_ownerWrite) return;
    final sanitized = sanitize(newValue);
    // Edge inertia can keep proposing movement after clamping has rejected it.
    // Avoid notifying/repainting when the effective bounded matrix is unchanged.
    if (!_ownerWrite && _matricesNearlyEqual(value, sanitized)) return;
    super.value = sanitized;
  }

  Matrix4 sanitize(Matrix4 matrix) =>
      _geometry?.sanitize(matrix) ?? matrix.clone();
}

bool _matricesNearlyEqual(Matrix4 first, Matrix4 second) {
  if (MatrixUtils.matrixEquals(first, second)) return true;
  for (var index = 0; index < 16; index++) {
    if ((first.storage[index] - second.storage[index]).abs() > 0.0000001) {
      return false;
    }
  }
  return true;
}
