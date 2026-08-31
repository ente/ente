import 'dart:typed_data' show Float32List, Uint8List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Uint64List;
import "package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart"
    show Int64List;
import "package:ml_linalg/linalg.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/models/ml/face/box.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/ml_constants.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/src/rust/api/image_processing_api.dart"
    as rust_image_processing;
import "package:photos/src/rust/api/ml_indexing_api.dart" as rust_ml;
import "package:photos/src/rust/api/usearch_api.dart" as rust_usearch;
import "package:photos/src/rust/frb_generated.dart" show EntePhotosRust;
import "package:photos/utils/ml_util.dart";

final Map<String, dynamic> _isolateCache = {};
const _rustLibLoadedCacheKey = "rustLibLoaded";
const _rustMlModelPathsCacheKey = "rustMlModelPaths";

class RustCorruptModelException implements Exception {
  const RustCorruptModelException(this.modelPath);

  final String modelPath;

  @override
  String toString() => "RustCorruptModelException: $modelPath";
}

enum IsolateOperation {
  analyzeImage,
  prepareRustMlRuntime,
  releaseRustMlRuntime,
  generateFaceThumbnails,
  runClipText,
  computeBulkSimilarities,
  computeBulkSimilaritiesWithRust,
  bulkVectorSearch,
  bulkVectorSearchWithKeys,
  linearIncrementalClustering,
  cacheImageEmbeddings,
  setIsolateCache,
  clearIsolateCache,
  clearAllIsolateCache,
}

class _CachedImageEmbeddings {
  _CachedImageEmbeddings({required this.embeddingVectors});

  final List<EmbeddingVector> embeddingVectors;
  rust_usearch.SemanticSearchExactCache? rustExactCache;
}

