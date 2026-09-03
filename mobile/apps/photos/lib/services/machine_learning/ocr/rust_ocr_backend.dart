import "dart:convert";
import "dart:io";
import "dart:ui";

import "package:crypto/crypto.dart";
import "package:logging/logging.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/src/rust/api/image_processing_api.dart"
    show decodeToJpeg;
import "package:photos/src/rust/api/ocr_api.dart";
import "package:synchronized/synchronized.dart";

class RustOcrBackend implements OcrBackend {
  static final _logger = Logger("RustOcrBackend");
  static const _modelVersion = "pp-ocrv5";
  static const _transcodableExtensions = {"heic", "heif", "heics", "avif"};
  static const _displayCacheDirectoryName = "ocr_display";
  static const _displayCacheMaxEntries = 32;
  static const _displayCacheMaxBytes = 256 * 1024 * 1024;
  static const _displayJpegQuality = 95;
  static const _noModelPaths = RustOcrModelPaths(
    detection: "",
    classification: "",
    recognition: "",
    dictionary: "",
  );

  final _engineLock = Lock();
  OcrEngine? _engine;
  RustOcrModelPaths _enginePaths = _noModelPaths;
  final Map<String, String> _displayCache = {};
  final Map<String, Future<String>> _displayInFlight = {};

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
    final engine = _requireEngine();
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
    final engine = _requireEngine();
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
    if (!_needsTranscode(imagePath)) {
      return Future.value(imagePath);
    }
    final inFlight = _displayInFlight[imagePath];
    if (inFlight != null) {
      return inFlight;
    }
    final future = _displayablePath(imagePath).whenComplete(() {
      _displayInFlight.remove(imagePath);
    });
    _displayInFlight[imagePath] = future;
    return future;
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

  bool _needsTranscode(String imagePath) {
    final extension = p.extension(imagePath).toLowerCase();
    return extension.isNotEmpty &&
        _transcodableExtensions.contains(extension.substring(1));
  }

  Future<String> _displayablePath(String imagePath) async {
    try {
      final stat = await File(imagePath).stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return imagePath;
      }
      final cacheDirectory = Directory(
        p.join(
          (await getTemporaryDirectory()).path,
          _displayCacheDirectoryName,
        ),
      );
      final cacheFile = File(
        p.join(cacheDirectory.path, "${_displayCacheKey(imagePath, stat)}.jpg"),
      );
      final cached = _displayCache.remove(imagePath);
      if (cached == cacheFile.path && await cacheFile.exists()) {
        _displayCache[imagePath] = cached!;
        await cacheFile.setLastModified(DateTime.now());
        return cached;
      }
      await cacheDirectory.create(recursive: true);
      final jpeg = await decodeToJpeg(
        imagePath: imagePath,
        quality: _displayJpegQuality,
      );
      await cacheFile.writeAsBytes(jpeg, flush: true);
      _displayCache[imagePath] = cacheFile.path;
      if (_displayCache.length > _displayCacheMaxEntries) {
        _displayCache.remove(_displayCache.keys.first);
      }
      await _trimDisplayCache(cacheDirectory);
      return cacheFile.path;
    } catch (e, s) {
      _logger.warning("Could not transcode $imagePath for display", e, s);
      return imagePath;
    }
  }

  String _displayCacheKey(String imagePath, FileStat stat) {
    final modified = stat.modified.millisecondsSinceEpoch;
    return md5
        .convert(utf8.encode("$imagePath:$modified:${stat.size}"))
        .toString();
  }

  Future<void> _trimDisplayCache(Directory cacheDirectory) async {
    final files = <(File, FileStat)>[];
    await for (final entity in cacheDirectory.list()) {
      if (entity is File) {
        files.add((entity, await entity.stat()));
      }
    }
    files.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
    var retainedBytes = 0;
    for (final (index, (file, stat)) in files.indexed) {
      final retain =
          index < _displayCacheMaxEntries &&
          retainedBytes + stat.size <= _displayCacheMaxBytes;
      if (retain) {
        retainedBytes += stat.size;
      } else {
        await file.delete();
      }
    }
    _displayCache.removeWhere(
      (_, cachedPath) => !File(cachedPath).existsSync(),
    );
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
