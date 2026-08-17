import 'dart:async';
import 'dart:io';

import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:mobile_ocr/mobile_ocr.dart'
    show DisplayImageHelper, MobileOcr, TextBlock;
import 'package:photos/theme/colors.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/viewer/file/ocr/text_overlay_widget.dart';

const double _enteSelectionHighlightOpacity = 0.28;

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

  bool get isProcessing => _state?._isProcessing ?? false;
  bool get hasSelectableText => _state?._hasSelectableText ?? false;
  bool get userAttemptedInteraction =>
      _state?._userAttemptedInteraction ?? false;

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

class TextDetectorWidget extends StatefulWidget {
  final String imagePath;
  final VoidCallback? onTextCopied;
  final TextDetectorController controller;
  final Offset? initialInteractionPosition;
  final bool isImageZoomed;
  final double uiScale;
  final Offset uiOffset;

  const TextDetectorWidget({
    super.key,
    required this.imagePath,
    required this.controller,
    required this.isImageZoomed,
    required this.uiScale,
    required this.uiOffset,
    this.onTextCopied,
    this.initialInteractionPosition,
  });

  @override
  State<TextDetectorWidget> createState() => _TextDetectorWidgetState();
}

class _TextDetectorWidgetState extends State<TextDetectorWidget> {
  final MobileOcr _ocr = MobileOcr();
  final TextOverlayController _textOverlayController = TextOverlayController();
  List<TextBlock>? _detectedTextBlocks;
  bool _isProcessing = false;
  String? _resolvedImagePath;
  Future<void>? _imagePreparation;
  bool _modelsReady = false;
  Future<void>? _modelPreparation;
  String? _errorMessage;
  bool _isNetworkError = false;
  Size? _imageSize;
  bool _userAttemptedInteraction = false;
  Offset? _pendingSelectionPosition;
  int _detectionRequestSequence = 0;
  String? _activeDetectionRequestId;
  bool get _hasSelectableText =>
      _detectedTextBlocks != null && _detectedTextBlocks!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _isProcessing = true;
    if (widget.initialInteractionPosition != null) {
      _userAttemptedInteraction = true;
      _pendingSelectionPosition = widget.initialInteractionPosition;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initializeFile());
    });
  }

  @override
  void dispose() {
    _cancelActiveDetection();
    widget.controller._detach(this);
    super.dispose();
  }

  Future<void> _initializeFile() async {
    final requestedPath = widget.imagePath;

    final preparation = _prepareDisplayImage(requestedPath);
    _imagePreparation = preparation;
    await preparation;
    if (_imagePreparation == preparation) {
      _imagePreparation = null;
    }
  }

  Future<void> _prepareDisplayImage(String requestedPath) async {
    setState(() {
      _resolvedImagePath = null;
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
        _resolvedImagePath = resolvedPath;
      });
      unawaited(_detectText());
    } catch (error) {
      debugPrint('Failed to prepare image $requestedPath: $error');
      if (!mounted || widget.imagePath != requestedPath) {
        return;
      }
      setState(() {
        _resolvedImagePath = null;
        _errorMessage = context.strings.ocrImageDecodeFailedError;
        _isProcessing = false;
      });
    }
  }

  void _cancelActiveDetection() {
    final requestId = _activeDetectionRequestId;
    _activeDetectionRequestId = null;
    if (requestId != null) {
      unawaited(_ocr.cancelRequest(requestId).catchError((_) {}));
    }
  }

  Future<void> _ensureModelsReady() async {
    if (_modelsReady) return;

    // Captured before the async gap; the callback may run after dispose.
    final strings = context.strings;
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
            _errorMessage = strings.ocrModelsNetworkRequiredError;
          } else {
            _errorMessage = strings.ocrModelsPrepareFailed;
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
        _errorMessage = context.strings.ocrImageDecodeFailedError;
        _isProcessing = false;
      });
      _notifyController();
      return;
    }

    if (!_isProcessing) {
      setState(() {
        _isProcessing = true;
        _detectedTextBlocks = null;
        _errorMessage = null;
        _isNetworkError = false;
      });
      _notifyController();
    }

    String? nativeRequestId;
    try {
      await _ensureModelsReady();
      if (_errorMessage != null) {
        return;
      }

      if (!mounted || widget.imagePath != requestedPath) {
        return;
      }

      final requestId =
          'text-detector-${identityHashCode(this)}-${++_detectionRequestSequence}';
      nativeRequestId = requestId;
      _activeDetectionRequestId = requestId;
      final result = await _ocr.detectText(
        imagePath: imagePath,
        requestId: requestId,
      );
      if (mounted && widget.imagePath == requestedPath) {
        final pendingPos = _pendingSelectionPosition;
        setState(() {
          _detectedTextBlocks = result.blocks;
          _imageSize = result.imageSize;
          _errorMessage = null;
          _pendingSelectionPosition = null;
        });
        _notifyController();

        if (pendingPos != null && (_detectedTextBlocks?.isNotEmpty ?? false)) {
          _textOverlayController.selectTextAtPosition(pendingPos);
        }
      }
    } catch (e) {
      debugPrint('Error detecting text: $e');
      if (mounted && widget.imagePath == requestedPath) {
        setState(() {
          final errorStr = e.toString().toLowerCase();
          if (errorStr.contains('image') &&
              errorStr.contains('not') &&
              errorStr.contains('exist')) {
            _errorMessage = context.strings.ocrImageNotFoundError;
          } else if (errorStr.contains('failed to decode')) {
            _errorMessage = context.strings.ocrImageDecodeFailedError;
          } else {
            _errorMessage = context.strings.ocrGenericDetectError;
          }
        });
        _notifyController();
      }
    } finally {
      if (_activeDetectionRequestId == nativeRequestId) {
        _activeDetectionRequestId = null;
      }
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

    if (!_isProcessing) {
      unawaited(_detectText());
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPressStart: _hasSelectableText ? null : _handleLongPressStart,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildImageLayer(),
          if (_errorMessage != null)
            Positioned(
              bottom: 32,
              left: 16,
              right: 16,
              child: _isNetworkError
                  ? _buildNetworkErrorBanner(_errorMessage!)
                  : _buildErrorBanner(_errorMessage!),
            ),
          if (_userAttemptedInteraction &&
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

  Widget _buildImageLayer() {
    final textBlocks = _detectedTextBlocks;
    final imageSize = _imageSize;
    if (textBlocks == null || imageSize == null) {
      return const SizedBox.shrink();
    }

    final TextSelectionThemeData baseSelectionTheme = TextSelectionTheme.of(
      context,
    );
    final Color primaryColor = getEnteColorScheme(context).primary500;
    final TextSelectionThemeData overlaySelectionTheme = baseSelectionTheme
        .copyWith(
          selectionColor: primaryColor.withValues(
            alpha: _enteSelectionHighlightOpacity,
          ),
          selectionHandleColor: primaryColor,
        );

    return TextSelectionTheme(
      data: overlaySelectionTheme,
      child: TextOverlayWidget(
        imageSize: imageSize,
        textBlocks: textBlocks,
        onTextCopied: widget.onTextCopied,
        controller: _textOverlayController,
        isImageZoomed: widget.isImageZoomed,
        uiScale: widget.uiScale,
        uiOffset: widget.uiOffset,
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: getEnteColorScheme(context).warning500.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: getEnteTextTheme(
          context,
        ).smallBold.copyWith(color: textBaseDark),
      ),
    );
  }

  Widget _buildNetworkErrorBanner(String message) {
    final Color cautionColor = getEnteColorScheme(context).caution500;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cautionColor.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cautionColor.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_download_outlined, color: cautionColor, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: getEnteTextTheme(
              context,
            ).small.copyWith(color: textBaseDark),
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
              unawaited(_detectText());
            },
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(context.strings.retry),
            style: OutlinedButton.styleFrom(
              foregroundColor: cautionColor,
              side: BorderSide(color: cautionColor),
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
            color: textBaseDark.withValues(alpha: 0.7),
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            context.strings.ocrNoTextDetected,
            style: getEnteTextTheme(
              context,
            ).small.copyWith(color: textBaseDark.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
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
    widget.controller._notifyStateChanged();
  }
}
