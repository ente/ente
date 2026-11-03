import "package:photos/db/ml/db.dart";
import "package:photos/services/machine_learning/semantic_search/dart_clip_similarity_scan.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/services/machine_learning/semantic_search/store_clip_similarity_scan.dart";

abstract class ClipSimilarityScan {
  static ClipSimilarityScan get instance => MLDataDB.isRustBackend
      ? StoreClipSimilarityScan.instance
      : DartClipSimilarityScan.instance;

  Future<Map<String, List<QueryResult>>> computeSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap,
  );
}
