import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_ocr/mobile_ocr_plugin.dart';
import 'package:mobile_ocr/models/text_block.dart';
import 'package:photos/ui/viewer/file/ocr/display_image_helper.dart';
import 'package:photos/ui/viewer/file/ocr/text_overlay_widget.dart';

const Color _entePrimaryColor = Color(0xFF1DB954);
const double _enteSelectionHighlightOpacity = 0.28;

/// Collection of user-facing strings used by [TextDetectorWidget].
class TextDetectorStrings {
  final String processingOverlayMessage;
  final String selectionHint;
  final String noTextDetected;
  final String retryButtonLabel;
  final String modelsNetworkRequiredError;
  final String modelsPrepareFailed;
  final String imageNotFoundError;
  final String imageDecodeFailedError;
  final String genericDetectError;

  const TextDetectorStrings({
    this.processingOverlayMessage = 'Detecting text...',
    this.selectionHint = 'Swipe or double tap to select just what you need',
    this.noTextDetected = 'No text detected',
    this.retryButtonLabel = 'Retry',
    this.modelsNetworkRequiredError =
        'Network connection required to download OCR models on first use',
    this.modelsPrepareFailed = 'Could not prepare OCR models',
    this.imageNotFoundError = 'Image file not found',
    this.imageDecodeFailedError = 'Could not read image file',
    this.genericDetectError = 'Could not detect text in image',
  });
}

/// Controller that surfaces imperative actions for [TextDetectorWidget].
class TextDetectorController extends ChangeNotifier {
  _TextDetectorWidgetState? _state;

  void _attach(_TextDetectorWidgetState state) {
    if (identical(_state, state)) {
      return;
    }
    _state = state;
    scheduleMicrotask(() {
      notifyListeners();
    });
  }

  void _detach(_TextDetectorWidgetState state) {
    if (identical(_state, state)) {
      _state = null;
      notifyListeners();
    }
  }

  void _notifyStateChanged() {
    notifyListeners();
  }

  /// Whether text detection is currently running.
  bool get isProcessing => _state?._isProcessing ?? false;

  /// Indicates if there is text that can be selected.
  bool get hasSelectableText => _state?._hasSelectableText ?? false;

  /// Whether the user has explicitly interacted (e.g. long press).
  bool get userAttemptedInteraction =>
      _state?._userAttemptedInteraction ?? false;

  /// Programmatically select all recognized text.
  bool selectAllText() {
    final state = _state;
    if (state == null) {
      return false;
    }
    return state._selectAllRecognizedText();
  }

  bool get hasActiveSelection => _state?._hasActiveSelection ?? false;

  bool selectTextAtPosition(Offset globalPosition) {
    final state = _state;
    if (state == null) {
      return false;
    }
    return state._selectTextAtPosition(globalPosition);
  }

  void clearSelection() {
    _state?._clearSelection();
  }

  bool isPointOnSelectableText(Offset globalPosition) {
    return _state?._isPointOnSelectableText(globalPosition) ?? false;
  }

  bool isPointOnInteractiveSelectionUi(Offset globalPosition) {
    return _state?._isPointOnInteractiveSelectionUi(globalPosition) ?? false;
  }
}

/// A complete text detection widget that displays an image and allows
/// users to select and copy detected text.
class TextDetectorWidget extends StatefulWidget {
  /// The path to the image file to detect text from
  final String imagePath;

  /// Callback when text is copied
  final Function(String)? onTextCopied;

  /// Callback when text blocks are selected
  final Function(List<TextBlock>)? onTextBlocksSelected;

  /// Whether to auto-detect text on load
  final bool autoDetect;

  /// Background color
  final Color backgroundColor;

  /// Whether to show boundaries for unselected text
  final bool showUnselectedBoundaries;

  /// Whether to show the inline selection preview banner.
  final bool enableSelectionPreview;

  /// Enable debug utilities like the detected-text dialog.
  final bool debugMode;

  /// Strings used for user-facing text in the widget.
  final TextDetectorStrings strings;

  /// Controller for imperative text selection actions.
  final TextDetectorController? controller;

