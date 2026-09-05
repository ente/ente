import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:ente_panorama_viewer/src/camera.dart";
import "package:ente_panorama_viewer/src/models.dart";
import "package:ente_panorama_viewer/src/motion.dart";
import "package:flutter/material.dart";
import "package:flutter/physics.dart";
import "package:flutter/scheduler.dart";

typedef PanoramaErrorCallback =
    void Function(Object error, StackTrace stackTrace);

Future<ui.FragmentProgram>? _program;

Future<ui.FragmentProgram> _loadProgram() {
  return _program ??= ui.FragmentProgram.fromAsset(
    "packages/ente_panorama_viewer/shaders/equirectangular.frag",
  );
}

class EntePanoramaViewer extends StatefulWidget {
  const EntePanoramaViewer({
    super.key,
    required this.image,
    required this.geometry,
    this.initialView,
    this.motionEnabled = false,
    this.placeholder,
    this.onTap,
    this.onViewChanged,
    this.onError,
  });

  // Full or cropped equirectangular image.
  final ImageProvider image;

  final PanoramaGeometry geometry;

  // Used only on mount and when image changes.
  final PanoramaView? initialView;

  final bool motionEnabled;

  final Widget? placeholder;
  final VoidCallback? onTap;
  final ValueChanged<PanoramaView>? onViewChanged;
  final PanoramaErrorCallback? onError;

  @override
  State<EntePanoramaViewer> createState() => _EntePanoramaViewerState();
}

