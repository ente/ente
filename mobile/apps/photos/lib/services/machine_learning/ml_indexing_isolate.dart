import "dart:async";
import "dart:io" show Platform;

import "package:flutter/foundation.dart" show kDebugMode;
import "package:logging/logging.dart";
import "package:photos/service_locator.dart"
    show flagService, isLocalGalleryMode, localSettings;
import 'package:photos/services/machine_learning/face_ml/face_detection/face_detection_service.dart';
import 'package:photos/services/machine_learning/face_ml/face_embedding/face_embedding_service.dart';
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_models_overview.dart";
import 'package:photos/services/machine_learning/ml_result.dart';
import "package:photos/services/machine_learning/pet_ml/pet_model_services.dart";
import "package:photos/services/machine_learning/semantic_search/clip/clip_image_encoder.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/isolate/super_isolate.dart";
import "package:photos/utils/ml_util.dart";
import "package:synchronized/synchronized.dart";

@pragma('vm:entry-point')
class MLIndexingIsolate extends SuperIsolate {
  @override
  Logger get logger => _logger;
  final _logger = Logger("MLIndexingIsolate");

  @override
  bool get isDartUiIsolate => !_shouldUseRustMl;

  @override
  String get isolateName => "MLIndexingIsolate";

  @override
  bool get shouldAutomaticDispose => true;

  bool get _shouldUseRustMl => flagService.useRustForML || isLocalGalleryMode;

  int _loadedModelsCount = 0;
  int _deloadedModelsCount = 0;

  final _initModelLock = Lock();
  final _rustRuntimeLock = Lock();

  Map<String, dynamic>? _cachedRustRuntimeArgs;

  @override
  Future<void> onDispose() async {
    await releaseRustRuntime();
    await _releaseModels();
  }

  @override
  bool postFunctionlockStop(IsolateOperation operation) {
    if (operation == IsolateOperation.analyzeImage &&
        shouldPauseIndexingAndClustering) {
      return true;
    }
    return false;
  }

  bool shouldPauseIndexingAndClustering = false;

  // Singleton pattern
  MLIndexingIsolate._privateConstructor();
  static final instance = MLIndexingIsolate._privateConstructor();
  factory MLIndexingIsolate() => instance;

  /// Analyzes the given image data by running the full pipeline for faces, using [analyzeImageStatic] in the isolate.
  Future<MLResult?> analyzeImage(
    FileMLInstruction instruction,
    String filePath,
  ) async {
    late MLResult result;

    try {
      final useRustMl = _shouldUseRustMl;
      final rustRuntimeArgs = useRustMl
          ? await _getCachedRustRuntimeArgs()
          : const <String, dynamic>{};
      _logger.info(
        "Analyzing image ${instruction.fileKey} via rust or legacy: ${useRustMl ? "RUST" : "LEGACY"}",
      );

      final isolateResult = await runInIsolate(IsolateOperation.analyzeImage, {
        "enteFileID": instruction.fileKey,
        "filePath": filePath,
        "useRustMl": useRustMl,
        "runFaces": instruction.shouldRunFaces,
        "runClip": instruction.shouldRunClip,
        "runPets": useRustMl && instruction.shouldRunPets,
        ...rustRuntimeArgs,
        "faceDetectionAddress": FaceDetectionService.instance.sessionAddress,
        "faceEmbeddingAddress": FaceEmbeddingService.instance.sessionAddress,
        "clipImageAddress": ClipImageEncoder.instance.sessionAddress,
      });
      if (isolateResult is RustCorruptModelCacheDeletedException) {
        _logger.warning(
          "Deleted corrupt Rust ONNX model cache at ${isolateResult.modelPath}; "
          "stopping ML indexing for fileID ${instruction.fileKey}",
        );
        shouldPauseIndexingAndClustering = true;
        throw isolateResult;
      }
      final resultJsonString = isolateResult as String?;
      if (resultJsonString == null) {
        if (!shouldPauseIndexingAndClustering) {
          _logger.severe('Analyzing image in isolate is giving back null');
        }
        return null;
      }
      result = MLResult.fromJsonString(resultJsonString);
      result.usedRustMl = useRustMl;
    } catch (e, s) {
      if (e is RustCorruptModelCacheDeletedException ||
          isExpectedMlSkipError(e)) {
        rethrow;
      }
      _logger.severe(
        "Could not analyze image with ID ${instruction.fileKey} \n",
        e,
        s,
      );
      if (kDebugMode) {
        _logger.info(
          "This image with fileID ${instruction.fileKey} has name ${instruction.file.displayName}.",
        );
      }
      rethrow;
    }

    return result;
  }