  /// When true, only the text overlay is rendered (no image). Use this when
  /// the image is already displayed by another widget underneath.
  final bool overlayOnly;

  /// Whether to show the "Detecting text..." overlay during processing.
  /// Defaults to true for backward compatibility.
  final bool showProcessingOverlay;

  /// Whether to show the selection hint after text is detected.
  /// Defaults to true for backward compatibility.
  final bool showEditorHint;

  /// Whether automatic detection should show the no-text message.
  final bool showNoTextMessageOnAutoDetect;

  /// When set, the widget starts with the interaction animation active and
  /// will auto-select text at this position after detection completes.
  /// Used when the parent captured a long press before the widget was built.
  final Offset? initialInteractionPosition;

  /// Whether to show the built-in scan line animation during processing.
  /// Defaults to true for backward compatibility.
  final bool showScanAnimation;

  /// Whether the underlying image viewer is currently zoomed.
  final bool isImageZoomed;

  /// Optional callback invoked instead of word selection on double tap while
  /// the underlying image is zoomed.
  final VoidCallback? onDoubleTapWhenZoomed;

  /// Scale factor applied to the overlay by an ancestor transform.
  /// Passed to [TextOverlayWidget] to counter-scale UI chrome (handles,
  /// copy button) back to a fixed screen size. Defaults to 1.0 (no scaling).
  final double uiScale;

  /// Translation applied to the overlay by an ancestor transform.
  final Offset uiOffset;

  /// Determines how OCR gestures should behave while the image is zoomed.
  final ZoomedInteractionPolicy zoomedInteractionPolicy;

  const TextDetectorWidget({
    super.key,
    required this.imagePath,
    this.onTextCopied,
    this.onTextBlocksSelected,
    this.autoDetect = true,
    this.backgroundColor = Colors.transparent,
    this.showUnselectedBoundaries = true,
    this.enableSelectionPreview = false,
    this.debugMode = false,
    this.strings = const TextDetectorStrings(),
    this.controller,
    this.overlayOnly = false,
    this.showProcessingOverlay = true,
    this.showEditorHint = true,
    this.showNoTextMessageOnAutoDetect = true,
    this.initialInteractionPosition,
    this.showScanAnimation = true,
    this.isImageZoomed = false,
    this.onDoubleTapWhenZoomed,
    this.uiScale = 1.0,
    this.uiOffset = Offset.zero,
    this.zoomedInteractionPolicy = ZoomedInteractionPolicy.panFirst,
  });

  @override
  State<TextDetectorWidget> createState() => _TextDetectorWidgetState();
}

