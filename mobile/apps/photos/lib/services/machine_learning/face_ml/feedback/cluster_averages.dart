abstract class ClusterAverages {
  Set<String> get clusterIDs;

  Future<List<List<(String, double)>>> searchNearest(
    List<String> queryClusterIDs,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    required int count,
  });

  Future<List<(String, double, String)>> suggestByMean(
    Set<String> personClusters,
    Set<String> ignoredClusters,
    double maxClusterDistance, {
    Map<String, Set<String>>? personClusterToIgnoredClusters,
  });
}
