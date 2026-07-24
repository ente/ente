import 'dart:async';
import "dart:typed_data" show Float32List;

import "package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart"
    show Uint64List;
import "package:logging/logging.dart";
import "package:photos/core/errors.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/machine_learning/ml_constants.dart";
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/services/machine_learning/webgpu_execution_policy.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/isolate/super_isolate.dart";
import "package:synchronized/synchronized.dart";

@pragma('vm:entry-point')
class MLComputer extends SuperIsolate {
  @override
  Logger get logger => _logger;
  final _logger = Logger('MLComputer');

  final _initModelLock = Lock();
  String? _clipTextModelPath;
  String? _clipTextVocabPath;
  Future<void>? _clipTextWarmupFuture;

  @override
  String get isolateName => "MLComputerIsolate";

  @override
  bool get shouldAutomaticDispose => false;

  // Singleton pattern
  MLComputer._privateConstructor();
  static final MLComputer instance = MLComputer._privateConstructor();
  factory MLComputer() => instance;

  Future<(List<Uint64List>, List<Float32List>)> bulkVectorSearch(
    List<Float32List> clipFloat32,
    bool exact,
  ) async {
    try {
      final result = await runInIsolate(IsolateOperation.bulkVectorSearch, {
        "clipFloat32": clipFloat32,
        "exact": exact,
      });
      return result;
    } catch (e, s) {
      _logger.severe("Could not run bulk vector search in MLComputer", e, s);
      rethrow;
    }
  }

  Future<(Uint64List, List<Uint64List>, List<Float32List>)>
  bulkVectorSearchWithKeys(Uint64List potentialKeys, bool exact) async {
    try {
      final result = await runInIsolate(
        IsolateOperation.bulkVectorSearchWithKeys,
        {"potentialKeys": potentialKeys, "exact": exact},
      );
      return result;
    } catch (e, s) {
      _logger.severe("Could not run bulk vector search in MLComputer", e, s);
      rethrow;
    }
  }

  Future<List<double>> runClipText(String query) async {
    try {
      await _ensureLoadedClipTextModel();
      final modelPath = _clipTextModelPath;
      final vocabPath = _clipTextVocabPath;
      if (modelPath == null || modelPath.trim().isEmpty) {
        throw Exception(
          "RustMLMissingModelPath: Missing required model path: clipTextModelPath",
        );
      }
      if (vocabPath == null || vocabPath.trim().isEmpty) {
        throw Exception(
          "RustMLMissingModelPath: Missing required model path: clipTextVocabPath",
        );
      }
      final enableWebGpu = await webGpuExecutionPolicy.isEligible();
      final isolateResult = await runInIsolate(IsolateOperation.runClipText, {
        "text": query,
        "clipTextModelPath": modelPath,
        "clipTextVocabPath": vocabPath,
        "enableWebGpu": enableWebGpu,
      });
      if (isolateResult is RustCorruptModelCacheDeletedException) {
        _clipTextModelPath = null;
        MLModelDownloadService.instance.invalidateModelDownloadCache(
          includeNonIndexingModels: true,
        );
        throw isolateResult;
      }
      final textEmbedding = isolateResult as List<double>;
      return textEmbedding;
    } on WiFiUnavailableError catch (e, s) {
      _logger.warning(
        "Could not run clip text because model is unavailable",
        e,
        s,
      );
      rethrow;
    } on RustCorruptModelCacheDeletedException catch (e) {
      _logger.warning(
        "Deleted corrupt Rust CLIP text model cache at ${e.modelPath}",
      );
      rethrow;
    } catch (e, s) {
      _logger.severe("Could not run clip text in isolate", e, s);
      rethrow;
    }
  }

  Future<void> warmUpClipTextEncoder() {
    _clipTextWarmupFuture ??= _warmUpClipTextEncoderInternal();
    return _clipTextWarmupFuture!;
  }

  Future<void> _warmUpClipTextEncoderInternal() async {
    try {
      await runClipText("warm up text encoder");
    } catch (e, s) {
      _clipTextWarmupFuture = null;
      _logger.warning("Clip text warmup failed in MLComputer", e, s);
      rethrow;
    }
  }

  Future<void> _ensureLoadedClipTextModel() async {
    return _initModelLock.synchronized(() async {
      try {
        if (_clipTextVocabPath == null) {
          final tokenizerRemotePath = ClipTextModel.instance.vocabRemotePath;
          _clipTextVocabPath = await RemoteAssetsService.instance.getAssetPath(
            tokenizerRemotePath,
            expectedSha256: ClipTextModel.instance.vocabSha256,
          );
        }

        if (_clipTextModelPath != null) {
          return;
        }

        final String? downloadedModelPath = await ClipTextModel.instance
            .downloadModelSafe();
        if (downloadedModelPath == null) {
          throw WiFiUnavailableError(
            "Could not download clip text model because high bandwidth "
            "connectivity is unavailable",
          );
        }
        _clipTextModelPath = downloadedModelPath;
      } catch (e, s) {
        _logger.severe("Could not load clip text model in MLComputer", e, s);
        rethrow;
      }
    });
  }

  Future<Map<String, List<QueryResult>>> computeBulkSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap,
  ) async {
    try {
      final queryToResults =
          await runInIsolate(IsolateOperation.computeBulkSimilarities, {
                "textQueryToEmbeddingMap": textQueryToEmbeddingMap,
                "minimumSimilarityMap": minimumSimilarityMap,
              })
              as Map<String, List<QueryResult>>;
      return queryToResults;
    } catch (e, s) {
      _logger.severe(
        "Could not bulk compare embeddings inside MLComputer isolate",
        e,
        s,
      );
      rethrow;
    }
  }

  Future<Map<String, List<QueryResult>>> computeBulkSimilaritiesWithRust(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap,
  ) async {
    try {
      final queryToResults =
          await runInIsolate(IsolateOperation.computeBulkSimilaritiesWithRust, {
                "textQueryToEmbeddingMap": textQueryToEmbeddingMap,
                "minimumSimilarityMap": minimumSimilarityMap,
              })
              as Map<String, List<QueryResult>>;
      return queryToResults;
    } catch (e, s) {
      _logger.severe(
        "Could not bulk compare embeddings with rust inside MLComputer isolate",
        e,
        s,
      );
      rethrow;
    }
  }

  Future<void> cacheImageEmbeddings(
    List<EmbeddingVector> embeddings, {
    bool cacheRustExact = false,
  }) async {
    try {
      await runInIsolate(IsolateOperation.cacheImageEmbeddings, {
            'embeddings': embeddings,
            'cacheRustExact': cacheRustExact,
          })
          as bool;
      _logger.info(
        'Cached ${embeddings.length} image embeddings inside MLComputer',
      );
      return;
    } catch (e, s) {
      _logger.severe("Could not cache image embeddings in MLComputer", e, s);
      rethrow;
    }
  }

  Future<void> clearImageEmbeddingsCache() async {
    try {
      await runInIsolate(IsolateOperation.clearIsolateCache, {
            'key': imageEmbeddingsKey,
          })
          as bool;
      return;
    } catch (e, s) {
      _logger.severe(
        "Could not clear image embeddings cache in MLComputer",
        e,
        s,
      );
      rethrow;
    }
  }
}
