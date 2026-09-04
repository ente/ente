import "dart:io";
import "dart:ui";

import "package:logging/logging.dart";
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/src/rust/api/ocr_api.dart";
import "package:synchronized/synchronized.dart";

class RustOcrBackend implements OcrBackend {
  static final _logger = Logger("RustOcrBackend");
  static const _modelVersion = "pp-ocrv5";
  static const _noModelPaths = RustOcrModelPaths(
    detection: "",
    classification: "",
    recognition: "",
    dictionary: "",
  );

  final _engineLock = Lock();
  OcrEngine? _engine;
  RustOcrModelPaths _enginePaths = _noModelPaths;

  @override
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  ) {
    return _engineLock.synchronized(() async {
      final paths = await _downloadModels(
        includeRecognizer: components.contains(OcrModelComponent.recognizer),
      );
      await _ensureEngine(paths);
      return ModelPreparationStatus(
        isReady: true,
        version: _modelVersion,
        modelPath: File(paths.detection).parent.path,
      );
    });
  }

  Future<RustOcrModelPaths> _downloadModels({
    required bool includeRecognizer,
  }) async {
    if (!includeRecognizer) {
      final detection = await OcrDetectionModel.instance.downloadModel();
      return RustOcrModelPaths(
        detection: detection,
        classification: _enginePaths.classification,
        recognition: _enginePaths.recognition,
        dictionary: _enginePaths.dictionary,
      );
    }
    final paths = await Future.wait([
      OcrDetectionModel.instance.downloadModel(),
      OcrClassificationModel.instance.downloadModel(),
      OcrRecognitionModel.instance.downloadModel(),
      OcrDictionaryAsset.instance.downloadModel(),
    ]);
    return RustOcrModelPaths(
      detection: paths[0],
      classification: paths[1],
      recognition: paths[2],
      dictionary: paths[3],
    );
  }

  Future<void> _ensureEngine(RustOcrModelPaths paths) async {
    if (_engine != null && paths == _enginePaths) {
      return;
    }
    try {
      _engine = await OcrEngine.create(paths: paths);
      _enginePaths = paths;
      final loadedModels = paths.recognition.isEmpty
          ? "detector only"
          : "detector, classifier and recognizer";
      _logger.info("Created Rust OCR engine ($loadedModels)");
    } on RustOcrError catch (error) {
      _logger.severe("Could not create the Rust OCR engine: $error");
      throw OcrException(
        code: "MODEL_PREP_ERROR",
        message: _rustOcrErrorMessage(error),
        details: error,
      );
    }
  }

  @override
  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    final engine = await _recognitionEngine();
    try {
      final result = await engine.detectText(
        imagePath: imagePath,
        includeAllConfidenceScores: includeAllConfidenceScores,
        requestId: requestId,
      );
      return textDetectionResultFromRust(result);
    } on RustOcrError catch (error) {
      throw _failure(
        error,
        imagePath: imagePath,
        otherCode: "RECOGNITION_ERROR",
      );
    }
  }

  @override
  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    final engine = await _detectionEngine();
    try {
      final result = await engine.detectTextRegions(
        imagePath: imagePath,
        requestId: requestId,
      );
      return textRegionDetectionResultFromRust(result);
    } on RustOcrError catch (error) {
      throw _failure(error, imagePath: imagePath, otherCode: "DETECTION_ERROR");
    }
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    _engine?.cancel(requestId: requestId);
  }

  @override
  Future<String> ensureDisplayablePath(String imagePath) {
    return Future.value(imagePath);
  }

  Future<OcrEngine> _recognitionEngine() async {
    final engine = _engine;
    if (engine != null && _enginePaths.recognition.isNotEmpty) {
      return engine;
    }
    await prepareModels(OcrModelComponent.values.toSet());
    return _requireEngine();
  }

  Future<OcrEngine> _detectionEngine() async {
    final engine = _engine;
    if (engine != null) {
      return engine;
    }
    final detectorAvailable = await RemoteAssetsService.instance.hasAsset(
      OcrDetectionModel.instance.modelRemotePath,
    );
    if (!detectorAvailable) {
      throw const OcrException(
        code: "MODEL_NOT_READY",
        message: "The OCR detector model is not available locally",
      );
    }
    await prepareModels({OcrModelComponent.detector});
    return _requireEngine();
  }

  OcrEngine _requireEngine() {
    final engine = _engine;
    if (engine == null) {
      throw const OcrException(
        code: "MODEL_NOT_READY",
        message: "OCR models have not been prepared",
      );
    }
    return engine;
  }

  OcrException _failure(
    RustOcrError error, {
    required String imagePath,
    required String otherCode,
  }) {
    final exception = ocrExceptionFromRustError(
      error,
      imagePath: imagePath,
      otherCode: otherCode,
    );
    if (error is RustOcrError_CorruptModel) {
      _logger.severe("Rust OCR reported a corrupt model: ${error.message}");
    } else {
      _logger.warning("Rust OCR failed: $exception");
    }
    return exception;
  }
}

TextDetectionResult textDetectionResultFromRust(
  RustTextDetectionResult result,
) {
  return TextDetectionResult(
    blocks: result.blocks
        .map(
          (block) => TextBlock(
            text: block.text,
            confidence: block.confidence,
            points: _offsetsFromRust(block.points),
            characters: block.characters
                .map(
                  (character) => CharacterBox(
                    text: character.text,
                    confidence: character.confidence,
                    points: _offsetsFromRust(character.points),
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false),
    imageSize: Size(
      result.imageWidth.toDouble(),
      result.imageHeight.toDouble(),
    ),
  );
}

TextRegionDetectionResult textRegionDetectionResultFromRust(
  RustTextRegionDetectionResult result,
) {
  return TextRegionDetectionResult(
    regions: result.regions
        .map(
          (region) => TextRegion(
            confidence: region.confidence,
            points: _offsetsFromRust(region.points),
          ),
        )
        .toList(growable: false),
    imageSize: Size(
      result.imageWidth.toDouble(),
      result.imageHeight.toDouble(),
    ),
  );
}

OcrException ocrExceptionFromRustError(
  RustOcrError error, {
  required String imagePath,
  required String otherCode,
}) {
  final message = _rustOcrErrorMessage(error);
  return switch (error) {
    RustOcrError_ImageNotFound() => OcrException(
      code: "IMAGE_NOT_FOUND",
      message: "Image file does not exist at path: $imagePath",
      details: message,
    ),
    RustOcrError_InvalidImage() => OcrException(
      code: "IMAGE_DECODE_ERROR",
      message: "Failed to decode image: $message",
    ),
    RustOcrError_Cancelled() => OcrException(
      code: "CANCELLED",
      message: message,
    ),
    RustOcrError_CorruptModel() => OcrException(
      code: "MODEL_PREP_ERROR",
      message: message,
    ),
    RustOcrError_Other() => OcrException(code: otherCode, message: message),
  };
}

String _rustOcrErrorMessage(RustOcrError error) => switch (error) {
  RustOcrError_Cancelled() => "OCR request was cancelled",
  RustOcrError_ImageNotFound(:final message) ||
  RustOcrError_InvalidImage(:final message) ||
  RustOcrError_CorruptModel(:final message) ||
  RustOcrError_Other(:final message) => message,
};

List<Offset> _offsetsFromRust(List<RustOcrPoint> points) =>
    points.map((point) => Offset(point.x, point.y)).toList(growable: false);