class _EntePanoramaViewerState extends State<EntePanoramaViewer>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final PanoramaCamera _camera;
  late final MotionController _motion;
  late final Ticker _inertiaTicker;

  ui.FragmentShader? _shader;
  ImageStream? _imageStream;
  ImageInfo? _imageInfo;
  late final ImageStreamListener _imageListener;

  PanoramaView _motionBase = const PanoramaView();
  Offset _lastFocalPoint = Offset.zero;
  double _lastGestureScale = 1;
  int _gesturePointerCount = 0;
  bool _gesturing = false;
  bool _gestureWasPinch = false;
  bool _lifecycleActive = false;
  bool _tickerModeActive = false;
  bool _dependenciesReady = false;

  FrictionSimulation? _longitudeInertia;
  FrictionSimulation? _latitudeInertia;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycleActive =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _camera = PanoramaCamera(
      geometry: widget.geometry,
      initialView: widget.initialView,
    )..addListener(_onCameraChanged);
    _motion = MotionController(
      _onMotionDelta,
      onReferenceChanged: _rebaseMotion,
      onError: _handleMotionError,
    );
    _inertiaTicker = createTicker(_onInertiaTick);
    _imageListener = ImageStreamListener(
      _handleImageFrame,
      onError: _handleImageError,
    );
    _loadShader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerModeActive = TickerMode.valuesOf(context).enabled;
    final motionStateChanged =
        !_dependenciesReady || tickerModeActive != _tickerModeActive;
    _dependenciesReady = true;
    _tickerModeActive = tickerModeActive;
    if (motionStateChanged) {
      _syncMotion();
    }
    _resolveImage();
  }

  @override
  void didUpdateWidget(EntePanoramaViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) {
      _camera.updateGeometry(widget.geometry, notify: false);
      _camera.reset(widget.initialView);
      _rebaseMotion();
      _motion.resetReference();
      _resolveImage();
    } else if (widget.geometry != oldWidget.geometry) {
      _camera.updateGeometry(widget.geometry);
      _rebaseMotion();
    }
    if (widget.motionEnabled != oldWidget.motionEnabled) {
      _syncMotion();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleActive = state == AppLifecycleState.resumed;
    _syncMotion();
  }

  Future<void> _loadShader() async {
    try {
      final program = await _loadProgram();
      if (!mounted) return;
      setState(() {
        _shader = program.fragmentShader();
      });
    } catch (error, stackTrace) {
      widget.onError?.call(error, stackTrace);
    }
  }

  void _resolveImage() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (_imageStream?.key == stream.key) return;
    _imageStream?.removeListener(_imageListener);
    if (_imageInfo != null) {
      setState(() {
        _replaceImage(null);
      });
    }
    _imageStream = stream..addListener(_imageListener);
  }

  void _handleImageFrame(ImageInfo imageInfo, bool _) {
    if (_imageInfo != null && imageInfo.isCloneOf(_imageInfo!)) {
      imageInfo.dispose();
      return;
    }
    setState(() {
      _replaceImage(imageInfo);
    });
  }

  void _replaceImage(ImageInfo? imageInfo) {
    final oldImage = _imageInfo;
    _imageInfo = imageInfo;
    if (oldImage != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        oldImage.dispose();
      });
    }
  }

  void _handleImageError(Object error, StackTrace? stackTrace) {
    widget.onError?.call(error, stackTrace ?? StackTrace.current);
  }

  void _handleMotionError(Object error, StackTrace stackTrace) {
    if (mounted) widget.onError?.call(error, stackTrace);
  }

  void _onCameraChanged() {
    widget.onViewChanged?.call(_camera.view);
  }

  void _syncMotion() {
    if (widget.motionEnabled &&
        _lifecycleActive &&
        _tickerModeActive &&
        _dependenciesReady) {
      _rebaseMotion();
      _motion.resetReference();
      _motion.start();
    } else {
      unawaited(_motion.stop());
    }
  }

  void _rebaseMotion() {
    _motionBase = _camera.view;
  }

  void _onMotionDelta(PanoramaView delta) {
    if (_gesturing ||
        _inertiaTicker.isActive ||
        !widget.motionEnabled ||
        !_lifecycleActive ||
        !_tickerModeActive) {
      return;
    }
    final requested = PanoramaView(
      longitude: _motionBase.longitude + delta.longitude,
      latitude: _motionBase.latitude + delta.latitude,
      zoom: _camera.view.zoom,
    );
    final constrained = _camera.wouldConstrain(requested);
    _camera.setView(requested);
    if (constrained) {
      _rebaseMotion();
      _motion.resetReference();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _stopInertia();
    _gesturing = true;
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = 1;
    _gesturePointerCount = details.pointerCount;
    _gestureWasPinch = details.pointerCount > 1;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    _gestureWasPinch |= details.pointerCount > 1;
    if (details.pointerCount != _gesturePointerCount) {
      _gesturePointerCount = details.pointerCount;
      _lastFocalPoint = details.localFocalPoint;
      _lastGestureScale = details.scale;
      return;
    }
    final anchor = _camera.sourcePointAt(_lastFocalPoint);
    final scaleDelta = details.scale / _lastGestureScale;
    _camera.setView(
      _camera.view.copyWith(zoom: _camera.view.zoom * scaleDelta),
    );
    _camera.anchorSourcePoint(details.localFocalPoint, anchor);
    _lastFocalPoint = details.localFocalPoint;
    _lastGestureScale = details.scale;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    _gesturing = false;
    _motionBase = _camera.view;
    _motion.resetReference();

    if (_gestureWasPinch) return;
    final size = _camera.viewport;
    if (size.isEmpty) return;
    final velocity = details.velocity.pixelsPerSecond;
    final longitudeVelocity =
        -velocity.dx / size.width * _camera.horizontalFieldOfView;
    final latitudeVelocity =
        velocity.dy / size.height * _camera.verticalFieldOfView;
    const drag = 0.08;
    _longitudeInertia = FrictionSimulation(
      drag,
      _camera.view.longitude,
      longitudeVelocity,
    );
    _latitudeInertia = FrictionSimulation(
      drag,
      _camera.view.latitude,
      latitudeVelocity,
    );
    _inertiaTicker.start();
  }

  void _onInertiaTick(Duration elapsed) {
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final longitude = _longitudeInertia;
    final latitude = _latitudeInertia;
    final requested = PanoramaView(
      longitude: longitude?.x(seconds) ?? _camera.view.longitude,
      latitude: latitude?.x(seconds) ?? _camera.view.latitude,
      zoom: _camera.view.zoom,
    );
    _camera.setView(requested);
    final actual = _camera.view;
    if (!_camera.geometry.coversFullWidth &&
        (actual.longitude - requested.longitude).abs() > 1e-9) {
      _longitudeInertia = null;
    } else if (longitude?.isDone(seconds) ?? false) {
      _longitudeInertia = null;
    }
    if ((actual.latitude - requested.latitude).abs() > 1e-9 ||
        (latitude?.isDone(seconds) ?? false)) {
      _latitudeInertia = null;
    }
    if (_longitudeInertia == null && _latitudeInertia == null) {
      _stopInertia(rebaseMotion: true);
    }
  }

  void _stopInertia({bool rebaseMotion = false}) {
    if (_inertiaTicker.isActive) _inertiaTicker.stop();
    _longitudeInertia = null;
    _latitudeInertia = null;
    if (rebaseMotion && widget.motionEnabled) {
      _motionBase = _camera.view;
      _motion.resetReference();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final viewportChanged = viewport != _camera.viewport;
        final viewChanged = _camera.updateViewport(viewport, notify: false);
        if (viewChanged && widget.onViewChanged != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onViewChanged?.call(_camera.view);
          });
        }
        if (viewportChanged && widget.motionEnabled) {
          _rebaseMotion();
          _motion.resetReference();
        }
        final shader = _shader;
        final image = _imageInfo;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onScaleStart: _onScaleStart,
          onScaleUpdate: _onScaleUpdate,
          onScaleEnd: _onScaleEnd,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if ((shader == null || image == null) &&
                  widget.placeholder != null)
                widget.placeholder!,
              if (image != null && !widget.geometry.coversFullSphere)
                RepaintBoundary(
                  child: CustomPaint(
                    isComplex: true,
                    painter: _BlurredBackgroundPainter(image.image),
                  ),
                ),
              if (shader != null && image != null)
                CustomPaint(
                  isComplex: true,
                  willChange: true,
                  painter: _PanoramaPainter(
                    camera: _camera,
                    geometry: widget.geometry,
                    shader: shader,
                    image: image.image,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_motion.stop());
    _camera
      ..removeListener(_onCameraChanged)
      ..dispose();
    _inertiaTicker.dispose();
    _imageStream?.removeListener(_imageListener);
    _imageInfo?.dispose();
    _shader?.dispose();
    super.dispose();
  }
}

