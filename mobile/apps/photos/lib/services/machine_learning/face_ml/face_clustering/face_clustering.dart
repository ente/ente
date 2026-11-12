import "package:photos/db/ml/db.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/dart_face_clustering.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/store_face_clustering.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";

abstract class FaceClustering {
  static FaceClustering get instance => MLDataDB.isRustBackend
      ? StoreFaceClustering.instance
      : DartFaceClustering.instance;
  static FaceClustering get localGalleryInstance => MLDataDB.isRustBackend
      ? StoreFaceClustering.localGalleryInstance
      : DartFaceClustering.localGalleryInstance;

  Future<void> clusterAllFaces({
    required Map<int, int> fileIDToCreationTime,
    required Map<String, List<String>> rejectedClusterIDsByFaceID,
    required MlRunControl control,
  });

  Future<Map<String, String>> reclusterFaces(
    List<String> faceIDs, {
    required Map<int, int> fileIDToCreationTime,
    required double distanceThreshold,
  });
}
