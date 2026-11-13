import "dart:typed_data" show Float32List;

import "package:photos/db/ml/rust_db.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/semantic_search/clip_similarity_scan.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

class StoreClipSimilarityScan implements ClipSimilarityScan {
  StoreClipSimilarityScan._();

  static final instance = StoreClipSimilarityScan._();

  RustMLDataDB get _mlDataDB => isLocalGalleryMode
      ? RustMLDataDB.localGalleryInstance
      : RustMLDataDB.instance;

  @override
  Future<Map<String, List<QueryResult>>> computeSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap,
  ) async {
    final queries = textQueryToEmbeddingMap.keys.toList(growable: false);
    final similarities = await (await _mlDataDB.store).scanClipSimilarities(
      queries: [
        for (final query in queries)
          rust.ClipQuery(
            embedding: Float32List.fromList(textQueryToEmbeddingMap[query]!),
            minimumSimilarity: minimumSimilarityMap[query]!,
          ),
      ],
    );
    return {
      for (final (index, query) in queries.indexed)
        query: [
          for (final similarity in similarities[index])
            QueryResult(similarity.fileId, similarity.similarity),
        ],
    };
  }
}
