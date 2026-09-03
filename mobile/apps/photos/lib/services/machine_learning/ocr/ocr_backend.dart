import "package:photos/services/machine_learning/ocr/ocr_models.dart";

abstract class OcrBackend {
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  );

  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  });

  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  });

  Future<void> cancelRequest(String requestId);

  Future<String> ensureDisplayablePath(String imagePath);
}