  Future<void> prepareRustRuntime() async {
    if (!_shouldUseRustMl) {
      return;
    }
    return _rustRuntimeLock.synchronized(() async {
      final rustRuntimeArgs = await _buildRustRuntimeArgs();
      final frozenRuntimeArgs = Map<String, dynamic>.unmodifiable(
        rustRuntimeArgs,
      );
      await runInIsolate(
        IsolateOperation.prepareRustMlRuntime,
        frozenRuntimeArgs,
      );
      _cachedRustRuntimeArgs = frozenRuntimeArgs;
    });
  }

  Future<void> releaseRustRuntime() async {
    final cachedRustRuntimeArgs = _cachedRustRuntimeArgs;
    if (cachedRustRuntimeArgs == null) {
      return;
    }
    if (!isIsolateSpawned) {
      _cachedRustRuntimeArgs = null;
      return;
    }
    return _rustRuntimeLock.synchronized(() async {
      if (_cachedRustRuntimeArgs == null) {
        return;
      }
      if (!isIsolateSpawned) {
        _cachedRustRuntimeArgs = null;
        return;
      }
      try {
        await runInIsolate(IsolateOperation.releaseRustMlRuntime, {});
        _cachedRustRuntimeArgs = null;
      } catch (e, s) {
        _logger.warning("Could not release rust runtime in isolate", e, s);
      }
    });
  }

  Future<void> ensureLoadedModels(FileMLInstruction instruction) async {
    if (_shouldUseRustMl) {
      return;
    }
    return _initModelLock.synchronized(() async {
      final faceDetectionLoaded = FaceDetectionService.instance.isInitialized;
      final faceEmbeddingLoaded = FaceEmbeddingService.instance.isInitialized;
      final facesModelsLoaded = faceDetectionLoaded && faceEmbeddingLoaded;
      final clipModelsLoaded = ClipImageEncoder.instance.isInitialized;

      final shouldLoadFaces = instruction.shouldRunFaces && !facesModelsLoaded;
      final shouldLoadClip = instruction.shouldRunClip && !clipModelsLoaded;
      if (!shouldLoadFaces && !shouldLoadClip) {
        return;
      }

      _logger.info(
        'Loading models. faces: $shouldLoadFaces, clip: $shouldLoadClip',
      );
      _loadedModelsCount++;
      _logger.info(
        "Loaded models count: $_loadedModelsCount, deloaded models count: $_deloadedModelsCount",
      );
      await MLIndexingIsolate.instance._loadModels(
        loadFaces: shouldLoadFaces,
        loadClip: shouldLoadClip,
      );
      _logger.info('Models loaded');
    });
  }

  Future<void> _loadModels({
    required bool loadFaces,
    required bool loadClip,
  }) async {
    if (!loadFaces && !loadClip) return;
    final List<MLModels> models = [];
    final List<String> modelNames = [];
    final List<String> modelPaths = [];
    if (loadFaces) {
      models.addAll([MLModels.faceDetection, MLModels.faceEmbedding]);
      final faceDetection = await FaceDetectionService.instance
          .getModelNameAndPath();
      modelNames.add(faceDetection.$1);
      modelPaths.add(faceDetection.$2);
      final faceEmbedding = await FaceEmbeddingService.instance
          .getModelNameAndPath();
      modelNames.add(faceEmbedding.$1);
      modelPaths.add(faceEmbedding.$2);
    }
    if (loadClip) {
      models.add(MLModels.clipImageEncoder);
      final clipImage = await ClipImageEncoder.instance.getModelNameAndPath();
      modelNames.add(clipImage.$1);
      modelPaths.add(clipImage.$2);
    }

    try {
      final addresses =
          await runInIsolate(IsolateOperation.loadIndexingModels, {
                "modelNames": modelNames,
                "modelPaths": modelPaths,
              })
              as List<int>;
      for (int i = 0; i < models.length; i++) {
        final model = models[i].model;
        final address = addresses[i];
        model.storeSessionAddress(address);
      }
    } catch (e, s) {
      _logger.severe("Could not load models in MLIndexingIsolate", e, s);
      rethrow;
    }
  }

  /// WARNING: This method is only for debugging purposes. It should not be used in production.
  Future<void> debugLoadSingleModel(MLModels model) {
    if (_shouldUseRustMl) {
      _logger.severe("Can't use legacy ML models when using rust");
      return Future.value();
    }
    return _initModelLock.synchronized(() async {
      final modelInstance = model.model;
      if (modelInstance.isInitialized) {
        _logger.info("Model ${model.name} already loaded");
        return;
      }
      final modelName = modelInstance.modelName;
      final modelPath = await modelInstance.downloadModelSafe();
      if (modelPath == null) {
        _logger.warning(
          "Could not download model '$modelName': WiFi unavailable",
        );
        return;
      }
      final address =
          await runInIsolate(IsolateOperation.loadModel, {
                "modelName": modelName,
                "modelPath": modelPath,
              })
              as int;
      modelInstance.storeSessionAddress(address);
    });
  }

