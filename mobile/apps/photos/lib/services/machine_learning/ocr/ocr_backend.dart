import "package:photos/services/machine_learning/ocr/ocr_models.dart";

abstract class OcrBackend {
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  );

  Future<void> unloadModels();

  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
  });

  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
  });

  Future<String> ensureDisplayablePath(String imagePath);
}
