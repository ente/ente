import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/store_clip_vector_db.dart";
import "package:photos/db/ml/usearch_clip_vector_db.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";

abstract class ClipVectorDB {
  static const int embeddingDimensions = 512;
  static const int embeddingBytesLength = embeddingDimensions * 4;

  static ClipVectorDB get instance => MLDataDB.isRustBackend
      ? StoreClipVectorDB.instance
      : UsearchClipVectorDB.instance;
  static ClipVectorDB get localGalleryInstance => MLDataDB.isRustBackend
      ? StoreClipVectorDB.localGalleryInstance
      : UsearchClipVectorDB.localGalleryInstance;

  Future<bool> isReady();
  Future<void> warmup();
  Future<List<QueryResult>> searchSimilaritiesWithinThreshold(
    List<double> query,
    double minimumSimilarity,
  );
  Future<Map<int, List<(int, double)>>> bulkSearchNearestForFiles(
    List<int> fileIDs, {
    required int count,
    required double maxDistance,
    required bool exact,
  });
}
