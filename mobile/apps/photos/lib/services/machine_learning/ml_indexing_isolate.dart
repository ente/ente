import "package:flutter/foundation.dart" show debugPrint, kDebugMode;
import "package:logging/logging.dart";
import "package:photos/models/ml/ml_versions.dart"
    show mlIndexFlagCoreML, mlIndexFlagRuntimeRust, mlIndexFlagWebGPU;
import "package:photos/service_locator.dart" show flagService, localSettings;
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_models_overview.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/webgpu_execution_policy.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/isolate/super_isolate.dart";
import "package:photos/utils/ml_util.dart";
import "package:synchronized/synchronized.dart";

@pragma("vm:entry-point")
class MLIndexingIsolate extends SuperIsolate {
  @override
  Logger get logger => _logger;
  final _logger = Logger("MLIndexingIsolate");

  @override
  String get isolateName => "MLIndexingIsolate";

  @override
  bool get shouldAutomaticDispose => true;

  final _rustRuntimeLock = Lock();
  Map<String, dynamic>? _cachedRustRuntimeArgs;
  final Set<int> _runtimeFlagCombinations = {};

  @override
  Future<void> onDispose() => releaseRustRuntime();

  @override
  bool postFunctionlockStop(IsolateOperation operation) {
    return operation == IsolateOperation.analyzeImage &&
        shouldPauseIndexingAndClustering;
  }

  bool shouldPauseIndexingAndClustering = false;

  MLIndexingIsolate._privateConstructor();
  static final instance = MLIndexingIsolate._privateConstructor();
  factory MLIndexingIsolate() => instance;

  Future<MLResult?> analyzeImage(
    FileMLInstruction instruction,
    String filePath,
  ) async {
    try {
      final rustRuntimeArgs = await _getCachedRustRuntimeArgs();
      final enableWebGpu = await webGpuExecutionPolicy.isEligible();
      _logger.info("Analyzing image ${instruction.fileKey} with Rust ML");

      final isolateResult = await runInIsolate(IsolateOperation.analyzeImage, {
        "enteFileID": instruction.fileKey,
        "filePath": filePath,
        "runFaces": instruction.shouldRunFaces,
        "runClip": instruction.shouldRunClip,
        "runPets": instruction.shouldRunPets,
        ...rustRuntimeArgs,
        "enableWebGpu": enableWebGpu,
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
          _logger.severe("Analyzing image in isolate returned null");
        }
        return null;
      }
      final result = MLResult.fromJsonString(resultJsonString);
      _runtimeFlagCombinations.add(result.remoteFlags);
      return result;
    } catch (e, s) {
      if (e is RustCorruptModelCacheDeletedException ||
          isExpectedMlSkipError(e)) {
        rethrow;
      }
      _logger.severe(
        "Could not analyze image with ID ${instruction.fileKey}",
        e,
        s,
      );
      if (kDebugMode) {
        debugPrint(
          "This image with fileID ${instruction.fileKey} has name ${instruction.file.displayName}.",
        );
      }
      rethrow;
    }
  }

  Future<void> prepareRustRuntime() {
    return _rustRuntimeLock.synchronized(() async {
      _runtimeFlagCombinations.clear();
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
    try {
      final cachedRustRuntimeArgs = _cachedRustRuntimeArgs;
      if (cachedRustRuntimeArgs == null) {
        return;
      }
      if (!isIsolateSpawned) {
        _cachedRustRuntimeArgs = null;
        return;
      }
      await _rustRuntimeLock.synchronized(() async {
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
          _logger.warning("Could not release Rust runtime in isolate", e, s);
        }
      });
    } finally {
      _logAndResetRuntimeSummary();
    }
  }

  void _logAndResetRuntimeSummary() {
    if (_runtimeFlagCombinations.isEmpty) {
      return;
    }
    final summaries =
        _runtimeFlagCombinations
            .map(_formatRuntimeFlags)
            .toList(growable: false)
          ..sort();
    _logger.info("Rust ML indexing runtime summary: ${summaries.join(', ')}");
    _runtimeFlagCombinations.clear();
  }

  String _formatRuntimeFlags(int flags) {
    if ((flags & mlIndexFlagRuntimeRust) == 0) {
      return "unknown ($flags)";
    }
    final acceleratedProviders = <String>[];
    if ((flags & mlIndexFlagCoreML) != 0) {
      acceleratedProviders.add("CoreML");
    }
    if ((flags & mlIndexFlagWebGPU) != 0) {
      acceleratedProviders.add("WebGPU");
    }
    if (acceleratedProviders.isEmpty) {
      return "Rust (no CoreML/WebGPU flag)";
    }
    return "Rust+${acceleratedProviders.join('+')}";
  }

  Future<void> cleanupLocalIndexingModels({bool delete = false}) async {
    await releaseRustRuntime();
    if (!MLModelDownloadService.instance.areIndexingModelsDownloaded) return;

    if (delete) {
      final remoteModelPaths = <String>[
        for (final model in MLModels.values)
          if (model.isIndexingModel) model.model.modelRemotePath,
      ];
      await RemoteAssetsService.instance.cleanupSelectedModels(
        remoteModelPaths,
      );
      MLModelDownloadService.instance.invalidateModelDownloadCache();
    }
  }

  Future<Map<String, dynamic>> _buildRustRuntimeArgs() async {
    final faceDetectionPath = await FaceDetectionModel.instance.getModelPath();
    final faceEmbeddingPath = await FaceEmbeddingModel.instance.getModelPath();
    final clipImagePath = await ClipImageModel.instance.getModelPath();

    String petFaceDetectionPath = "";
    String petFaceEmbeddingDogPath = "";
    String petFaceEmbeddingCatPath = "";
    String petBodyDetectionPath = "";
    String petBodyEmbeddingDogPath = "";
    String petBodyEmbeddingCatPath = "";

    if (flagService.petEnabled && localSettings.petRecognitionEnabled) {
      petFaceDetectionPath = await PetFaceDetectionModel.instance
          .getModelPath();
      petFaceEmbeddingDogPath = await PetFaceEmbeddingDogModel.instance
          .getModelPath();
      petFaceEmbeddingCatPath = await PetFaceEmbeddingCatModel.instance
          .getModelPath();
      petBodyDetectionPath = await PetBodyDetectionModel.instance
          .getModelPath();
      petBodyEmbeddingDogPath = await PetBodyEmbeddingDogModel.instance
          .getModelPath();
      petBodyEmbeddingCatPath = await PetBodyEmbeddingCatModel.instance
          .getModelPath();
    }

    return {
      // Sessions are lazy, so the inference call re-evaluates this app-side
      // policy before Rust applies its own durable crash canary.
      "enableWebGpu": await webGpuExecutionPolicy.isEligible(),
      "faceDetectionModelPath": faceDetectionPath,
      "faceEmbeddingModelPath": faceEmbeddingPath,
      "clipImageModelPath": clipImagePath,
      "petFaceDetectionModelPath": petFaceDetectionPath,
      "petFaceEmbeddingDogModelPath": petFaceEmbeddingDogPath,
      "petFaceEmbeddingCatModelPath": petFaceEmbeddingCatPath,
      "petBodyDetectionModelPath": petBodyDetectionPath,
      "petBodyEmbeddingDogModelPath": petBodyEmbeddingDogPath,
      "petBodyEmbeddingCatModelPath": petBodyEmbeddingCatPath,
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
