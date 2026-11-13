import "package:ente_vision/ente_vision.dart";
import "package:flutter/services.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";

class VisionOcrBackend implements OcrBackend {
  VisionOcrBackend({VisionTextRecognizer? recognizer})
    : _recognizer = recognizer ?? VisionTextRecognizer.instance;

  static const _status = ModelPreparationStatus(
    isReady: true,
    version: "iOS-Vision",
    modelPath: "system",
  );

  final VisionTextRecognizer _recognizer;

  @override
  Future<void> unloadModels() async {}

  @override
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  ) async {
    return _status;
  }

  @override
  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
  }) {
    return _translate(() async {
      final result = await _recognizer.detectText(
        imagePath: imagePath,
        includeAllConfidenceScores: includeAllConfidenceScores,
      );
      return TextDetectionResult.fromMap(result);
    });
  }

  @override
  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
  }) {
    return _translate(() async {
      final result = await _recognizer.detectTextRegions(imagePath: imagePath);
      return TextRegionDetectionResult.fromMap(result);
    });
  }

  @override
  Future<String> ensureDisplayablePath(String imagePath) async {
    return imagePath;
  }

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on PlatformException catch (error) {
      throw OcrException(
        code: error.code,
        message: error.message ?? "OCR operation failed",
        details: error.details,
      );
    }
  }
}