class _TextDetectorWidgetState extends State<TextDetectorWidget> {
  final MobileOcr _ocr = MobileOcr();
  final TextOverlayController _textOverlayController = TextOverlayController();
  List<TextBlock>? _detectedTextBlocks;
  bool _isProcessing = false;
  File? _imageFile;
  String? _resolvedImagePath;
  Future<void>? _imagePreparation;
  bool _modelsReady = false;
  Future<void>? _modelPreparation;
  String? _errorMessage;
  Timer? _editorHintTimer;
  bool _showEditorHint = false;
  bool _isNetworkError = false;
  Size? _imageSize;
  bool _userAttemptedInteraction = false;
  Offset? _pendingSelectionPosition;
  bool get _hasSelectableText =>
      _detectedTextBlocks != null && _detectedTextBlocks!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
    // Pick up initial interaction from parent (e.g. long press before widget existed)
    if (widget.initialInteractionPosition != null) {
      _userAttemptedInteraction = true;
      _pendingSelectionPosition = widget.initialInteractionPosition;
      _isProcessing = true;
    } else if (widget.autoDetect) {
      // Set initial processing state if auto-detecting
      _isProcessing = true;
    }
    // Schedule file initialization after first frame to ensure immediate rendering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializeFile());
    });
  }

  @override
  void dispose() {
    _editorHintTimer?.cancel();
    widget.controller?._detach(this);
    super.dispose();
  }

  Future<void> _initializeFile() async {
    final requestedPath = widget.imagePath;
    _editorHintTimer?.cancel();

    final preparation = _prepareDisplayImage(requestedPath);
    _imagePreparation = preparation;
    await preparation;
    if (_imagePreparation == preparation) {
      _imagePreparation = null;
    }
  }

  Future<void> _prepareDisplayImage(String requestedPath) async {
    setState(() {
      _imageFile = null;
      _resolvedImagePath = null;
      _showEditorHint = false;
      _errorMessage = null;
    });

    try {
      final resolvedPath = await DisplayImageHelper.ensureDisplayablePath(
        requestedPath,
      );
      if (!mounted || widget.imagePath != requestedPath) {
        return;
      }
      final file = File(resolvedPath);
      if (!file.existsSync()) {
        throw Exception('Image file not found after normalization');
      }

      setState(() {
        _imageFile = file;
        _resolvedImagePath = resolvedPath;
      });

      if (!widget.overlayOnly) {
        _precacheCurrentImage();
      }

      if (widget.autoDetect || widget.initialInteractionPosition != null) {
        unawaited(_detectText());
      }
    } catch (error) {
      debugPrint('Failed to prepare image $requestedPath: $error');
      if (!mounted || widget.imagePath != requestedPath) {
        return;
      }
      setState(() {
        _imageFile = null;
        _resolvedImagePath = null;
        _errorMessage = widget.strings.imageDecodeFailedError;
        _isProcessing = false;
      });
    }
  }

  @override
  void didUpdateWidget(covariant TextDetectorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.imagePath != widget.imagePath) {
      setState(() {
        _isProcessing = widget.autoDetect;
        _detectedTextBlocks = null;
        _imageFile = null;
        _errorMessage = null;
        _isNetworkError = false;
        _userAttemptedInteraction = false;
        _pendingSelectionPosition = null;
      });
      _notifyController();
      unawaited(_initializeFile());
    }
  }

  Future<void> _ensureModelsReady() async {
    if (_modelsReady) return;

    _modelPreparation ??= _ocr
        .prepareModels()
        .then((status) {
          _modelsReady = status.isReady;
        })
        .catchError((error, _) {
          final errorStr = error.toString().toLowerCase();
          _isNetworkError =
              errorStr.contains('network') ||
              errorStr.contains('connection') ||
              errorStr.contains('timeout') ||
              errorStr.contains('failed to download') ||
              errorStr.contains('http');

          if (_isNetworkError) {
            _errorMessage = widget.strings.modelsNetworkRequiredError;
          } else {
            _errorMessage = widget.strings.modelsPrepareFailed;
          }
          debugPrint('Model preparation error: $error');
        })
        .whenComplete(() {
          _modelPreparation = null;
        });

    await _modelPreparation;
  }

  Future<void> _detectText() async {
    final String requestedPath = widget.imagePath;
    String? imagePath = _resolvedImagePath;
    if (imagePath == null) {
      final pendingPreparation = _imagePreparation;
      if (pendingPreparation != null) {
        await pendingPreparation;
        if (!mounted || widget.imagePath != requestedPath) {
          return;
        }
        imagePath = _resolvedImagePath;
      }
    }
    if (imagePath == null) {
      setState(() {
        _errorMessage = widget.strings.imageDecodeFailedError;
        _isProcessing = false;
      });
      _notifyController();
      return;
    }

    // Don't set processing true here if already processing
    if (!_isProcessing) {
      setState(() {
        _isProcessing = true;
        _detectedTextBlocks = null;
        _errorMessage = null;
        _isNetworkError = false;
      });
      _notifyController();
    }

    try {
      await _ensureModelsReady();
      if (_errorMessage != null) {
        throw Exception(_errorMessage);
      }

      final result = await _ocr.detectText(imagePath: imagePath);

      if (mounted && widget.imagePath == requestedPath) {
        final pendingPos = _pendingSelectionPosition;
        setState(() {
          _detectedTextBlocks = result.blocks;
          _imageSize = result.imageSize;
          _errorMessage = null;
          _pendingSelectionPosition = null;
        });
        _notifyController();
        _handleEditorHint(_detectedTextBlocks ?? []);

        // If the user long-pressed during processing, queue auto-select.
        // The overlay controller will execute it once block visuals are ready.
        if (pendingPos != null && (_detectedTextBlocks?.isNotEmpty ?? false)) {
          _textOverlayController.selectTextAtPosition(pendingPos);
        }
      }
    } catch (e) {
      debugPrint('Error detecting text: $e');
      if (mounted && widget.imagePath == requestedPath) {
        setState(() {
          // Show user-friendly message based on error type
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('image') &&
              errorStr.contains('not') &&
              errorStr.contains('exist')) {
            _errorMessage = widget.strings.imageNotFoundError;
          } else if (errorStr.contains('failed to decode')) {
            _errorMessage = widget.strings.imageDecodeFailedError;
          } else {
            _errorMessage = widget.strings.genericDetectError;
          }
        });
        _notifyController();
      }
    } finally {
      if (mounted && widget.imagePath == requestedPath) {
        setState(() {
          _isProcessing = false;
          _pendingSelectionPosition = null;
        });
        _notifyController();
      }
    }
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    setState(() {
      _userAttemptedInteraction = true;
      _pendingSelectionPosition = details.globalPosition;
    });
    _notifyController();

    if (!_isProcessing && _resolvedImagePath != null) {
      unawaited(_detectText());
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showProcessingAnimation =
        _isProcessing &&
        _detectedTextBlocks == null &&
        _userAttemptedInteraction;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _hasSelectableText ? null : _handleLongPressStart,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImageLayer(),
          if (showProcessingAnimation && widget.showScanAnimation)
            const _ScanLineAnimation(),
          if (widget.showProcessingOverlay &&
              _isProcessing &&
              _detectedTextBlocks == null &&
              !_userAttemptedInteraction)
            _buildProcessingOverlay(),
          if (widget.showEditorHint &&
              _showEditorHint &&
              _detectedTextBlocks != null &&
              _detectedTextBlocks!.isNotEmpty)
            _buildEditorHint(),
          if (_errorMessage != null)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: _isNetworkError
                  ? _buildNetworkErrorBanner(_errorMessage!)
                  : _buildErrorBanner(_errorMessage!),
            ),
          if ((widget.showNoTextMessageOnAutoDetect ||
                  _userAttemptedInteraction) &&
              _detectedTextBlocks != null &&
              _detectedTextBlocks!.isEmpty &&
              _errorMessage == null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Center(child: _buildNoTextMessage()),
            ),
        ],
      ),
    );
  }

  Widget _buildEditorHint() {
    return Positioned(
      bottom: 36,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CupertinoColors.activeBlue.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              widget.strings.selectionHint,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleEditorHint(List<TextBlock> blocks) {
    _editorHintTimer?.cancel();
    if (!mounted) {
      return;
    }

    if (blocks.isEmpty) {
      if (_showEditorHint) {
        setState(() {
          _showEditorHint = false;
        });
      }
      return;
    }

    setState(() {
      _showEditorHint = true;
    });

    _editorHintTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showEditorHint = false;
      });
    });
  }

  void _dismissEditorHint() {
    if (!_showEditorHint) {
      return;
    }
    _editorHintTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _showEditorHint = false;
    });
  }

  Widget _buildImageLayer() {
    final imageFile = _imageFile;
    final textBlocks = _detectedTextBlocks;
    if (imageFile == null || textBlocks == null) {
      return const SizedBox.shrink();
    }
    if (widget.overlayOnly && _imageSize == null) {
      return const SizedBox.shrink();
    }

    final TextSelectionThemeData baseSelectionTheme = TextSelectionTheme.of(
      context,
    );
    final TextSelectionThemeData overlaySelectionTheme = baseSelectionTheme
        .copyWith(
          selectionColor: _entePrimaryColor.withValues(
            alpha: _enteSelectionHighlightOpacity,
          ),
          selectionHandleColor: _entePrimaryColor,
        );

    final overlayWidget = TextOverlayWidget(
      imageFile: widget.overlayOnly ? null : imageFile,
      imageSize: widget.overlayOnly ? _imageSize : null,
      textBlocks: textBlocks,
      onTextBlocksSelected: widget.onTextBlocksSelected,
      onTextCopied: widget.onTextCopied,
      onSelectionStart: _dismissEditorHint,
      showUnselectedBoundaries: widget.showUnselectedBoundaries,
      enableSelectionPreview: widget.enableSelectionPreview,
      debugMode: widget.debugMode,
      controller: _textOverlayController,
      isImageZoomed: widget.isImageZoomed,
      onDoubleTapWhenZoomed: widget.onDoubleTapWhenZoomed,
      uiScale: widget.uiScale,
      uiOffset: widget.uiOffset,
      zoomedInteractionPolicy: widget.zoomedInteractionPolicy,
    );

    // In overlay-only mode, don't wrap in a Container with a color —
    // even Colors.transparent creates a hit target that blocks the
    // underlying PageView from receiving swipes.
    if (widget.overlayOnly) {
      return TextSelectionTheme(
        data: overlaySelectionTheme,
        child: overlayWidget,
      );
    }

    return Container(
      color: widget.backgroundColor,
      child: TextSelectionTheme(
        data: overlaySelectionTheme,
        child: overlayWidget,
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(radius: 10, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                widget.strings.processingOverlayMessage,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNetworkErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_download_outlined,
            color: Colors.orange.shade300,
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _isNetworkError = false;
                _modelsReady = false;
                _userAttemptedInteraction = true;
              });
              _detectText();
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(widget.strings.retryButtonLabel),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange.shade300,
              side: BorderSide(color: Colors.orange.shade300),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTextMessage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            color: Colors.white.withValues(alpha: 0.7),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            widget.strings.noTextDetected,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Manually trigger text detection
  Future<void> detectText() {
    return _detectText();
  }

  /// Get the currently detected text blocks
  List<TextBlock>? get detectedTextBlocks => _detectedTextBlocks;

  /// Check if text detection is currently processing
  bool get isProcessing => _isProcessing;

  bool _selectAllRecognizedText() {
    if (!_hasSelectableText) {
      return false;
    }
    return _textOverlayController.selectAllText();
  }

  bool get _hasActiveSelection => _textOverlayController.hasActiveSelection;

  bool _selectTextAtPosition(Offset globalPosition) {
    if (_detectedTextBlocks == null) {
      setState(() {
        _userAttemptedInteraction = true;
        _pendingSelectionPosition = globalPosition;
      });
      _notifyController();
      if (_resolvedImagePath != null && !_isProcessing) {
        unawaited(_detectText());
      }
      return false;
    }
    _textOverlayController.selectTextAtPosition(globalPosition);
    return true;
  }

  void _clearSelection() {
    _textOverlayController.clearSelection();
  }

  bool _isPointOnSelectableText(Offset globalPosition) {
    return _textOverlayController.isPointOnSelectableText(globalPosition);
  }

  bool _isPointOnInteractiveSelectionUi(Offset globalPosition) {
    return _textOverlayController.isPointOnInteractiveSelectionUi(
      globalPosition,
    );
  }

  void _notifyController() {
    widget.controller?._notifyStateChanged();
  }

  void _precacheCurrentImage() {
    final imageFile = _imageFile;
    if (imageFile == null) {
      return;
    }
    precacheImage(FileImage(imageFile), context);
  }
}

/// A subtle scanning line that sweeps top-to-bottom while OCR is running.
class _ScanLineAnimation extends StatefulWidget {
  const _ScanLineAnimation();

  @override
  State<_ScanLineAnimation> createState() => _ScanLineAnimationState();
}

class _ScanLineAnimationState extends State<_ScanLineAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ScanLinePainter(
              progress: _controller.value,
              color: _entePrimaryColor,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ScanLinePainter extends CustomPainter {
  final double progress;
  final Color color;

  _ScanLinePainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 30, size.width, 60));
    canvas.drawRect(Rect.fromLTWH(0, y - 30, size.width, 60), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
