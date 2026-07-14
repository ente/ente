import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:mobile_ocr/mobile_ocr.dart" show MobileOcr;
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file/trash_file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/text_detection_page.dart";
import "package:photos/utils/dialog_util.dart";

class TextDetectionOverlayButton extends StatefulWidget {
  final EnteFile file;
  final ValueListenable<bool> enableFullScreenNotifier;
  final bool isGuestView;

  const TextDetectionOverlayButton({
    required this.file,
    required this.enableFullScreenNotifier,
    required this.isGuestView,
    super.key,
  });

  @override
  State<TextDetectionOverlayButton> createState() =>
      _TextDetectionOverlayButtonState();
}

class _TextDetectionOverlayButtonState
    extends State<TextDetectionOverlayButton> {
  static final Map<String, _DetectionResult> _cache = {};
  final Logger _logger = Logger("TextDetectionOverlayButton");
  final MobileOcr _mobileOcr = MobileOcr();

  bool _isEligible = false;
  bool _hasText = false;
  bool _isChecking = false;
  String? _localFilePath;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _evaluateFile();
  }

  @override
  void didUpdateWidget(covariant TextDetectionOverlayButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_didFileChange(oldWidget.file, widget.file)) {
      _evaluateFile();
    }
  }

  bool _didFileChange(EnteFile oldFile, EnteFile newFile) {
    if (oldFile.generatedID != newFile.generatedID) {
      return true;
    }
    if (oldFile.uploadedFileID != newFile.uploadedFileID) {
      return true;
    }
    if (oldFile.localID != newFile.localID) {
      return true;
    }
    return false;
  }

  Future<void> _evaluateFile() async {
    final bool isEligible = _isFileEligible(widget.file);
    final int requestId = ++_requestId;

    if (!isEligible) {
      setState(() {
        _isEligible = false;
        _hasText = false;
        _localFilePath = null;
        _isChecking = false;
      });
      return;
    }

    final String cacheKey = _cacheKey(widget.file);
    final _DetectionResult? cachedResult = _cache[cacheKey];
    if (cachedResult != null) {
      if (!mounted || requestId != _requestId) {
        return;
      }
      setState(() {
        _isEligible = true;
        _hasText = cachedResult.hasText;
        _localFilePath = cachedResult.localPath;
        _isChecking = false;
      });
      return;
    }

    setState(() {
      _isEligible = true;
      _hasText = false;
      _localFilePath = null;
      _isChecking = true;
    });

    try {
      final File? localFile = await getFile(widget.file);
      if (!mounted || requestId != _requestId) {
        return;
      }
      if (localFile == null || !localFile.existsSync()) {
        _cache[cacheKey] = const _DetectionResult(hasText: false);
        setState(() {
          _hasText = false;
          _localFilePath = null;
          _isChecking = false;
        });
        return;
      }

      bool hasText = false;
      try {
        hasText = await _mobileOcr.hasText(imagePath: localFile.path);
      } catch (error, stackTrace) {
        _logger.severe("Failed to run hasText", error, stackTrace);
      }

      if (!mounted || requestId != _requestId) {
        return;
      }

      final _DetectionResult result = _DetectionResult(
        hasText: hasText,
        localPath: hasText ? localFile.path : null,
      );
      _cache[cacheKey] = result;
      setState(() {
        _hasText = result.hasText;
        _localFilePath = result.localPath;
        _isChecking = false;
      });
    } catch (error, stackTrace) {
      _logger.severe("Text detection pre-check failed", error, stackTrace);
      if (!mounted || requestId != _requestId) {
        return;
      }
      _cache[cacheKey] = const _DetectionResult(hasText: false);
      setState(() {
        _hasText = false;
        _localFilePath = null;
        _isChecking = false;
      });
    }
  }

  bool _isFileEligible(EnteFile file) {
    return file.fileType == FileType.image ||
        file.fileType == FileType.livePhoto;
  }

  String _cacheKey(EnteFile file) {
    if (file.uploadedFileID != null) {
      return "uploaded_${file.uploadedFileID}";
    }
    if (file.localID != null) {
      return "local_${file.localID}";
    }
    return "generated_${file.generatedID}";
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEligible || _isChecking || !_hasText) {
      return const SizedBox.shrink();
    }

    return ValueListenableBuilder<bool>(
      valueListenable: widget.enableFullScreenNotifier,
      builder: (context, isFullScreen, _) {
        final bool shouldHide =
            isFullScreen || widget.isGuestView || widget.file is TrashFile;
        if (shouldHide) {
          return const SizedBox.shrink();
        }

        double bottomOffset = MediaQuery.paddingOf(context).bottom + 72.0;

        final caption = widget.file.caption;
        if (caption != null && caption.trim().isNotEmpty) {
          // 1. Configure the text engine with a 3-line maximum
          final textPainter = TextPainter(
            text: TextSpan(
              text: caption.trim(),
              style: getEnteTextTheme(context).mini,
            ),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 3,
          );

          // 2. Measure against the available screen width
          final double maxWidth = MediaQuery.sizeOf(context).width - 16.0;
          textPainter.layout(maxWidth: maxWidth);

          // 3. Add the exact calculated text height (capped at 3 lines) + 24px safe padding buffer
          bottomOffset += textPainter.height + 24.0;
        }

        return Positioned(
          bottom: bottomOffset,
          left: 0,
          right: 0,
          child: Center(
            child: GestureDetector(
              onTap: _onPressed,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(160),
                  borderRadius: BorderRadius.circular(60),
                  border: Border.all(
                    color: Colors.white.withAlpha(60),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: getEnteColorScheme(context).primary700,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Select text",
                      style: getEnteTextTheme(
                        context,
                      ).mini.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onPressed() async {
    try {
      final String? path = _localFilePath ?? await _ensureLocalFilePath();
      if (path == null) {
        throw Exception("Failed to resolve file path for text detection");
      }
      if (!mounted) {
        return;
      }
      await routeToPage(
        context,
        TextDetectionPage(file: widget.file, imagePath: path),
      );
    } catch (error, stackTrace) {
      _logger.severe("Failed to start text detection", error, stackTrace);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: error);
      }
    }
  }

  Future<String?> _ensureLocalFilePath() async {
    final File? localFile = await getFile(widget.file);
    if (localFile == null || !localFile.existsSync()) {
      return null;
    }
    return localFile.path;
  }
}

class _DetectionResult {
  final bool hasText;
  final String? localPath;

  const _DetectionResult({required this.hasText, this.localPath});
}