  Future<void> cleanupLocalIndexingModels({bool delete = false}) async {
    await releaseRustRuntime();
    if (!MLModelDownloadService.instance.areIndexingModelsDownloaded) return;
    await _releaseModels();

    if (delete) {
      final List<String> remoteModelPaths = [];

      for (final model in MLModels.values) {
        if (!model.isIndexingModel) continue;
        final mlModel = model.model;
        remoteModelPaths.add(mlModel.modelRemotePath);
      }
      await RemoteAssetsService.instance.cleanupSelectedModels(
        remoteModelPaths,
      );

      MLModelDownloadService.instance.invalidateModelDownloadCache();
    }
  }

  Future<void> _releaseModels() async {
    if (_shouldUseRustMl) {
      _logger.severe("Can't release legacy ML models when using rust");
      return Future.value();
    }
    final List<String> modelNames = [];
    final List<int> modelAddresses = [];
    final List<MLModels> models = [];
    for (final model in MLModels.values) {
      if (!model.isIndexingModel) continue;
      final mlModel = model.model;
      if (mlModel.isInitialized) {
        models.add(model);
        modelNames.add(mlModel.modelName);
        modelAddresses.add(mlModel.sessionAddress);
      }
    }
    if (modelNames.isEmpty) return;
    try {
      _logger.info("Releasing models $modelNames");
      _deloadedModelsCount++;
      _logger.info(
        "Loaded models count: $_loadedModelsCount, deloaded models count: $_deloadedModelsCount",
      );
      await runInIsolate(IsolateOperation.releaseIndexingModels, {
        "modelNames": modelNames,
        "modelAddresses": modelAddresses,
      });
      for (final model in models) {
        model.model.releaseSessionAddress();
      }
      _logger.info("Indexing models released in isolate");
    } catch (e, s) {
      _logger.severe("Could not release models in MLIndexingIsolate", e, s);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _buildRustRuntimeArgs() async {
    final faceDetection = await FaceDetectionService.instance
        .getModelNameAndPath();
    final faceEmbedding = await FaceEmbeddingService.instance
        .getModelNameAndPath();
    final clipImage = await ClipImageEncoder.instance.getModelNameAndPath();

    String petFaceDetectionPath = "";
    String petFaceEmbeddingDogPath = "";
    String petFaceEmbeddingCatPath = "";
    String petBodyDetectionPath = "";
    String petBodyEmbeddingDogPath = "";
    String petBodyEmbeddingCatPath = "";

    if (flagService.petEnabled && localSettings.petRecognitionEnabled) {
      petFaceDetectionPath =
          (await PetFaceDetectionService.instance.getModelNameAndPath()).$2;
      petFaceEmbeddingDogPath =
          (await PetFaceEmbeddingDogService.instance.getModelNameAndPath()).$2;
      petFaceEmbeddingCatPath =
          (await PetFaceEmbeddingCatService.instance.getModelNameAndPath()).$2;
      petBodyDetectionPath =
          (await PetBodyDetectionService.instance.getModelNameAndPath()).$2;
      petBodyEmbeddingDogPath =
          (await PetBodyEmbeddingDogService.instance.getModelNameAndPath()).$2;
      petBodyEmbeddingCatPath =
          (await PetBodyEmbeddingCatService.instance.getModelNameAndPath()).$2;
    }

    return {
      "faceDetectionModelPath": faceDetection.$2,
      "faceEmbeddingModelPath": faceEmbedding.$2,
      "clipImageModelPath": clipImage.$2,
      "petFaceDetectionModelPath": petFaceDetectionPath,
      "petFaceEmbeddingDogModelPath": petFaceEmbeddingDogPath,
      "petFaceEmbeddingCatModelPath": petFaceEmbeddingCatPath,
      "petBodyDetectionModelPath": petBodyDetectionPath,
      "petBodyEmbeddingDogModelPath": petBodyEmbeddingDogPath,
      "petBodyEmbeddingCatModelPath": petBodyEmbeddingCatPath,
      "preferCoreml": Platform.isIOS,
      "preferNnapi": Platform.isAndroid,
      "preferXnnpack": Platform.isAndroid,
      "allowCpuFallback": true,
    };
  }

  Future<Map<String, dynamic>> _getCachedRustRuntimeArgs() async {
    final cachedArgs = _cachedRustRuntimeArgs;
    if (cachedArgs != null) {
      return cachedArgs;
    }
    final rustRuntimeArgs = await _buildRustRuntimeArgs();
    final frozenArgs = Map<String, dynamic>.unmodifiable(rustRuntimeArgs);
    _cachedRustRuntimeArgs ??= frozenArgs;
    return _cachedRustRuntimeArgs!;
  }
}
