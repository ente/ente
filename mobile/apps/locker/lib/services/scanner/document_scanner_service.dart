import 'dart:typed_data';

import 'package:locker/services/scanner/scanner_models.dart';

abstract class DocumentScannerService {
  Future<void> init();

  bool get isReady;

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

  Future<ScanQuad?> detectLiveBgra(
    Uint8List bytes,
    int rowStride,
    int width,
    int height,
    int rotationDegrees,
  );

  Future<ScannedPage> processCapture(Uint8List capturedJpeg);

  Future<ScannedPage> updatePage(
    ScannedPage page, {
    ScanQuad? quad,
    int? rotationDegrees,
  });

  Future<void> disposePage(ScannedPage page);

  Future<void> dispose();
}
