import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/scanner/auto_capture_controller.dart';
import 'package:locker/services/scanner/scan_geometry.dart';
import 'package:locker/services/scanner/scan_session_controller.dart';
import 'package:locker/services/scanner/scanner_models.dart';
import 'package:locker/ui/pages/scanner/capture_flight.dart';
import 'package:locker/ui/pages/scanner/scan_quad_overlay.dart';
import 'package:locker/ui/pages/scanner/scanner_capture_widgets.dart';
import 'package:locker/ui/pages/scanner/scanner_review_page.dart';
import 'package:logging/logging.dart';

enum _CameraStatus { starting, ready, permissionDenied, error }

class ScannerCapturePage extends StatefulWidget {
  const ScannerCapturePage({super.key, required this.onUploadFiles});

  final Future<bool> Function(List<File> files) onUploadFiles;

  @override
  State<ScannerCapturePage> createState() => _ScannerCapturePageState();
}

class _ScannerCapturePageState extends State<ScannerCapturePage>
    with WidgetsBindingObserver {
  final _logger = Logger('ScannerCapturePage');
  final _session = ScanSessionController();
  final _stabilizer = QuadStabilizer();
  final _autoCapture = AutoCaptureController();

  CameraController? _camera;
  _CameraStatus _status = _CameraStatus.starting;
  ScanQuad? _stableQuad;
  bool _analysisInFlight = false;
  bool _takingPicture = false;
  bool _torchOn = false;
  bool _autoMode = true;
  bool _scannerInitFailed = false;
  bool _reviewActive = false;

  final _previewKey = GlobalKey();
  final _flightLayerKey = GlobalKey();
  final _pagesButtonKey = GlobalKey();
  final List<_PendingCapture> _pending = [];
  final List<_ActiveFlight> _flights = [];
  int _captureSeq = 0;
  ScanQuad? _snapQuad;
  int _snapId = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSessionChanged);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    if (!mounted) return;
    unawaited(_initScanner());
    unawaited(_startCamera());
  }

  Future<void> _initScanner() async {
    if (_scannerInitFailed) setState(() => _scannerInitFailed = false);
    try {
      await _session.init();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _scannerInitFailed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    unawaited(_camera?.dispose());
    unawaited(_session.disposeSession());
    for (final capture in _pending) {
      capture.spec?.image.dispose();
    }
    unawaited(
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (state == AppLifecycleState.inactive) {
      if (camera != null) {
        setState(() => _camera = null);
        unawaited(camera.dispose());
      }
      _autoCapture.reset();
    } else if (state == AppLifecycleState.resumed) {
      if (!_reviewActive &&
          _camera == null &&
          _status != _CameraStatus.starting) {
        unawaited(_startCamera());
      }
    }
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final error = _session.takeLastError();
    if (error != null) {
      showShortToast(context, context.strings.somethingWentWrong);
    }
    _reconcilePending(failed: error != null);
    setState(() {});
  }

  Future<void> _startCamera() async {
    setState(() {
      _status = _CameraStatus.starting;
      _stableQuad = null;
    });
    _stabilizer.reset();
    _autoCapture.reset();
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() => _status = _CameraStatus.error);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();
      var retainedController = false;
      try {
        if (!mounted) return;
        await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        if (!mounted) return;
        await controller.startImageStream(_onFrame);
        if (!mounted) return;
        if (_torchOn) await _applyTorch(controller, true);
        if (!mounted) return;
        setState(() {
          _camera = controller;
          _status = _CameraStatus.ready;
        });
        retainedController = true;
      } finally {
        if (!retainedController) {
          await controller.dispose();
        }
      }
    } on CameraException catch (e) {
      _logger.warning('Camera unavailable: ${e.code}', e);
      if (!mounted) return;
      setState(() {
        _status = e.code.startsWith('CameraAccessDenied')
            ? _CameraStatus.permissionDenied
            : _CameraStatus.error;
      });
    } catch (e, s) {
      _logger.severe('Failed to start camera', e, s);
      if (mounted) setState(() => _status = _CameraStatus.error);
    }
  }

  Future<void> _pauseCamera() async {
    final camera = _camera;
    if (camera == null) return;
    setState(() {
      _camera = null;
      _stableQuad = null;
    });
    _stabilizer.reset();
    _autoCapture.reset();
    await camera.dispose();
  }

  void _onFrame(CameraImage image) {
    if (_reviewActive ||
        _analysisInFlight ||
        _takingPicture ||
        !_session.isServiceReady) {
      return;
    }
    _analysisInFlight = true;
    unawaited(_analyze(image));
  }

  Future<void> _analyze(CameraImage image) async {
    try {
      final rotation = Platform.isIOS
          ? 0
          : _camera?.description.sensorOrientation ?? 0;
      ScanQuad? raw;
      if (image.planes.length >= 3) {
        raw = await _session.detectLiveYuv(
          y: image.planes[0].bytes,
          u: image.planes[1].bytes,
          v: image.planes[2].bytes,
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
          width: image.width,
          height: image.height,
          rotationDegrees: rotation,
        );
      } else if (image.planes.isNotEmpty) {
        raw = await _session.detectLiveBgra(
          image.planes[0].bytes,
          image.planes[0].bytesPerRow,
          image.width,
          image.height,
          rotation,
        );
      }
      final stable = _stabilizer.update(raw);
      var fire = false;
      if (_autoMode) {
        fire = _autoCapture.onFrame(
          stable,
          captureBusy: _takingPicture || _session.isProcessing,
        );
      }
      if (mounted) {
        setState(() => _stableQuad = stable);
        if (fire) unawaited(_capture());
      }
    } catch (_) {
    } finally {
      _analysisInFlight = false;
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _takingPicture || _reviewActive) return;
    final quad = _stableQuad ?? ScanQuad.fullFrame();
    _autoCapture.notifyCaptureStarted();
    unawaited(HapticFeedback.mediumImpact());
    setState(() {
      _takingPicture = true;
      _stableQuad = null;
      _snapQuad = quad;
      _snapId++;
    });
    _stabilizer.reset();
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      unawaited(_deleteQuietly(File(shot.path)));
      _onShotTaken(bytes, quad);
    } catch (e, s) {
      _logger.severe('Capture failed', e, s);
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
      }
    } finally {
      if (mounted) setState(() => _takingPicture = false);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  void _onShotTaken(Uint8List bytes, ScanQuad quad) {
    final capture = _PendingCapture(_captureSeq++);
    _pending.add(capture);
    _session.addCapture(bytes);
    unawaited(_launchFlight(capture, bytes, quad));
  }

  Future<void> _launchFlight(
    _PendingCapture capture,
    Uint8List bytes,
    ScanQuad quad,
  ) async {
    final spec = await _buildFlightSpec(bytes, quad);
    if (!mounted || capture.landed) {
      spec?.image.dispose();
      return;
    }
    if (spec == null) {
      setState(() {
        capture.landed = true;
        _purgeResolved();
      });
      return;
    }
    capture.spec = spec;
    setState(() => _flights.add(_ActiveFlight(capture: capture, spec: spec)));
  }

  Future<CaptureFlightSpec?> _buildFlightSpec(
    Uint8List bytes,
    ScanQuad quad,
  ) async {
    final layer = _renderBox(_flightLayerKey);
    final preview = _renderBox(_previewKey);
    final thumb = _renderBox(_pagesButtonKey);
    if (layer == null || preview == null || thumb == null) return null;
    final previewRect =
        preview.localToGlobal(Offset.zero, ancestor: layer) & preview.size;
    final thumbRect =
        thumb.localToGlobal(Offset.zero, ancestor: layer) & thumb.size;
    final targetWidth =
        (previewRect.width * MediaQuery.devicePixelRatioOf(context)).round();
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      image = frame.image;
    } catch (e, s) {
      _logger.warning('Failed to decode capture preview', e, s);
      return null;
    }
    return CaptureFlightSpec(
      image: image,
      sourceCorners: [
        for (final corner in quad.corners)
          previewRect.topLeft +
              Offset(
                corner.dx * previewRect.width,
                corner.dy * previewRect.height,
              ),
      ],
      imageToLayer: coverImageTransform(
        Size(image.width.toDouble(), image.height.toDouble()),
        previewRect,
      ),
      target: thumbRect,
      targetRadius: Radii.md,
      targetBorder: ScannerPagesButton.borderWidth,
    );
  }

  static RenderBox? _renderBox(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box : null;
  }

  void _onFlightLanded(_ActiveFlight flight) {
    if (!mounted) return;
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _flights.remove(flight);
      flight.capture.landed = true;
      _purgeResolved();
    });
  }

  void _reconcilePending({required bool failed}) {
    var markFailed = failed;
    var unresolved = _pending.where((capture) => !capture.resolved).length;
    while (unresolved > _session.pendingCount) {
      final oldest = _pending.firstWhere((capture) => !capture.resolved);
      if (markFailed) {
        oldest.failed = true;
        oldest.landed = true;
        _flights.removeWhere((flight) => flight.capture == oldest);
        markFailed = false;
      } else {
        oldest.processed = true;
      }
      unresolved--;
    }
    _purgeResolved();
  }

  void _purgeResolved() {
    _PendingCapture? newestLanded;
    for (final capture in _pending) {
      if (capture.landed) newestLanded = capture;
    }
    for (final capture in _pending) {
      if (capture.landed && (capture.failed || capture != newestLanded)) {
        _releaseSnapshot(capture);
      }
    }
    _pending.removeWhere(
      (capture) => capture.landed && capture.resolved && capture.spec == null,
    );
  }

  static void _releaseSnapshot(_PendingCapture capture) {
    final image = capture.spec?.image;
    capture.spec = null;
    if (image != null) {
      unawaited(Future<void>.delayed(Motion.slow * 2, image.dispose));
    }
  }

  ({int count, Widget? thumbnail, File? heroFile}) _pagesButtonState() {
    final hiddenPages = _pending
        .where((capture) => capture.processed && !capture.landed)
        .length;
    final shownPages = math.max(0, _session.pageCount - hiddenPages);
    final landedUnprocessed = _pending
        .where((capture) => capture.landed && !capture.resolved)
        .length;
    final showingSnapshot = [
      for (final capture in _pending)
        if (capture.landed && !capture.failed && capture.spec != null) capture,
    ];
    Widget? thumbnail;
    final heroFile = shownPages > 0
        ? _session.pages[shownPages - 1].processedJpeg
        : null;
    if (showingSnapshot.isNotEmpty) {
      final capture = showingSnapshot.last;
      thumbnail = CaptureSnapshotThumbnail(
        key: ValueKey('capture-${capture.id}'),
        spec: capture.spec!,
      );
    } else if (shownPages > 0) {
      final page = _session.pages[shownPages - 1];
      thumbnail = ScannerProcessedThumbnail(
        key: ValueKey(page.processedJpeg.path),
        page: page,
      );
    }
    return (
      count: shownPages + landedUnprocessed,
      thumbnail: thumbnail,
      heroFile: heroFile,
    );
  }

  void _toggleAutoMode() {
    setState(() => _autoMode = !_autoMode);
    _autoCapture.reset();
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    await _applyTorch(camera, !_torchOn);
    if (mounted) setState(() {});
  }

  Future<void> _applyTorch(CameraController camera, bool on) async {
    try {
      await camera.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      _torchOn = on;
    } on CameraException catch (e) {
      _logger.warning('Torch unavailable: ${e.code}');
      _torchOn = false;
    }
  }

  Future<void> _openReview() async {
    if (_reviewActive || (_session.pageCount == 0 && !_session.isProcessing)) {
      return;
    }
    final navigator = Navigator.of(context);
    _reviewActive = true;
    bool? saved;
    try {
      if (_session.pageCount > 0) {
        await precacheImage(
          FileImage(_session.pages.last.processedJpeg),
          context,
        );
        if (!mounted) return;
      }
      await _pauseCamera();
      if (!mounted) return;
      saved = await navigator.push<bool>(
        MaterialPageRoute(
          builder: (_) => ScannerReviewPage(
            session: _session,
            onUploadFiles: widget.onUploadFiles,
          ),
        ),
      );
    } finally {
      _reviewActive = false;
    }
    if (!mounted) return;
    if (saved == true) {
      navigator.pop(true);
    } else {
      setState(() {
        for (final capture in _pending) {
          capture.landed = true;
          _releaseSnapshot(capture);
        }
        _flights.clear();
        _purgeResolved();
      });
      unawaited(_startCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final pages = _pagesButtonState();
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildPreview(colors),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Spacing.lg),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ScannerChromeButton(
                        icon: HugeIcons.strokeRoundedCancel01,
                        onTap: () => Navigator.of(context).pop(false),
                        tooltip: context.strings.close,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ScannerChromeButton(
                            icon: _torchOn
                                ? HugeIcons.strokeRoundedFlash
                                : HugeIcons.strokeRoundedFlashOff,
                            onTap: _camera == null ? null : _toggleTorch,
                            tooltip: _torchOn
                                ? context.strings.scannerTorchOff
                                : context.strings.scannerTorchOn,
                          ),
                          const SizedBox(width: Spacing.sm),
                          ScannerModeToggle(
                            active: _autoMode,
                            onTap: _toggleAutoMode,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  ScannerPreparingHint(
                    visible: !_session.isServiceReady && !_scannerInitFailed,
                  ),
                  SizedBox(
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ScannerShutterButton(
                          enabled:
                              _status == _CameraStatus.ready &&
                              !_takingPicture &&
                              _session.isServiceReady,
                          onTap: _capture,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ScannerPagesButton(
                            key: _pagesButtonKey,
                            count: pages.count,
                            thumbnail: pages.thumbnail,
                            heroFile: pages.heroFile,
                            accent: colors.primary,
                            onTap: _openReview,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ScannerDoneButton(
                            visible: pages.count > 0,
                            accent: colors.primary,
                            onTap: _openReview,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IgnorePointer(
            child: Stack(
              key: _flightLayerKey,
              fit: StackFit.expand,
              children: [
                for (final flight in _flights)
                  CaptureFlightCard(
                    key: ValueKey(flight.capture.id),
                    spec: flight.spec,
                    borderColor: colors.specialWhite,
                    onLanded: () => _onFlightLanded(flight),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorTokens colors) {
    if (_scannerInitFailed) {
      return ScannerCameraMessage(
        message: context.strings.somethingWentWrong,
        onRetry: _initScanner,
      );
    }
    switch (_status) {
      case _CameraStatus.starting:
        return Center(
          child: CircularProgressIndicator(color: colors.specialWhite),
        );
      case _CameraStatus.permissionDenied:
        return ScannerCameraMessage(
          message: context.strings.cameraPermissionSettings,
          onRetry: _startCamera,
        );
      case _CameraStatus.error:
        return ScannerCameraMessage(
          message: context.strings.somethingWentWrong,
          onRetry: _startCamera,
        );
      case _CameraStatus.ready:
        final camera = _camera;
        if (camera == null || !camera.value.isInitialized) {
          return Center(
            child: CircularProgressIndicator(color: colors.specialWhite),
          );
        }
        return Center(
          child: AspectRatio(
            aspectRatio: 1 / camera.value.aspectRatio,
            child: ClipRRect(
              key: _previewKey,
              borderRadius: BorderRadius.circular(Radii.sheet),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CameraPreview(camera),
                  ScanQuadOverlay(
                    quad: _takingPicture || _flights.isNotEmpty
                        ? null
                        : _stableQuad,
                    color: colors.primary,
                    armingProgress: _autoMode ? _autoCapture.progress : 0,
                  ),
                  CaptureSnapOverlay(
                    quad: _snapQuad,
                    snapId: _snapId,
                    color: colors.primary,
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

class _PendingCapture {
  _PendingCapture(this.id);

  final int id;
  CaptureFlightSpec? spec;
  bool landed = false;
  bool processed = false;
  bool failed = false;

  bool get resolved => processed || failed;
}

class _ActiveFlight {
  const _ActiveFlight({required this.capture, required this.spec});

  final _PendingCapture capture;
  final CaptureFlightSpec spec;
}
