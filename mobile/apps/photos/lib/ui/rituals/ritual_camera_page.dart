import "dart:async";
import "dart:io";

import "package:camera/camera.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/actions/collection/collection_file_actions.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/rituals/all_rituals_screen.dart";
import "package:receive_sharing_intent/receive_sharing_intent.dart";

void openRitualCamera(BuildContext context, Ritual ritual) {
  final albumId = ritual.albumId;
  if (albumId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.ritualSetAlbumToLaunchCamera)),
    );
    return;
  }
  routeToPage(context, RitualCameraPage(ritualId: ritual.id, albumId: albumId));
}

enum _CameraScreenMode { capture, review }

class _RitualCapture {
  const _RitualCapture({required this.file, required this.mirrorPreview});

  final XFile file;
  final bool mirrorPreview;
}

class RitualCameraPage extends StatefulWidget {
  const RitualCameraPage({
    super.key,
    required this.ritualId,
    required this.albumId,
  });

  final String ritualId;
  final int? albumId;

  @override
  State<RitualCameraPage> createState() => _RitualCameraPageState();
}

class _RitualCameraPageState extends State<RitualCameraPage>
    with WidgetsBindingObserver {
  static CameraDescription? _cachedPreferredBackCamera;
  CameraController? _controller;
  List<CameraDescription> _cameras = <CameraDescription>[];
  CameraDescription? _activeCamera;
  CameraDescription? _preferredBackCamera = _cachedPreferredBackCamera;
  late final PageController _pageController;
  late final ScrollController _thumbScrollController;
  Ritual? _ritual;
  _CameraScreenMode _mode = _CameraScreenMode.capture;
  int _selectedIndex = 0;
  bool _pausedForNavigation = false;
  bool _initializing = true;
  bool _capturing = false;
  bool _saving = false;
  String? _error;
  List<_RitualCapture> _captures = <_RitualCapture>[];
  Collection? _album;
  bool _isPinching = false;
  double _minAvailableZoom = 1.0;
  double _maxAvailableZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;
  Offset? _focusPointRel;
  Timer? _focusHideTimer;
  Timer? _zoomHintTimer;
  bool _showZoomHint = false;
  static const int _maxCaptures = 20;
  late final VoidCallback _ritualsListener;
  static const double _thumbnailSize = 80;
  static const double _thumbnailSpacing = 12;

  void _ensurePageVisible(int index, {bool animate = false}) {
    if (_captures.isEmpty) return;
    final int capped = index.clamp(0, _captures.length - 1);
    void jump() {
      if (animate) {
        _pageController.animateToPage(
          capped,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _pageController.jumpToPage(capped);
      }
    }

    if (_pageController.hasClients) {
      jump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          jump();
        }
      });
    }
  }

  void _scrollThumbsToIndex(int index, {bool animate = true}) {
    if (_captures.isEmpty) return;
    final int capped = index.clamp(0, _captures.length - 1);
    void jump() {
      if (!_thumbScrollController.hasClients) return;
      final double itemStart = capped * (_thumbnailSize + _thumbnailSpacing);
      final double itemEnd = itemStart + _thumbnailSize;
      const double padding = 20;
      final double viewport = _thumbScrollController.position.viewportDimension;
      double newOffset = _thumbScrollController.offset;
      if (itemStart - padding < newOffset) {
        newOffset = itemStart - padding;
      } else if (itemEnd + padding > newOffset + viewport) {
        newOffset = itemEnd + padding - viewport;
      }
      final double maxOffset = _thumbScrollController.position.maxScrollExtent;
      newOffset = newOffset.clamp(0.0, maxOffset);
      if ((newOffset - _thumbScrollController.offset).abs() < 0.5) {
        return;
      }
      if (animate) {
        _thumbScrollController.animateTo(
          newOffset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _thumbScrollController.jumpTo(newOffset);
      }
    }

    if (_thumbScrollController.hasClients) {
      jump();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController();
    _thumbScrollController = ScrollController();
    _ritualsListener = _syncRitualFromService;
    ritualsService.stateNotifier.addListener(_ritualsListener);
    _loadAlbum();
    _syncRitualFromService();
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ritualsService.stateNotifier.removeListener(_ritualsListener);
    _focusHideTimer?.cancel();
    _zoomHintTimer?.cancel();
    _controller?.dispose();
    _pageController.dispose();
    _thumbScrollController.dispose();
    _cleanupCaptures();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.resumed) {
      if (controller == null || !controller.value.isInitialized) {
        unawaited(_initializeCamera(_activeCamera));
      }
      return;
    }
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(controller.dispose());
      _controller = null;
    }
  }

  Future<void> _loadAlbum() async {
    if (widget.albumId == null) return;
    final collection = CollectionsService.instance.getCollectionByID(
      widget.albumId!,
    );
    if (mounted) {
      setState(() {
        _album = collection;
      });
    }
  }

  void _syncRitualFromService() {
    final rituals = ritualsService.stateNotifier.value.rituals;
    Ritual? match;
    for (final ritual in rituals) {
      if (ritual.id == widget.ritualId) {
        match = ritual;
        break;
      }
    }
    if (match != null && mounted) {
      setState(() {
        _ritual = match;
      });
    }
  }

  Future<CameraDescription?> _pickPreferredBackCamera() async {
    if (_preferredBackCamera != null &&
        _cameras.contains(_preferredBackCamera)) {
      return _preferredBackCamera;
    }
    final List<CameraDescription> backCameras = _cameras
        .where((camera) => camera.lensDirection == CameraLensDirection.back)
        .toList(growable: false);
    if (backCameras.isEmpty) {
      return null;
    }
    if (backCameras.length == 1) {
      _preferredBackCamera = backCameras.first;
      return _preferredBackCamera;
    }

    int bestPixels = -1;
    CameraDescription? bestCamera;
    for (final camera in backCameras) {
      if (!mounted) break;
      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
      );
      try {
        await controller.initialize();
        final Size? size = controller.value.previewSize;
        final int pixels = size == null
            ? -1
            : (size.width * size.height).toInt();
        if (pixels > bestPixels) {
          bestPixels = pixels;
          bestCamera = camera;
        }
      } catch (_) {
        // Ignore cameras that fail to initialize.
      } finally {
        try {
          await controller.dispose();
        } catch (_) {
          // Ignore dispose failures.
        }
      }
    }
    _preferredBackCamera = bestCamera ?? backCameras.first;
    _cachedPreferredBackCamera = _preferredBackCamera;
    return _preferredBackCamera;
  }

  Future<void> _initializeCamera([CameraDescription? description]) async {
    if (!flagService.ritualsFlag) return;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      _cameras = _cameras.isEmpty ? await availableCameras() : _cameras;
      if (_cameras.isEmpty) {
        setState(() {
          _error = context.l10n.ritualCameraNotFound;
          _initializing = false;
        });
        return;
      }
      final CameraDescription target =
          description ??
          (_controller == null
              ? await _pickPreferredBackCamera() ?? _cameras.first
              : _preferredCamera() ?? _cameras.first);
      final bool reuseExisting = _controller != null;
      if (reuseExisting) {
        await _controller!.setDescription(target);
      } else {
        final controller = CameraController(
          target,
          ResolutionPreset.max,
          enableAudio: false,
        );
        await controller.initialize();
        _controller = controller;
      }
      if (_controller != null) {
        _minAvailableZoom = await _controller!.getMinZoomLevel();
        _maxAvailableZoom = await _controller!.getMaxZoomLevel();
        _currentZoom = 1.0;
        _baseZoom = 1.0;
        await _controller!.setZoomLevel(_currentZoom);
      }
      if (!mounted) {
        await _controller?.dispose();
        return;
      }
      setState(() {
        _activeCamera = target;
        _initializing = false;
      });
    } catch (e) {
      setState(() {
        _error = context.l10n.ritualCameraStartError;
        _initializing = false;
      });
    }
  }

  CameraDescription? _preferredCamera() {
    if (_preferredBackCamera != null &&
        _cameras.contains(_preferredBackCamera)) {
      return _preferredBackCamera;
    }
    for (final camera in _cameras) {
      if (camera.lensDirection == CameraLensDirection.back) {
        return camera;
      }
    }
    return null;
  }

  bool get _canSwitchCamera =>
      _cameras.length > 1 && !_saving && !_initializing;

  CameraDescription? _cameraForDirection(CameraLensDirection direction) {
    for (final camera in _cameras) {
      if (camera.lensDirection == direction) {
        return camera;
      }
    }
    return null;
  }

  CameraDescription? _backCameraForFlip() {
    if (_preferredBackCamera != null &&
        _cameras.contains(_preferredBackCamera)) {
      return _preferredBackCamera;
    }
    return _cameraForDirection(CameraLensDirection.back);
  }

  Future<void> _switchCamera() async {
    if (!_canSwitchCamera) return;
    final current = _activeCamera;
    if (current == null) return;
    final nextIndex = (_cameras.indexOf(current) + 1) % _cameras.length;
    await _initializeCamera(_cameras[nextIndex]);
  }

  Future<void> _flipCamera() async {
    if (!_canSwitchCamera) return;
    final current = _activeCamera;
    if (current == null) return;
    final bool isFront = current.lensDirection == CameraLensDirection.front;
    final CameraDescription? target = isFront
        ? _backCameraForFlip()
        : _cameraForDirection(CameraLensDirection.front);
    if (target == null || target == current) return;
    await _initializeCamera(target);
  }

  void _handleViewFinderDoubleTap() {
    unawaited(_flipCamera());
  }

  Future<void> _takePicture() async {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _capturing ||
        _saving) {
      return;
    }
    final bool shouldMirrorPreview =
        _controller!.description.lensDirection == CameraLensDirection.front;
    setState(() {
      _capturing = true;
    });
    try {
      final XFile capture = await _controller!.takePicture();
      if (!mounted) return;
      setState(() {
        _captures = List<_RitualCapture>.from(_captures)
          ..add(
            _RitualCapture(file: capture, mirrorPreview: shouldMirrorPreview),
          );
      });
      _ensurePageVisible(_captures.length - 1, animate: true);
      _scrollThumbsToIndex(_captures.length - 1, animate: true);
    } catch (_) {
      if (!mounted) return;
      showShortToast(context, context.l10n.ritualCaptureError);
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  Future<void> _onShutterTap() async {
    if (_captures.length >= _maxCaptures) {
      if (mounted) {
        showShortToast(
          context,
          context.l10n.ritualPhotoLimit(maxPhotos: _maxCaptures),
        );
      }
      return;
    }
    final int previousCount = _captures.length;
    await _takePicture();
    if (!mounted) return;
    final int newCount = _captures.length;
    if (newCount > previousCount) {
      setState(() {
        _selectedIndex = newCount - 1;
        if (previousCount == 0) {
          _mode = _CameraScreenMode.review;
        }
      });
      _ensurePageVisible(_selectedIndex, animate: true);
      _scrollThumbsToIndex(_selectedIndex, animate: true);
    }
  }

  Future<void> _onAccept() async {
    if (_captures.isEmpty) {
      showShortToast(context, context.l10n.ritualCaptureAtLeastOne);
      return;
    }
    if (widget.albumId == null) {
      if (!mounted) return;
      final navContext = context;
      ScaffoldMessenger.of(navContext).showSnackBar(
        SnackBar(content: Text(navContext.l10n.ritualAlbumMissing)),
      );
      await _pausePreview();
      if (!mounted) return;
      if (!navContext.mounted) return;
      await routeToPage(
        navContext,
        const AllRitualsScreen(),
      ).whenComplete(_resumePreview);
      return;
    }
    final List<_RitualCapture> pending = List<_RitualCapture>.from(_captures);
    bool saved = false;
    setState(() {
      _saving = true;
    });
    try {
      final shared = pending
          .map(
            (capture) => SharedMediaFile(
              path: capture.file.path,
              type: SharedMediaType.image,
            ),
          )
          .toList(growable: false);
      final actions = CollectionActions(CollectionsService.instance);
      await actions.addToCollection(
        context,
        widget.albumId!,
        true,
        sharedFiles: shared,
      );
      saved = true;
      if (!mounted) return;
      showShortToast(
        context,
        _album == null
            ? context.l10n.ritualAddedToAlbum
            : context.l10n.ritualAddedToAlbumWithName(
                albumName: _album!.displayName,
              ),
      );
      await ritualsService.refresh();
      if (!mounted) return;
      await Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.ritualAddToAlbumFailure(error: e.toString()),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          if (saved) {
            _captures = <_RitualCapture>[];
          }
        });
      }
      if (saved) {
        _cleanupCaptures(pending);
      }
    }
  }

  void _enterReview() {
    if (_captures.isEmpty) return;
    setState(() {
      _mode = _CameraScreenMode.review;
      _selectedIndex = _captures.length - 1;
    });
    _ensurePageVisible(_selectedIndex);
  }

  void _returnToCapture() {
    setState(() {
      _mode = _CameraScreenMode.capture;
    });
  }

  void _removeCapture(int index) {
    if (index < 0 || index >= _captures.length) return;
    final capture = _captures[index];
    try {
      File(capture.file.path).deleteSync();
    } catch (_) {
      // best-effort cleanup
    }
    setState(() {
      _captures.removeAt(index);
      if (_captures.isEmpty) {
        _mode = _CameraScreenMode.capture;
        _selectedIndex = 0;
      } else {
        _selectedIndex = index.clamp(0, _captures.length - 1);
      }
    });
    if (_captures.isNotEmpty) {
      _ensurePageVisible(_selectedIndex);
      _scrollThumbsToIndex(_selectedIndex);
    }
  }

  void _cleanupCaptures([List<_RitualCapture>? files]) {
    final targets = files ?? _captures;
    for (final capture in targets) {
      try {
        File(capture.file.path).deleteSync();
      } catch (_) {
        // ignore cleanup failures
      }
    }
    _captures = <_RitualCapture>[];
  }

  Future<void> _pausePreview() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isPreviewPaused) {
      return;
    }
    try {
      await controller.pausePreview();
      _pausedForNavigation = true;
    } catch (_) {
      // ignore pause failures
    }
  }

  Future<void> _resumePreview() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !_pausedForNavigation) {
      return;
    }
    try {
      await controller.resumePreview();
      _pausedForNavigation = false;
    } catch (_) {
      // ignore resume failures
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!flagService.ritualsFlag) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text("Rituals are currently limited to internal users."),
            ),
          ),
        ),
      );
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final bool isReady =
        _controller != null &&
        _controller!.value.isInitialized &&
        !_initializing;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(textTheme),
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _mode == _CameraScreenMode.capture
                        ? _buildCameraArea(isReady, colorScheme)
                        : _buildReviewArea(),
                  ),
                  if (_mode == _CameraScreenMode.capture &&
                      _captures.isNotEmpty)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: _ConfirmChip(
                        count: _captures.length,
                        onTap: _enterReview,
                      ),
                    ),
                ],
              ),
            ),
            _mode == _CameraScreenMode.capture
                ? _buildCaptureControls(colorScheme, isReady)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_captures.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: _ThumbnailStrip(
                            captures: _captures,
                            selectedIndex: _selectedIndex,
                            controller: _thumbScrollController,
                            onSelect: (index) {
                              setState(() {
                                _selectedIndex = index;
                              });
                              _ensurePageVisible(index);
                              _scrollThumbsToIndex(index);
                            },
                            onRemove: _removeCapture,
                          ),
                        ),
                      _buildReviewControls(colorScheme, textTheme),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(EnteTextTheme textTheme) {
    final String title = _ritual?.title.trim().isNotEmpty == true
        ? _ritual!.title.trim()
        : context.l10n.ritualDefaultCameraTitle;
    final String icon = _ritual?.icon.isNotEmpty == true ? _ritual!.icon : "📸";
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: textTheme.smallBold.copyWith(color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Spacer(),
          _RoundIconButton(
            onTap: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: Colors.white),
            background: Colors.white.withValues(alpha: 0.12),
            size: 44,
          ),
        ],
      ),
    );
  }

  Widget _buildCameraArea(bool isReady, EnteColorScheme colorScheme) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.textMuted, size: 32),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _initializing ? null : _initializeCamera,
              child: Text(context.l10n.tryAgain),
            ),
            TextButton(
              onPressed: () async {
                await _pausePreview();
                if (!mounted) return;
                await routeToPage(
                  context,
                  const AllRitualsScreen(),
                ).whenComplete(_resumePreview);
              },
              child: Text(context.l10n.ritualBackToList),
            ),
          ],
        ),
      );
    }
    if (!isReady || _controller == null) {
      return const SizedBox.shrink();
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final mediaOrientation = MediaQuery.of(context).orientation;

        final Size? rawPreviewSize = _controller!.value.previewSize;
        final Size fallbackSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final Size viewSize = Size(constraints.maxWidth, constraints.maxHeight);
        final Size rotatedPreviewSize =
            mediaOrientation == Orientation.portrait && rawPreviewSize != null
            ? Size(rawPreviewSize.height, rawPreviewSize.width)
            : (rawPreviewSize ?? fallbackSize);
        final FittedSizes fittedSizes = applyBoxFit(
          BoxFit.contain,
          rotatedPreviewSize,
          viewSize,
        );
        final Rect previewRect = Alignment.center.inscribe(
          fittedSizes.destination,
          Offset.zero & viewSize,
        );

        final Offset? focus = _focusPointRel == null
            ? null
            : Offset(
                previewRect.left + _focusPointRel!.dx * previewRect.width,
                previewRect.top + _focusPointRel!.dy * previewRect.height,
              );

        final cameraPreview = CameraPreview(_controller!);

        return Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: rotatedPreviewSize.width,
                  height: rotatedPreviewSize.height,
                  child: cameraPreview,
                ),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _handleViewFinderDoubleTap,
                onScaleStart: _handleScaleStart,
                onScaleUpdate: _handleScaleUpdate,
                onScaleEnd: _handleScaleEnd,
                onTapDown: (details) => _onViewFinderTap(details, previewRect),
              ),
            ),
            Positioned.fromRect(
              rect: previewRect,
              child: IgnorePointer(child: CustomPaint(painter: _GridPainter())),
            ),
            if (focus != null)
              Positioned(
                key: const ValueKey("focus_indicator"),
                left: focus.dx - 24,
                top: focus.dy - 24,
                child: AnimatedOpacity(
                  opacity: _focusPointRel == null ? 0 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 2,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              key: const ValueKey("zoom_indicator"),
              left: 12,
              top: 88, // keep below top bar so it stays visible
              child: AnimatedOpacity(
                opacity: _showZoomHint ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    "${_currentZoom.toStringAsFixed(1)}x",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReviewArea() {
    if (_captures.isEmpty) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Text(
            context.l10n.ritualNoPhotosYet,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return Container(
      color: Colors.black,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _captures.length,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
          _scrollThumbsToIndex(index);
        },
        itemBuilder: (context, index) {
          final capture = _captures[index];
          return _MirroredImage(
            mirror: capture.mirrorPreview,
            child: Image.file(
              File(capture.file.path),
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
          );
        },
      ),
    );
  }

  Widget _buildCaptureControls(EnteColorScheme colorScheme, bool isReady) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    final bool canCapture =
        !_capturing && !_saving && isReady && _captures.length < _maxCaptures;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 32, 16, 26 + bottomPadding),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.60)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 96,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _LatestPreview(captures: _captures, onTap: _enterReview),
            ),
          ),
          Expanded(
            child: Center(
              child: _ShutterButton(
                enabled: canCapture,
                busy: _capturing,
                onTap: canCapture ? _onShutterTap : null,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: _RoundIconButton(
                    onTap: _canSwitchCamera ? _switchCamera : null,
                    icon: const Icon(
                      Icons.cameraswitch_rounded,
                      color: Colors.white,
                    ),
                    background: Colors.white.withValues(alpha: 0.12),
                    size: 48,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewControls(
    EnteColorScheme colorScheme,
    EnteTextTheme textTheme,
  ) {
    final double bottomPadding = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 18, 16, 24 + bottomPadding),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.60)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _RoundIconButton(
                onTap: _saving ? null : _returnToCapture,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedImageAdd02,
                  color: Colors.white,
                  size: 22,
                ),
                background: Colors.white.withValues(alpha: 0.12),
                size: 44,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: (_captures.isNotEmpty && !_saving)
                    ? _onAccept
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.textBase,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_outline),
                          const SizedBox(width: 8),
                          Text(
                            context.l10n.addToAlbum,
                            style: textTheme.bodyBold.copyWith(
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleScaleStart(ScaleStartDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _isPinching = details.pointerCount >= 2;
    _baseZoom = _currentZoom;
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _isPinching = false;
  }

  Future<void> _handleScaleUpdate(ScaleUpdateDetails details) async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (details.pointerCount < 2) {
      _isPinching = false;
      return;
    }
    if (!_isPinching) {
      _isPinching = true;
      _baseZoom = _currentZoom;
    }
    final double newZoom = (_baseZoom * details.scale).clamp(
      _minAvailableZoom,
      _maxAvailableZoom,
    );
    if ((newZoom - _currentZoom).abs() < 0.001) return;
    _currentZoom = newZoom;
    try {
      await _controller!.setZoomLevel(_currentZoom);
      _showZoomIndicator();
    } catch (_) {
      // Ignore zoom failures to avoid interrupting capture flow.
    }
  }

  void _onViewFinderTap(TapDownDetails details, Rect previewRect) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (!previewRect.contains(details.localPosition)) {
      return;
    }
    final offset = Offset(
      (details.localPosition.dx - previewRect.left) / previewRect.width,
      (details.localPosition.dy - previewRect.top) / previewRect.height,
    );
    try {
      final clamped = Offset(
        offset.dx.clamp(0.0, 1.0),
        offset.dy.clamp(0.0, 1.0),
      );
      final bool shouldMirrorPreview =
          _activeCamera?.lensDirection == CameraLensDirection.front;
      final Offset cameraPoint = shouldMirrorPreview
          ? Offset(1.0 - clamped.dx, clamped.dy)
          : clamped;
      controller.setExposurePoint(cameraPoint);
      controller.setFocusPoint(cameraPoint);
      _showFocusIndicator(clamped);
    } catch (_) {
      // Best effort; not all devices support focus/exposure points.
    }
  }

  void _showFocusIndicator(Offset normalizedOffset) {
    _focusHideTimer?.cancel();
    setState(() {
      _focusPointRel = normalizedOffset;
    });
    _focusHideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _focusPointRel = null;
        });
      }
    });
  }

  void _showZoomIndicator() {
    _zoomHintTimer?.cancel();
    setState(() {
      _showZoomHint = true;
    });
    _zoomHintTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _showZoomHint = false;
        });
      }
    });
  }
}