class _BlurredBackgroundPainter extends CustomPainter {
  const _BlurredBackgroundPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final targetSize = size * 1.1;
    final fitted = applyBoxFit(BoxFit.cover, imageSize, targetSize);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
    final destination = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: fitted.destination.width,
      height: fitted.destination.height,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()
        ..filterQuality = FilterQuality.low
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: 32,
          sigmaY: 32,
          tileMode: TileMode.mirror,
        ),
    );
  }

  @override
  bool shouldRepaint(_BlurredBackgroundPainter oldDelegate) {
    return oldDelegate.image != image;
  }
}

class _PanoramaPainter extends CustomPainter {
  _PanoramaPainter({
    required this.camera,
    required this.geometry,
    required this.shader,
    required this.image,
  }) : super(repaint: camera);

  final PanoramaCamera camera;
  final PanoramaGeometry geometry;
  final ui.FragmentShader shader;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final view = camera.view;
    final crop = geometry.normalizedCrop;
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, math.tan(37.5 * math.pi / 180) / view.zoom)
      ..setFloat(3, view.longitude * math.pi / 180)
      ..setFloat(4, view.latitude * math.pi / 180)
      ..setFloat(5, crop.left)
      ..setFloat(6, crop.top)
      ..setFloat(7, crop.right)
      ..setFloat(8, crop.bottom)
      ..setFloat(9, geometry.coversFullWidth ? 1 : 0)
      ..setImageSampler(0, image);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PanoramaPainter oldDelegate) {
    return oldDelegate.geometry != geometry ||
        oldDelegate.shader != shader ||
        oldDelegate.image != image;
  }
}
