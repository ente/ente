import "dart:math" show Random, max;

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:ml_linalg/linalg.dart";
import "package:photos/db/ml/dart_db.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/services/machine_learning/face_ml/feedback/face_distances.dart";

class DartFaceDistances implements FaceDistances {
  static final Logger _logger = Logger("DartFaceDistances");

  final DartMLDataDB _mlDataDB;

  DartFaceDistances._(this._mlDataDB);

  static final instance = DartFaceDistances._(DartMLDataDB.instance);

  @override
  Future<List<(String, double)>> suggestByMedian(
    Set<String> personClusters,
    List<String> candidateClusterIDs, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  }) async {
    final List<Uint8List> personEmbeddingsProto = [];
    for (final clusterID in personClusters) {
      final Iterable<Uint8List> embeddings = await _mlDataDB
          .getFaceEmbeddingsForCluster(clusterID);
      personEmbeddingsProto.addAll(embeddings);
    }
    final sampledEmbeddingsProto = randomSampleWithoutReplacement(
      personEmbeddingsProto,
      sampleSize,
    );
    final List<Vector> sampledEmbeddings = sampledEmbeddingsProto
        .map(
          (embedding) => Vector.fromList(
            EVector.fromBuffer(embedding).values,
            dtype: DType.float32,
          ),
        )
        .toList(growable: false);

    final List<(String, double)> suggestionsMedian = [];
    double minMedianDistance = maxDistance;
    for (final otherClusterId in candidateClusterIDs) {
      final Iterable<Uint8List> otherEmbeddingsProto = await _mlDataDB
          .getFaceEmbeddingsForCluster(otherClusterId);
      final sampledOtherEmbeddingsProto = randomSampleWithoutReplacement(
        otherEmbeddingsProto,
        sampleSize,
      );
      final List<Vector> sampledOtherEmbeddings = sampledOtherEmbeddingsProto
          .map(
            (embedding) => Vector.fromList(
              EVector.fromBuffer(embedding).values,
              dtype: DType.float32,
            ),
          )
          .toList(growable: false);

      final List<double> distances = [];
      for (final otherEmbedding in sampledOtherEmbeddings) {
        for (final embedding in sampledEmbeddings) {
          distances.add(1 - embedding.dot(otherEmbedding));
        }
      }
      distances.sort();
      final double medianDistance = distances[distances.length ~/ 2];
      if (medianDistance < minMedianDistance) {
        suggestionsMedian.add((otherClusterId, medianDistance));
        minMedianDistance = medianDistance;
        if (medianDistance < goodDistance) {
          break;
        }
      }
    }
    return suggestionsMedian;
  }

  @override
  Future<Map<String, (String, double)>> closestByMedianPerPerson(
    Map<String, Set<String>> personToClusters,
    Map<String, List<String>> personToCandidates, {
    required int sampleSize,
    required double maxDistance,
    required double goodDistance,
  }) async {
    final closestByPerson = <String, (String, double)>{};
    final clustersNeededForMedian = <String>{};
    for (final entry in personToCandidates.entries) {
      clustersNeededForMedian.addAll(entry.value);
      clustersNeededForMedian.addAll(personToClusters[entry.key]!);
    }
    final embeddingsByCluster = await _mlDataDB.getFaceEmbeddingsForClusters(
      clustersNeededForMedian,
    );
    final sampledVectorsByCluster = <String, List<Vector>>{};

    List<Vector> getSampledVectors(String clusterID) {
      final cached = sampledVectorsByCluster[clusterID];
      if (cached != null) {
        return cached;
      }
      final embeddingsProto =
          embeddingsByCluster[clusterID] ?? const <Uint8List>[];
      if (embeddingsProto.isEmpty) {
        sampledVectorsByCluster[clusterID] = const [];
        return const [];
      }
      final sampledEmbeddingsProto = randomSampleWithoutReplacement(
        embeddingsProto,
        sampleSize,
      );
      final sampledVectors = sampledEmbeddingsProto
          .map(
            (embedding) => Vector.fromList(
              EVector.fromBuffer(embedding).values,
              dtype: DType.float32,
            ),
          )
          .toList(growable: false);
      sampledVectorsByCluster[clusterID] = sampledVectors;
      return sampledVectors;
    }

    for (final entry in personToCandidates.entries) {
      final personID = entry.key;
      final candidateClusterIDs = entry.value;
      final personClusters = personToClusters[personID]!;
      final personEmbeddingsProto = <Uint8List>[];
      for (final personClusterID in personClusters) {
        final embeddingsForCluster =
            embeddingsByCluster[personClusterID] ?? const <Uint8List>[];
        personEmbeddingsProto.addAll(embeddingsForCluster);
      }
      if (personEmbeddingsProto.isEmpty) {
        continue;
      }
      final sampledPersonEmbeddingsProto = randomSampleWithoutReplacement(
        personEmbeddingsProto,
        sampleSize,
      );
      final sampledPersonEmbeddings = sampledPersonEmbeddingsProto
          .map(
            (embedding) => Vector.fromList(
              EVector.fromBuffer(embedding).values,
              dtype: DType.float32,
            ),
          )
          .toList(growable: false);
      if (sampledPersonEmbeddings.isEmpty) {
        continue;
      }

      double minMedianDistance = maxDistance;
      (String, double)? bestMedianSuggestion;
      for (final otherClusterID in candidateClusterIDs) {
        final sampledOtherEmbeddings = getSampledVectors(otherClusterID);
        if (sampledOtherEmbeddings.isEmpty) {
          continue;
        }
        final distances = <double>[];
        for (final otherEmbedding in sampledOtherEmbeddings) {
          for (final personEmbedding in sampledPersonEmbeddings) {
            distances.add(1 - personEmbedding.dot(otherEmbedding));
          }
        }
        if (distances.isEmpty) {
          continue;
        }
        distances.sort();
        final medianDistance = distances[distances.length ~/ 2];
        if (medianDistance < minMedianDistance) {
          minMedianDistance = medianDistance;
          bestMedianSuggestion = (otherClusterID, medianDistance);
          if (medianDistance < goodDistance) {
            break;
          }
        }
      }
      if (bestMedianSuggestion != null) {
        closestByPerson[personID] = bestMedianSuggestion;
      }
    }
    return closestByPerson;
  }

  @override
  Stream<List<(String, double)>?> distancesToPersons(
    List<(String, List<String>)> personFaces,
  ) async* {
    final Map<String, Vector> personAverages = {};
    for (final (personID, faceIDs) in personFaces) {
      Vector? personAvg = personAverages[personID];
      if (personAvg == null) {
        personAvg = await _getPersonAvg(personID);
        if (personAvg == null) {
          yield null;
          continue;
        }
        personAverages[personID] = personAvg;
      }
      final faceIdToEmbeddingMap = await _mlDataDB.getFaceEmbeddingMapForFaces(
        faceIDs,
      );
      final faceIdToVectorMap = faceIdToEmbeddingMap.map(
        (key, value) => MapEntry(
          key,
          Vector.fromList(
            EVector.fromBuffer(value).values,
            dtype: DType.float32,
          ),
        ),
      );
      yield [
        for (final entry in faceIdToVectorMap.entries)
          (entry.key, 1 - personAvg.dot(entry.value)),
      ];
    }
  }

  @override
  Future<Map<String, double>> maxSimilaritiesToPersons(
    String clusterID,
    Set<String> personIDs,
  ) async {
    final allClusterSummary = await _mlDataDB.getAllClusterSummary();
    final clusterEmbeddingData = allClusterSummary[clusterID]?.$1;
    if (clusterEmbeddingData == null) {
      return {};
    }
    final Vector clusterEmbedding = Vector.fromList(
      EVector.fromBuffer(clusterEmbeddingData).values,
      dtype: DType.float32,
    );

    final clusterToPerson = await _mlDataDB.getClusterIDToPersonID();
    clusterToPerson.removeWhere((_, personID) => !personIDs.contains(personID));
    allClusterSummary.removeWhere(
      (key, value) => !clusterToPerson.containsKey(key),
    );
    final Map<String, Vector> allClusterEmbeddings = allClusterSummary.map(
      (key, value) => MapEntry(
        key,
        Vector.fromList(
          EVector.fromBuffer(value.$1).values,
          dtype: DType.float32,
        ),
      ),
    );

    final Map<String, double> personToMaxSimilarity = {};
    for (final entry in allClusterEmbeddings.entries) {
      final personID = clusterToPerson[entry.key]!;
      final similarity = clusterEmbedding.dot(entry.value);
      personToMaxSimilarity[personID] = max(
        personToMaxSimilarity[personID] ?? double.negativeInfinity,
        similarity,
      );
    }
    return personToMaxSimilarity;
  }

  Future<Vector?> _getPersonAvg(String personID) async {
    final w = (kDebugMode ? EnteWatch('_getPersonAvg') : null)?..start();
    final personClusters = await _mlDataDB.getPersonClusterIDs(personID);
    w?.log('got person clusters');
    final Map<String, (Uint8List, int)> personClusterToSummary = await _mlDataDB
        .getClusterToClusterSummary(personClusters);
    w?.log('got cluster summaries');

    for (final clusterID in personClusters.toSet()) {
      if (!personClusterToSummary.containsKey(clusterID)) {
        _logger.warning('missing summary for $clusterID');
        personClusters.remove(clusterID);
      }
    }
    if (personClusters.isEmpty) {
      _logger.warning('No person clusters with summary found');
      return null;
    }

    int personEmbeddingsCount = 0;
    for (final clusterID in personClusters) {
      personEmbeddingsCount += personClusterToSummary[clusterID]!.$2;
    }

    Vector personAvg = Vector.filled(192, 0);
    for (final personClusterID in personClusters) {
      final personClusterBlob = personClusterToSummary[personClusterID]!.$1;
      final personClusterAvg = Vector.fromList(
        EVector.fromBuffer(personClusterBlob).values,
        dtype: DType.float32,
      );
      final clusterWeight =
          personClusterToSummary[personClusterID]!.$2 / personEmbeddingsCount;
      personAvg += personClusterAvg * clusterWeight;
    }
    w?.log('calculated person avg');
    return personAvg;
  }
}

List<S> randomSampleWithoutReplacement<S>(
  Iterable<S> embeddings,
  int sampleSize,
) {
  final random = Random();

  if (sampleSize >= embeddings.length) {
    return embeddings.toList();
  }

  if (sampleSize > embeddings.length / 2) {
    final List<S> shuffled = List<S>.from(embeddings)..shuffle(random);
    return shuffled.take(sampleSize).toList(growable: false);
  }

  final selectedIndices = <int>{};
  final sampledEmbeddings = <S>[];
  while (sampledEmbeddings.length < sampleSize) {
    final int index = random.nextInt(embeddings.length);
    if (!selectedIndices.contains(index)) {
      selectedIndices.add(index);
      sampledEmbeddings.add(embeddings.elementAt(index));
    }
  }

  return sampledEmbeddings;
}
