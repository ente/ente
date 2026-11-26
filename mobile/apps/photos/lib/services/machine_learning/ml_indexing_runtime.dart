import "dart:async";

import "package:flutter/foundation.dart" show debugPrint, kDebugMode;
import "package:logging/logging.dart";
import "package:photos/models/ml/ml_versions.dart"
    show mlIndexFlagCoreML, mlIndexFlagRuntimeRust, mlIndexFlagWebGPU;
import "package:photos/service_locator.dart" show flagService, localSettings;
import "package:photos/services/machine_learning/ml_exceptions.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/webgpu_execution_policy.dart";
import "package:photos/src/rust/api/ml_indexing_api.dart" as rust_ml;
import "package:photos/utils/ml_util.dart";
import "package:synchronized/synchronized.dart";

typedef _RuntimeArgs = ({
  String assetsDir,
  bool preparePets,
  bool enableWebGpu,
});

class MLIndexingRuntime {
  MLIndexingRuntime._privateConstructor();
  static final instance = MLIndexingRuntime._privateConstructor();

  static const _idleReleaseDelay = Duration(seconds: 60);

  final _logger = Logger("MLIndexingRuntime");
  final _lock = Lock();
  Timer? _idleReleaseTimer;
  _RuntimeArgs? _runtimeArgs;
  ({String assetsDir, bool preparePets})? _initializedRuntime;
  final Set<int> _runtimeFlagCombinations = {};

  bool shouldPauseIndexingAndClustering = false;

  Future<MLResult?> analyzeImage(
    FileMLInstruction instruction,
    String filePath,
  ) async {
    try {
      _logger.info("Analyzing image ${instruction.fileKey} with Rust ML");
      final result = await _runLocked(() async {
        if (shouldPauseIndexingAndClustering) return null;
        final runtimeArgs = _runtimeArgs ?? await _buildRuntimeArgs();
        final enableWebGpu = await webGpuExecutionPolicy.isEligible();
        if (shouldPauseIndexingAndClustering) return null;
        _runtimeArgs = runtimeArgs;
        try {
          return await analyzeImageRust(
            enteFileID: instruction.fileKey,
            imagePath: filePath,
            runFaces: instruction.shouldRunFaces,
            runClip: instruction.shouldRunClip,
            runPets: instruction.shouldRunPets,
            assetsDir: runtimeArgs.assetsDir,
            enableWebGpu: enableWebGpu,
          );
        } on RustCorruptModelException {
          shouldPauseIndexingAndClustering = true;
          rethrow;
        }
      });
      if (result != null) _runtimeFlagCombinations.add(result.remoteFlags);
      return result;
    } on RustCorruptModelException catch (e) {
      _logger.severe(
        "Rust ML reported a corrupt model at ${e.modelPath}; "
        "stopping ML indexing for fileID ${instruction.fileKey}",
      );
      rethrow;
    } catch (e, s) {
      if (isExpectedMlSkipError(e)) rethrow;
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
    return _runLocked(() async {
      _runtimeFlagCombinations.clear();
      final runtimeArgs = await _buildRuntimeArgs();
      await rust_ml.setMlExecutionConfig(
        enableWebgpu: runtimeArgs.enableWebGpu,
      );
      final runtime = (
        assetsDir: runtimeArgs.assetsDir,
        preparePets: runtimeArgs.preparePets,
      );
      if (_initializedRuntime != runtime) {
        try {
          await rust_ml.initMlRuntime(
            assetsDir: runtimeArgs.assetsDir,
            runFaces: true,
            runClip: true,
            runPets: runtimeArgs.preparePets,
          );
        } on rust_ml.RustMlError_ModelDownloadNetwork catch (e) {
          throw ModelDownloadNetworkException(e.message);
        }
        _initializedRuntime = runtime;
      }
      _runtimeArgs = runtimeArgs;
    });
  }

  Future<void> releaseRustRuntime() async {
    _idleReleaseTimer?.cancel();
    try {
      await _lock.synchronized(() async {
        if (_runtimeArgs == null) return;
        try {
          await rust_ml.releaseMlRuntime();
        } catch (e, s) {
          _logger.warning("Could not release Rust runtime", e, s);
        }
        _runtimeArgs = null;
        _initializedRuntime = null;
      });
    } finally {
      _logAndResetRuntimeSummary();
    }
  }

  Future<T> _runLocked<T>(Future<T> Function() operation) {
    return _lock.synchronized(() async {
      _idleReleaseTimer?.cancel();
      try {
        return await operation();
      } finally {
        _idleReleaseTimer = Timer(
          _idleReleaseDelay,
          () => unawaited(releaseRustRuntime()),
        );
      }
    });
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

  Future<_RuntimeArgs> _buildRuntimeArgs() async {
    return (
      assetsDir: await MLModelDownloadService.instance.getAssetsDirectory(),
      preparePets:
          flagService.petEnabled && localSettings.petRecognitionEnabled,
      enableWebGpu: await webGpuExecutionPolicy.isEligible(),
    );
  }
}
