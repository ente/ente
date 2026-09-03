import "package:mobile_ocr/mobile_ocr.dart" as legacy;
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";

class LegacyMobileOcrBackend implements OcrBackend {
  final legacy.MobileOcr _ocr = legacy.MobileOcr();

  @override
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  ) {
    return _translate(() async {
      final status = await _ocr.prepareModels(
        components: components
            .map(
              (component) =>
                  legacy.OcrModelComponent.values.byName(component.name),
            )
            .toSet(),
      );
      return ModelPreparationStatus(
        isReady: status.isReady,
        version: status.version,
        modelPath: status.modelPath,
      );
    });
  }

  @override
  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) {
    return _translate(() async {
      final result = await _ocr.detectText(
        imagePath: imagePath,
        includeAllConfidenceScores: includeAllConfidenceScores,
        requestId: requestId,
      );
      return TextDetectionResult(
        blocks: result.blocks.map(_toTextBlock).toList(growable: false),
        imageSize: result.imageSize,
      );
    });
  }

  @override
  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) {
    return _translate(() async {
      final result = await _ocr.detectTextRegions(
        imagePath: imagePath,
        requestId: requestId,
      );
      return TextRegionDetectionResult(
        regions: result.regions.map(_toTextRegion).toList(growable: false),
        imageSize: result.imageSize,
      );
    });
  }

  @override
  Future<void> cancelRequest(String requestId) {
    return _translate(() => _ocr.cancelRequest(requestId));
  }

  @override
  Future<String> ensureDisplayablePath(String imagePath) {
    return legacy.DisplayImageHelper.ensureDisplayablePath(imagePath);
  }

  Future<T> _translate<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on legacy.OcrException catch (error) {
      throw OcrException(
        code: error.code,
        message: error.message,
        details: error.details,
      );
    }
  }

  TextBlock _toTextBlock(legacy.TextBlock block) => TextBlock(
    text: block.text,
    confidence: block.confidence,
    points: block.points,
    characters: block.characters.map(_toCharacterBox).toList(growable: false),
  );

  CharacterBox _toCharacterBox(legacy.CharacterBox character) => CharacterBox(
    text: character.text,
    confidence: character.confidence,
    points: character.points,
  );

  TextRegion _toTextRegion(legacy.TextRegion region) =>
      TextRegion(confidence: region.confidence, points: region.points);
}
