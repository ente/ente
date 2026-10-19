import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/store_cluster_centroid_vector_db.dart";
import "package:photos/db/ml/usearch_cluster_centroid_vector_db.dart";

typedef ClusterCentroidMatches = ({
  List<(String, double)> matches,
  bool reachedCount,
});

abstract class ClusterCentroidVectorDB {
  static const int embeddingDimensions = 192;

  static ClusterCentroidVectorDB get instance => MLDataDB.isRustBackend
      ? StoreClusterCentroidVectorDB.instance
      : UsearchClusterCentroidVectorDB.instance;
  static ClusterCentroidVectorDB get localGalleryInstance =>
      MLDataDB.isRustBackend
      ? StoreClusterCentroidVectorDB.localGalleryInstance
      : UsearchClusterCentroidVectorDB.localGalleryInstance;

  Future<bool> isReady();
  Future<void> warmup();
  Future<List<List<(String, double)>>> bulkSearchNearestAllowed(
    List<List<double>> queries,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    int count = 10,
  });
  Future<Map<String, ClusterCentroidMatches>> bulkSearchNearestForClusters(
    Set<String> queryClusterIDs, {
    required Set<String> candidateClusterIDs,
    required int count,
    double? maxDistance,
  });
}
