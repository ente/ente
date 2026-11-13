import "package:photos/db/ml/rust_db.dart";
import "package:photos/services/machine_learning/face_ml/feedback/face_distances.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;

class StoreFaceDistances implements FaceDistances {
  final RustMLDataDB _mlDataDB;

  StoreFaceDistances._(this._mlDataDB);

  static final instance = StoreFaceDistances._(RustMLDataDB.instance);

  @override
  Future<List<(String, double)>> suggestByMedian(
    Set<String> personClusters,
    List<String> candidateClusterIDs, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  }) async {
    final suggestions = await _suggestByMedian(
      [
        rust.MedianQuery(
          personClusterIds: personClusters.toList(),
          candidateClusterIds: candidateClusterIDs,
        ),
      ],
      sampleSize: sampleSize,
      maxDistance: maxDistance,
      goodDistance: goodDistance,
    );
    return suggestions.single;
  }

  @override
  Future<Map<String, (String, double)>> closestByMedianPerPerson(
    Map<String, Set<String>> personToClusters,
    Map<String, List<String>> personToCandidates, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  }) async {
    final personIDs = personToCandidates.keys.toList(growable: false);
    final suggestions = await _suggestByMedian(
      [
        for (final personID in personIDs)
          rust.MedianQuery(
            personClusterIds: personToClusters[personID]!.toList(),
            candidateClusterIds: personToCandidates[personID]!,
          ),
      ],
      sampleSize: sampleSize,
      maxDistance: maxDistance,
      goodDistance: goodDistance,
    );
    return {
      for (final (index, personID) in personIDs.indexed)
        if (suggestions[index].isNotEmpty) personID: suggestions[index].last,
    };
  }

  @override
  Stream<List<(String, double)>?> distancesToPersons(
    List<(String, List<String>)> personFaces,
  ) async* {
    final distances = await (await _mlDataDB.store).distancesToPersonAverages(
      requests: [
        for (final (personID, faceIDs) in personFaces)
          rust.PersonFaces(personId: personID, faceIds: faceIDs),
      ],
    );
    for (final faceDistances in distances) {
      yield faceDistances
          ?.map((faceDistance) => (faceDistance.faceId, faceDistance.distance))
          .toList(growable: false);
    }
  }

  @override
  Future<Map<String, double>> maxSimilaritiesToPersons(
    String clusterID,
    Set<String> personIDs,
  ) async {
    return (await _mlDataDB.store).maxSimilaritiesToPersons(
      clusterId: clusterID,
      personIds: personIDs.toList(growable: false),
    );
  }

  Future<List<List<(String, double)>>> _suggestByMedian(
    List<rust.MedianQuery> queries, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  }) async {
    final suggestions = await (await _mlDataDB.store).suggestClustersByMedian(
      queries: queries,
      sampleSize: sampleSize,
      maxDistance: maxDistance,
      goodDistance: goodDistance,
    );
    return [
      for (final closer in suggestions)
        [
          for (final suggestion in closer)
            (suggestion.clusterId, suggestion.distance),
        ],
    ];
  }
}
