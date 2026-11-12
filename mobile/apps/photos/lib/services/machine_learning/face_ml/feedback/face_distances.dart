import "package:photos/db/ml/db.dart";
import "package:photos/services/machine_learning/face_ml/feedback/dart_face_distances.dart";
import "package:photos/services/machine_learning/face_ml/feedback/store_face_distances.dart";

abstract class FaceDistances {
  static FaceDistances get instance => MLDataDB.isRustBackend
      ? StoreFaceDistances.instance
      : DartFaceDistances.instance;

  Future<List<(String, double)>> suggestByMedian(
    Set<String> personClusters,
    List<String> candidateClusterIDs, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  });

  Future<Map<String, (String, double)>> closestByMedianPerPerson(
    Map<String, Set<String>> personToClusters,
    Map<String, List<String>> personToCandidates, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  });

  Stream<List<(String, double)>?> distancesToPersons(
    List<(String, List<String>)> personFaces,
  );

  Future<Map<String, double>> maxSimilaritiesToPersons(
    String clusterID,
    Set<String> personIDs,
  );
}
