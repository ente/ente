import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

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
import 'package:locker/ui/pages/scanner/scan_quad_overlay.dart';
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
  bool _autoMode = false;
  bool _scannerInitFailed = false;

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
        _camera = null;
        unawaited(camera.dispose());
      }
      _autoCapture.reset();
    } else if (state == AppLifecycleState.resumed) {
      if (_camera == null && _status != _CameraStatus.starting) {
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
        _torchOn = false;
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
    if (_analysisInFlight || _takingPicture || !_session.isServiceReady) {
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
        if (fire) {
          unawaited(HapticFeedback.lightImpact());
          unawaited(_capture());
        }
      }
    } catch (_) {
    } finally {
      _analysisInFlight = false;
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _takingPicture) return;
    _autoCapture.notifyCaptureStarted();
    setState(() {
      _takingPicture = true;
      _stableQuad = null;
    });
    _stabilizer.reset();
    try {
      final shot = await camera.takePicture();
      final bytes = await shot.readAsBytes();
      unawaited(_deleteQuietly(File(shot.path)));
      _session.addCapture(bytes);
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

  void _toggleAutoMode() {
    setState(() => _autoMode = !_autoMode);
    _autoCapture.reset();
  }

  Future<void> _toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    final next = !_torchOn;
    try {
      await camera.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _torchOn = next);
    } on CameraException catch (e) {
      _logger.warning('Torch unavailable: ${e.code}');
    }
  }

  Future<void> _openReview() async {
    if (_session.pageCount == 0 && !_session.isProcessing) return;
    final navigator = Navigator.of(context);
    await _pauseCamera();
    final saved = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => ScannerReviewPage(
          session: _session,
          onUploadFiles: widget.onUploadFiles,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      navigator.pop(true);
    } else {
      unawaited(_startCamera());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
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
                      _ChromeButton(
                        icon: HugeIcons.strokeRoundedCancel01,
                        onTap: () => Navigator.of(context).pop(false),
                        tooltip: context.strings.close,
                      ),
                      _ChromeButton(
                        icon: _torchOn
                            ? HugeIcons.strokeRoundedFlash
                            : HugeIcons.strokeRoundedFlashOff,
                        onTap: _camera == null ? null : _toggleTorch,
                        tooltip: _torchOn
                            ? context.strings.scannerTorchOff
                            : context.strings.scannerTorchOn,
                      ),
                    ],
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 88,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _ShutterButton(
                          enabled:
                              _status == _CameraStatus.ready &&
                              !_takingPicture &&
                              _session.isServiceReady,
                          armingProgress: _autoMode ? _autoCapture.progress : 0,
                          armingColor: colors.primary,
                          onTap: _capture,
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _AutoToggle(
                            active: _autoMode,
                            onTap: _toggleAutoMode,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ListenableBuilder(
                            listenable: _session,
                            builder: (context, _) => _DoneButton(
                              session: _session,
                              accent: colors.primary,
                              onTap: _openReview,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(ColorTokens colors) {
    if (_scannerInitFailed) {
      return _CameraMessage(
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
        return _CameraMessage(
          message: context.strings.cameraPermissionSettings,
          onRetry: _startCamera,
        );
      case _CameraStatus.error:
        return _CameraMessage(
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(camera),
                ScanQuadOverlay(
                  quad: _takingPicture ? null : _stableQuad,
                  color: colors.primary,
                ),
              ],
            ),
          ),
        );
    }
  }
}

class _CameraMessage extends StatelessWidget {
  const _CameraMessage({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: colors.specialWhite),
            ),
            const SizedBox(height: Spacing.xl),
            ButtonComponent(
              label: context.strings.retry,
              size: ButtonComponentSize.small,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.onTap, this.tooltip});

  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: HugeIcon(
            icon: icon,
            color: onTap == null
                ? colors.specialWhite.withValues(alpha: 0.4)
                : colors.specialWhite,
            size: 22,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.enabled,
    required this.armingProgress,
    required this.armingColor,
    required this.onTap,
  });

  final bool enabled;

  final double armingProgress;
  final Color armingColor;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final white = colors.specialWhite;
    return GestureDetector(
      onTap: enabled ? () => onTap() : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.5,
        child: SizedBox(
          width: 76,
          height: 76,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: white, width: 4),
                ),
                child: Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: white,
                    ),
                  ),
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: armingProgress.clamp(0.0, 1.0)),
                duration: Motion.quick,
                builder: (context, value, _) => CustomPaint(
                  painter: _ArmingArcPainter(
                    progress: value,
                    color: armingColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArmingArcPainter extends CustomPainter {
  const _ArmingArcPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || size.isEmpty) return;
    canvas.drawArc(
      Rect.fromCircle(
        center: size.center(Offset.zero),
        radius: size.shortestSide / 2 - 2,
      ),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ArmingArcPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

class _AutoToggle extends StatelessWidget {
  const _AutoToggle({required this.active, required this.onTap});

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Tooltip(
      message: active
          ? context.strings.scannerAutoCaptureOff
          : context.strings.scannerAutoCaptureOn,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.standard,
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: active
                ? colors.primary
                : Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedCameraAutomatically01,
                color: colors.specialWhite,
                size: 20,
              ),
              const SizedBox(width: Spacing.xs),
              Text(
                active
                    ? context.strings.scannerCaptureModeAuto
                    : context.strings.scannerCaptureModeManual,
                style: TextStyles.mini.copyWith(color: colors.specialWhite),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.session,
    required this.accent,
    required this.onTap,
  });

  final ScanSessionController session;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final visible = session.pageCount > 0 || session.isProcessing;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: Motion.standard,
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: Tooltip(
          message: context.strings.done,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Center(
                        child: session.isProcessing
                            ? SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: colors.specialWhite,
                                ),
                              )
                            : HugeIcon(
                                icon: HugeIcons.strokeRoundedTick02,
                                color: colors.specialWhite,
                                size: 30,
                              ),
                      ),
                    ),
                  ),
                  if (session.pageCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.all(Spacing.xs),
                        constraints: const BoxConstraints(minWidth: 22),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.specialWhite,
                        ),
                        child: Center(
                          child: Text(
                            '${session.pageCount}',
                            style: TextStyles.mini.copyWith(color: accent),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