// Return only primitives unless this operation only runs on regular Dart
// isolates rather than Dart UI or Flutter isolates.
// https://api.flutter.dev/flutter/dart-isolate/SendPort/send.html
Future<dynamic> isolateFunction(
  IsolateOperation function,
  Map<String, dynamic> args,
) async {
  switch (function) {
    case IsolateOperation.bulkVectorSearchWithKeys:
      await _ensureRustLoaded();
      final potentialKeys = args["potentialKeys"] as Uint64List;
      final exact = args["exact"] as bool;

      return ClipVectorDB.instance.bulkSearchWithKeys(
        potentialKeys,
        BigInt.from(100),
        exact: exact,
      );

    case IsolateOperation.bulkVectorSearch:
      await _ensureRustLoaded();
      final clipFloat32 = args["clipFloat32"] as List<Float32List>;
      final exact = args["exact"] as bool;

      return ClipVectorDB.instance.bulkSearchVectors(
        clipFloat32,
        BigInt.from(100),
        exact: exact,
      );

    case IsolateOperation.analyzeImage:
      await _ensureRustLoaded();
      final MLResult result;
      try {
        result = await analyzeImageRust(args);
      } on rust_ml.RustMlError_CorruptModel catch (e) {
        return RustCorruptModelException(e.message);
      }
      return result.toJsonString();

    case IsolateOperation.prepareRustMlRuntime:
      await _ensureRustLoaded();
      await _ensureRustRuntimePrepared(args);
      return true;

    case IsolateOperation.releaseRustMlRuntime:
      await _releaseRustRuntime();
      return true;

    case IsolateOperation.generateFaceThumbnails:
      final imagePath = args['imagePath'] as String;
      final faceBoxesJson = args['faceBoxesList'] as List<Map<String, dynamic>>;
      final List<FaceBox> faceBoxes = faceBoxesJson
          .map((json) => FaceBox.fromJson(json))
          .toList();
      await _ensureRustLoaded();
      final rustFaceBoxes = faceBoxes
          .map(
            (box) => rust_image_processing.RustFaceBox(
              x: box.x,
              y: box.y,
              width: box.width,
              height: box.height,
            ),
          )
          .toList(growable: false);
      final List<Uint8List> results = await rust_image_processing
          .generateFaceThumbnails(
            imagePath: imagePath,
            faceBoxes: rustFaceBoxes,
          );
      return List.from(results);

    case IsolateOperation.runClipText:
      await _ensureRustLoaded();
      final text = args["text"] as String;
      final clipTextModelPath = args["clipTextModelPath"] as String?;
      if (clipTextModelPath == null || clipTextModelPath.trim().isEmpty) {
        throw Exception(
          "RustMLMissingModelPath: Missing required model path: clipTextModelPath",
        );
      }

      final clipTextVocabPath = args["clipTextVocabPath"] as String?;
      if (clipTextVocabPath == null || clipTextVocabPath.trim().isEmpty) {
        throw Exception(
          "RustMLMissingModelPath: Missing required model path: clipTextVocabPath",
        );
      }

      // Configure execution behavior before the CLIP text session is
      // created; the session is process-global and cannot be reconfigured
      // once built.
      await rust_ml.setMlExecutionConfig(
        enableWebgpu: (args["enableWebGpu"] as bool?) ?? false,
      );

      final rust_ml.RunClipTextResult result;
      try {
        result = await rust_ml.runClipTextRust(
          req: rust_ml.RunClipTextRequest(
            text: text,
            modelPath: clipTextModelPath,
            vocabPath: clipTextVocabPath,
          ),
        );
      } on rust_ml.RustMlError_CorruptModel catch (e) {
        return RustCorruptModelException(e.message);
      }
      return List<double>.from(result.embedding, growable: false);

    case IsolateOperation.computeBulkSimilarities:
      final cachedEmbeddings = _getCachedImageEmbeddings();
      final textEmbedding =
          args["textQueryToEmbeddingMap"] as Map<String, List<double>>;
      final minimumSimilarityMap =
          args["minimumSimilarityMap"] as Map<String, double>;
      final result = <String, List<QueryResult>>{};
      for (final MapEntry<String, List<double>> entry
          in textEmbedding.entries) {
        final query = entry.key;
        final textVector = Vector.fromList(entry.value);
        final minimumSimilarity = minimumSimilarityMap[query]!;
        final queryResults = <QueryResult>[];
        for (final imageEmbedding in cachedEmbeddings.embeddingVectors) {
          final similarity = imageEmbedding.vector.dot(textVector);
          if (similarity >= minimumSimilarity) {
            queryResults.add(QueryResult(imageEmbedding.fileID, similarity));
          }
        }
        queryResults.sort(
          (first, second) => second.score.compareTo(first.score),
        );
        result[query] = queryResults;
      }
      return result;

    case IsolateOperation.computeBulkSimilaritiesWithRust:
      await _ensureRustLoaded();
      final cachedEmbeddings = _getCachedImageEmbeddings();
      final textEmbedding =
          args["textQueryToEmbeddingMap"] as Map<String, List<double>>;
      final minimumSimilarityMap =
          args["minimumSimilarityMap"] as Map<String, double>;
      final queryKeys = textEmbedding.keys.toList(growable: false);
      final rustExactCache = await _ensureRustExactCache(cachedEmbeddings);
      final response = await rustExactCache.search(
        queryEmbeddings: queryKeys
            .map((query) => Float32List.fromList(textEmbedding[query]!))
            .toList(growable: false),
        minimumSimilarities: Float32List.fromList(
          queryKeys
              .map((query) => minimumSimilarityMap[query]!)
              .toList(growable: false),
        ),
      );
      final result = <String, List<QueryResult>>{};
      for (int i = 0; i < queryKeys.length; i++) {
        final matches = response.matchesPerQuery[i];
        result[queryKeys[i]] = matches
            .map((match) => QueryResult(match.fileId, match.score))
            .toList(growable: false);
      }
      return result;

    case IsolateOperation.linearIncrementalClustering:
      final ClusteringResult result = runLinearClustering(args);
      return result;

    case IsolateOperation.cacheImageEmbeddings:
      final embeddings = args['embeddings'] as List<EmbeddingVector>;
      final cacheRustExact = args['cacheRustExact'] as bool? ?? false;
      final cachedEmbeddings = _CachedImageEmbeddings(
        embeddingVectors: embeddings,
      );
      if (cacheRustExact) {
        cachedEmbeddings.rustExactCache = await _createRustExactCache(
          cachedEmbeddings,
        );
      }
      _disposeIsolateCacheValue(_isolateCache[imageEmbeddingsKey]);
      _isolateCache[imageEmbeddingsKey] = cachedEmbeddings;
      return true;

    case IsolateOperation.setIsolateCache:
      final key = args['key'] as String;
      final value = args['value'];
      _disposeIsolateCacheValue(_isolateCache[key]);
      _isolateCache[key] = value;
      return true;

    case IsolateOperation.clearIsolateCache:
      final key = args['key'] as String;
      final removedValue = _isolateCache.remove(key);
      _disposeIsolateCacheValue(removedValue);
      return true;

    case IsolateOperation.clearAllIsolateCache:
      await _ensureRustDisposed();
      for (final value in _isolateCache.values) {
        _disposeIsolateCacheValue(value);
      }
      _isolateCache.clear();
      return true;
  }
}

_CachedImageEmbeddings _getCachedImageEmbeddings() {
  final cachedEmbeddings = _isolateCache[imageEmbeddingsKey];
  if (cachedEmbeddings is! _CachedImageEmbeddings) {
    throw StateError("Image embeddings are not cached in MLComputer isolate");
  }
  return cachedEmbeddings;
}

Future<rust_usearch.SemanticSearchExactCache> _ensureRustExactCache(
  _CachedImageEmbeddings cachedEmbeddings,
) async {
  final rustExactCache = cachedEmbeddings.rustExactCache;
  if (rustExactCache != null && !rustExactCache.isDisposed) {
    return rustExactCache;
  }

  final newCache = await _createRustExactCache(cachedEmbeddings);
  cachedEmbeddings.rustExactCache = newCache;
  return newCache;
}

