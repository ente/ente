import 'dart:typed_data';

import 'package:locker/services/scanner/scanner_models.dart';

/// Seam between the scanner UI and the native processing pipeline.
///
/// Implementations own the storage of page artifacts (temp files); callers
/// own page lifecycle via [disposePage].
abstract class DocumentScannerService {
  Future<void> init();

  bool get isReady;

  /// Live document detection on an Android YUV420 preview frame.
  /// Returns the detected quad in mask space of the upright
  /// ([rotationDegrees]-applied) frame, or null when nothing is detected.
  Future<ScanQuad?> detectLiveYuv({
    required Uint8List y,
    required Uint8List u,
    required Uint8List v,
    required int yRowStride,
    required int uvRowStride,
    required int uvPixelStride,
    required int width,
    required int height,
    required int rotationDegrees,
  });

  /// Live document detection on an iOS BGRA8888 preview frame.
  Future<ScanQuad?> detectLiveBgra(
    Uint8List bytes,
    int rowStride,
    int width,
    int height,
    int rotationDegrees,
  );

  /// Detects the document in [capturedJpeg], applies perspective crop,
  /// auto color mode and enhancement at high quality.
  Future<ScannedPage> processCapture(Uint8List capturedJpeg);

  /// Re-renders [page] from its source with a manual [quad] (mask space)
  /// and/or [rotationDegrees]. Returns a page that supersedes [page]; its
  /// processedJpeg is a new file and superseded render artifacts are cleaned
  /// up by the service.
  Future<ScannedPage> updatePage(
    ScannedPage page, {
    ScanQuad? quad,
    int? rotationDegrees,
  });

  /// Deletes all files backing [page].
  Future<void> disposePage(ScannedPage page);

  Future<void> dispose();
}
