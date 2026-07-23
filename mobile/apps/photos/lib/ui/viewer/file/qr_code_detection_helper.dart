import "dart:async";
import "dart:io";

import "package:ente_qr/ente_qr.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/module/download/file.dart";

class QrCodeDetectionHelper {
  static const _debounceDuration = Duration(milliseconds: 500);
  final Logger _logger = Logger("QrCodeDetectionHelper");
  final EnteQr _enteQr = EnteQr();

  final ValueNotifier<List<QrDetection>> qrDetectionsNotifier =
      ValueNotifier<List<QrDetection>>(const []);

  int _requestId = 0;
  bool _disposed = false;
  Timer? _debounceTimer;

  Future<void> evaluateFile(EnteFile file) async {
    _debounceTimer?.cancel();

    final bool isEligible = _isFileEligible(file);
    final int requestId = ++_requestId;

    if (!isEligible) {
      _clearDetections();
      return;
    }

    _clearDetections();

    _debounceTimer = Timer(_debounceDuration, () {
      _scanFile(file, requestId);
    });
  }

  Future<void> _scanFile(EnteFile file, int requestId) async {
    if (_disposed || requestId != _requestId) return;

    try {
      final stopwatch = Stopwatch()..start();
      final File? localFile = await getFile(file);
      if (_disposed || requestId != _requestId) return;
      if (localFile == null || !localFile.existsSync()) {
        _clearDetections();
        return;
      }
      final getFileMs = stopwatch.elapsedMilliseconds;

      List<QrDetection> detections = const [];
      try {
        final result = await _enteQr.scanAllQrFromImage(localFile.path);
        if (result.success && result.detections.isNotEmpty) {
          detections = result.detections;
        }
      } catch (error, stackTrace) {
        _logger.severe("Failed to scan QR codes", error, stackTrace);
      }

      final totalMs = stopwatch.elapsedMilliseconds;
      _logger.info(
        "QR scan: getFile=${getFileMs}ms, "
        "detect=${totalMs - getFileMs}ms, "
        "total=${totalMs}ms, "
        "found=${detections.length}",
      );

      if (_disposed || requestId != _requestId) return;

      qrDetectionsNotifier.value = detections;
    } catch (error, stackTrace) {
      _logger.severe("QR code detection failed", error, stackTrace);
      if (_disposed || requestId != _requestId) return;
      _clearDetections();
    }
  }

  /// Only notify listeners when the value actually changes.
  void _clearDetections() {
    if (qrDetectionsNotifier.value.isNotEmpty) {
      qrDetectionsNotifier.value = const [];
    }
  }

  bool _isFileEligible(EnteFile file) {
    return file.fileType == FileType.image ||
        file.fileType == FileType.livePhoto;
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    qrDetectionsNotifier.dispose();
  }
}
