import "dart:io";

import "package:logging/logging.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ocr/legacy_mobile_ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/machine_learning/ocr/rust_ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/vision_ocr_backend.dart";

enum OcrBackendKind { legacy, rust, vision }

class OcrService {
  OcrService({
    required bool Function() rustOcrEnabled,
    required bool isAndroid,
    required bool isIOS,
    OcrBackend Function()? createLegacyBackend,
    OcrBackend Function()? createRustBackend,
    OcrBackend Function()? createVisionBackend,
  }) : _rustOcrEnabled = rustOcrEnabled,
       _isAndroid = isAndroid,
       _isIOS = isIOS,
       _createLegacyBackend = createLegacyBackend ?? LegacyMobileOcrBackend.new,
       _createRustBackend = createRustBackend ?? RustOcrBackend.new,
       _createVisionBackend = createVisionBackend ?? VisionOcrBackend.new;

  static final instance = OcrService(
    rustOcrEnabled: () => flagService.rustOcr,
    isAndroid: Platform.isAndroid,
    isIOS: Platform.isIOS,
  );

  static final _logger = Logger("OcrService");

  final bool Function() _rustOcrEnabled;
  final bool _isAndroid;
  final bool _isIOS;
  final OcrBackend Function() _createLegacyBackend;
  final OcrBackend Function() _createRustBackend;
  final OcrBackend Function() _createVisionBackend;
  final Map<OcrBackendKind, OcrBackend> _backends = {};
  OcrBackendKind? _activeKind;

  OcrBackendKind get backendKind {
    if (!_rustOcrEnabled()) {
      return OcrBackendKind.legacy;
    }
    if (_isAndroid) {
      return OcrBackendKind.rust;
    }
    if (_isIOS) {
      return OcrBackendKind.vision;
    }
    return OcrBackendKind.legacy;
  }

  Future<ModelPreparationStatus> prepareModels({
    Set<OcrModelComponent>? components,
  }) {
    return _backend.prepareModels(
      components ?? OcrModelComponent.values.toSet(),
    );
  }

  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    _ensureImageExists(imagePath);
    return _backend.detectText(
      imagePath: imagePath,
      includeAllConfidenceScores: includeAllConfidenceScores,
      requestId: requestId,
    );
  }

  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    _ensureImageExists(imagePath);
    return _backend.detectTextRegions(
      imagePath: imagePath,
      requestId: requestId,
    );
  }

  Future<void> cancelRequest(String requestId) {
    return _backend.cancelRequest(requestId);
  }

  Future<String> ensureDisplayablePath(String imagePath) {
    return _backend.ensureDisplayablePath(imagePath);
  }

  OcrBackend get _backend {
    final kind = backendKind;
    if (kind != _activeKind) {
      _logger.info("Using the ${kind.name} OCR backend");
      _activeKind = kind;
    }
    return _backends.putIfAbsent(kind, () => _createBackend(kind));
  }

  OcrBackend _createBackend(OcrBackendKind kind) => switch (kind) {
    OcrBackendKind.legacy => _createLegacyBackend(),
    OcrBackendKind.rust => _createRustBackend(),
    OcrBackendKind.vision => _createVisionBackend(),
  };

  void _ensureImageExists(String imagePath) {
    if (!File(imagePath).existsSync()) {
      throw ArgumentError("Image file does not exist at path: $imagePath");
    }
  }
}
