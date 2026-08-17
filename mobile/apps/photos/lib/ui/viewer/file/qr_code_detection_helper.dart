import "dart:async";
import "dart:io";

import "package:ente_qr/ente_qr.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";

class QrCodeDetectionResult {
  final String fileTag;
  final List<QrDetection> detections;

  const QrCodeDetectionResult(this.fileTag, this.detections);

  List<QrDetection> forFile(EnteFile file) =>
      file.tag == fileTag ? detections : const [];
}

class QrCodeDetectionHelper {
  static const _debounceDuration = Duration(milliseconds: 500);
  final Logger _logger = Logger("QrCodeDetectionHelper");
  final EnteQr _enteQr = EnteQr();

  final ValueNotifier<QrCodeDetectionResult?> qrDetectionsNotifier =
      ValueNotifier<QrCodeDetectionResult?>(null);

  int _requestId = 0;
  bool _disposed = false;
  Timer? _debounceTimer;

  void evaluateFile(EnteFile file, File? localFile) {
    _debounceTimer?.cancel();

    final int requestId = ++_requestId;
    if (!_isFileEligible(file) || localFile == null) {
      _clearDetections();
      return;
    }

    _clearDetections();

    _debounceTimer = Timer(_debounceDuration, () {
      _scanFile(file, localFile, requestId);
    });
  }

  Future<void> _scanFile(EnteFile file, File localFile, int requestId) async {
    if (_disposed || requestId != _requestId) return;

    try {
      final stopwatch = Stopwatch()..start();
      if (!localFile.existsSync()) {
        _clearDetections();
        return;
      }

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
        "QR scan: detect=${totalMs}ms, "
        "found=${detections.length}",
      );

      if (_disposed || requestId != _requestId) return;

      qrDetectionsNotifier.value = QrCodeDetectionResult(file.tag, detections);
    } catch (error, stackTrace) {
      _logger.severe("QR code detection failed", error, stackTrace);
      if (_disposed || requestId != _requestId) return;
      _clearDetections();
    }
  }

  void _clearDetections() {
    if (qrDetectionsNotifier.value != null) {
      qrDetectionsNotifier.value = null;
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