class _ThumbnailStrip extends StatelessWidget {
  const _ThumbnailStrip({
    required this.captures,
    required this.selectedIndex,
    required this.controller,
    required this.onSelect,
    required this.onRemove,
  });

  final List<_RitualCapture> captures;
  final int selectedIndex;
  final ScrollController controller;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: captures.length,
        clipBehavior: Clip.none,
        controller: controller,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final capture = captures[index];
          return GestureDetector(
            onTap: () => onSelect(index),
            child: _ReviewThumb(
              capture: capture,
              selected: index == selectedIndex,
              onRemove: () => onRemove(index),
            ),
          );
        },
      ),
    );
  }
}

class _LatestPreview extends StatelessWidget {
  const _LatestPreview({required this.captures, required this.onTap});

  final List<_RitualCapture> captures;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final _RitualCapture? lastCapture = captures.isNotEmpty
        ? captures.last
        : null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(fade),
            child: child,
          ),
        );
      },
      child: lastCapture == null
          ? const SizedBox.shrink()
          : GestureDetector(
              key: ValueKey(lastCapture.file.path),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _MirroredImage(
                        mirror: lastCapture.mirrorPreview,
                        child: Image.file(
                          File(lastCapture.file.path),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1),
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

class _ConfirmChip extends StatelessWidget {
  const _ConfirmChip({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          color: Color(0xFF08C225),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Center(
              child: Icon(Icons.check, color: Colors.white, size: 26),
            ),
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF08C225),
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    "$count",
                    style: const TextStyle(
                      color: Color(0xFF08C225),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({
    required this.onTap,
    required this.enabled,
    required this.busy,
  });

  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white, width: 3),
        ),
        child: Center(
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              color: enabled ? Colors.white : Colors.white30,
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.onTap,
    required this.icon,
    this.background,
    this.size = 44,
  });

  final VoidCallback? onTap;
  final Widget icon;
  final Color? background;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: background ?? Colors.black.withValues(alpha: 0.1),
        ),
        child: Center(child: icon),
      ),
    );
  }
}

class _MirroredImage extends StatelessWidget {
  const _MirroredImage({required this.mirror, required this.child});

  final bool mirror;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!mirror) {
      return child;
    }
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
      child: child,
    );
  }
}

class _ReviewThumb extends StatelessWidget {
  const _ReviewThumb({
    required this.capture,
    required this.onRemove,
    required this.selected,
  });

  final _RitualCapture capture;
  final VoidCallback onRemove;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: selected ? 2 : 1),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _MirroredImage(
              mirror: capture.mirrorPreview,
              child: Image.file(
                File(capture.file.path),
                width: 80,
                height: 80,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFFF35151),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final double thirdWidth = size.width / 3;
    final double thirdHeight = size.height / 3;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(thirdWidth * i, 0),
        Offset(thirdWidth * i, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, thirdHeight * i),
        Offset(size.width, thirdHeight * i),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