Future<rust_usearch.SemanticSearchExactCache> _createRustExactCache(
  _CachedImageEmbeddings cachedEmbeddings,
) async {
  await _ensureRustLoaded();
  final imageFileIds = Int64List.fromList(
    cachedEmbeddings.embeddingVectors
        .map((embedding) => embedding.fileID)
        .toList(growable: false),
  );
  final imageEmbeddings = cachedEmbeddings.embeddingVectors
      .map((embedding) => Float32List.fromList(embedding.vector.toList()))
      .toList(growable: false);
  return rust_usearch.SemanticSearchExactCache(
    imageFileIds: imageFileIds,
    imageEmbeddings: imageEmbeddings,
  );
}

void _disposeIsolateCacheValue(dynamic value) {
  if (value is _CachedImageEmbeddings) {
    value.rustExactCache?.dispose();
    value.rustExactCache = null;
  }
}

Future<void> _ensureRustLoaded() async {
  final bool loaded = _isolateCache[_rustLibLoadedCacheKey] as bool? ?? false;
  if (!loaded) {
    await EntePhotosRust.init();
    _isolateCache[_rustLibLoadedCacheKey] = true;
  }
}

Future<void> _ensureRustDisposed() async {
  // Intentionally a no-op.
  //
  // Rust ML residency is owned by the feature isolate that prepared it.
  // The generic cache-clear path runs in multiple rust-using isolates, so
  // letting it call process-global ML teardown would allow unrelated isolates
  // to release indexing sessions they do not own. MLIndexingIsolate tracks
  // whether it prepared the runtime and releases it explicitly during its own
  // cleanup, even if the app mode or flags have changed since preparation.
}

Future<void> _ensureRustRuntimePrepared(Map<String, dynamic> args) async {
  // Configure execution behavior before any ONNX session is created.
  await rust_ml.setMlExecutionConfig(
    enableWebgpu: (args["enableWebGpu"] as bool?) ?? false,
  );
  final modelPaths = rust_ml.RustModelPaths(
    faceDetection: (args["faceDetectionModelPath"] as String?) ?? "",
    faceEmbedding: (args["faceEmbeddingModelPath"] as String?) ?? "",
    clipImage: (args["clipImageModelPath"] as String?) ?? "",
    clipText: (args["clipTextModelPath"] as String?) ?? "",
    petFaceDetection: (args["petFaceDetectionModelPath"] as String?) ?? "",
    petFaceEmbeddingDog:
        (args["petFaceEmbeddingDogModelPath"] as String?) ?? "",
    petFaceEmbeddingCat:
        (args["petFaceEmbeddingCatModelPath"] as String?) ?? "",
    petBodyDetection: (args["petBodyDetectionModelPath"] as String?) ?? "",
    petBodyEmbeddingDog:
        (args["petBodyEmbeddingDogModelPath"] as String?) ?? "",
    petBodyEmbeddingCat:
        (args["petBodyEmbeddingCatModelPath"] as String?) ?? "",
  );
  final modelPathsKey = _modelPathsCacheKey(modelPaths);
  final currentModelPathsKey =
      _isolateCache[_rustMlModelPathsCacheKey] as String?;
  if (currentModelPathsKey == modelPathsKey) {
    return;
  }

  final missingModelPaths = <String>[];
  if (modelPaths.faceDetection.trim().isEmpty) {
    missingModelPaths.add("faceDetectionModelPath");
  }
  if (modelPaths.faceEmbedding.trim().isEmpty) {
    missingModelPaths.add("faceEmbeddingModelPath");
  }
  if (modelPaths.clipImage.trim().isEmpty) {
    missingModelPaths.add("clipImageModelPath");
  }
  if (missingModelPaths.isNotEmpty) {
    throw Exception(
      "RustMLMissingModelPath: Missing required model paths: ${missingModelPaths.join(', ')}",
    );
  }

  await rust_ml.initMlRuntime(modelPaths: modelPaths);
  _isolateCache[_rustMlModelPathsCacheKey] = modelPathsKey;
}

Future<void> _releaseRustRuntime() async {
  final bool loaded = _isolateCache[_rustLibLoadedCacheKey] as bool? ?? false;
  if (!loaded) {
    return;
  }
  try {
    await rust_ml.releaseMlRuntime();
  } catch (_) {
    // no-op: indexing-model release is best-effort.
  }
  _isolateCache.remove(_rustMlModelPathsCacheKey);
}

String _modelPathsCacheKey(rust_ml.RustModelPaths modelPaths) {
  return [
    modelPaths.faceDetection,
    modelPaths.faceEmbedding,
    modelPaths.clipImage,
    modelPaths.clipText,
    modelPaths.petFaceDetection,
    modelPaths.petFaceEmbeddingDog,
    modelPaths.petFaceEmbeddingCat,
    modelPaths.petBodyDetection,
    modelPaths.petBodyEmbeddingDog,
    modelPaths.petBodyEmbeddingCat,
  ].join("|");
}
