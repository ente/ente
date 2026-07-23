part of "package:photos/services/wrapped/candidate_builders.dart";

/// Shared helper that picks a diverse, people-forward set of media for
/// Wrapped cards while filtering obvious screenshots/documents.
class WrappedMediaSelector {
  const WrappedMediaSelector._();

  static const String _kScreenshotQuery =
      "Screenshot of a phone or computer screen";
  static const String _kDocumentQuery =
      "Scanned document, receipt or whiteboard photo";
  static const String _kPeopleDelightQuery =
      "Candid photograph of friends laughing together";

  static const double _kBaseScoreFloor = 1.0;
  static const double _kFavoriteBoost = 0.25;
  static const double _kNamedPersonBaseBoost = 0.22;
  static const double _kNamedPersonExtraBoost = 0.06;
  static const double _kFacePresenceBoost = 0.05;
  static const double _kPeopleDelightWeight = 0.25;
  static const double _kFaceCountWeight = 0.02;

  static const double _kScreenshotPenaltyStart = 0.19;
  static const double _kDocumentPenaltyStart = 0.18;
  static const double _kScreenshotPenaltyWeight = 1.15;
  static const double _kDocumentPenaltyWeight = 0.95;
  static const double _kScreenshotHardPenalty = 0.75;
  static const double _kScreenshotHardCutoff = 0.34;

  static const double _kSimilarityPenaltyStart = 0.70;
  static const double _kSimilarityPenaltyWeight = 3.0;
  static const double _kSimilarityRejectThreshold = 0.92;

  static const double _kTimePenaltyWeight = 0.8;

  static final Expando<_MediaSelectorCache> _cache =
      Expando<_MediaSelectorCache>("wrappedMediaSelectorCache");

  static Set<String> get requiredTextQueries {
    return <String>{_kScreenshotQuery, _kDocumentQuery, _kPeopleDelightQuery};
  }

  static List<MediaRef> selectMediaRefs({
    required WrappedEngineContext context,
    required Iterable<int> candidateUploadedFileIDs,
    int maxCount = 3,
    Map<int, double>? scoreHints,
    bool preferNamedPeople = false,
    Duration? minimumSpacing,
    bool enforceDistinctness = true,
    bool avoidPreviouslySelected = true,
    bool reserveSelected = true,
  }) {
    final List<int> ids = select(
      context: context,
      candidateUploadedFileIDs: candidateUploadedFileIDs,
      maxCount: maxCount,
      scoreHints: scoreHints,
      preferNamedPeople: preferNamedPeople,
      minimumSpacing: minimumSpacing,
      enforceDistinctness: enforceDistinctness,
      avoidPreviouslySelected: avoidPreviouslySelected,
      reserveSelected: reserveSelected,
    );
    return ids.map(MediaRef.new).toList(growable: false);
  }

  static List<int> select({
    required WrappedEngineContext context,
    required Iterable<int> candidateUploadedFileIDs,
    int maxCount = 3,
    Map<int, double>? scoreHints,
    bool preferNamedPeople = false,
    Duration? minimumSpacing,
    bool enforceDistinctness = true,
    bool avoidPreviouslySelected = true,
    bool reserveSelected = true,
  }) {
    if (maxCount <= 0) {
      return const <int>[];
    }

    final _MediaSelectorCache cache = _cache[context] ??=
        _MediaSelectorCache.fromEngineContext(context);

    final Set<int> seen = <int>{};
    final List<_ScoredCandidate> candidates = <_ScoredCandidate>[];
    for (final int id in candidateUploadedFileIDs) {
      if (id <= 0 || !seen.add(id)) {
        continue;
      }
      if (avoidPreviouslySelected && cache.isUsed(id)) {
        continue;
      }
      final _MediaAsset? asset = cache.assetFor(id);
      if (asset == null) {
        continue;
      }
      final double hint = scoreHints?[id] ?? 0.0;
      candidates.add(
        _ScoredCandidate(
          asset: asset,
          initialScore: hint,
          preferNamedPeople: preferNamedPeople,
        ),
      );
    }

    if (candidates.isEmpty) {
      return const <int>[];
    }

    candidates.sort(
      (_ScoredCandidate a, _ScoredCandidate b) =>
          b.baseScore.compareTo(a.baseScore),
    );

    final List<_ScoredCandidate> selected = <_ScoredCandidate>[];
    final int? spacingMicros = minimumSpacing?.inMicroseconds;
    final int targetCount = math.min(maxCount, candidates.length);

    while (selected.length < targetCount && candidates.isNotEmpty) {
      _ScoredCandidate? bestCandidate;
      double bestScore = -double.infinity;

      for (final _ScoredCandidate candidate in candidates) {
        final double score = candidate.adjustedScore(
          selected,
          spacingMicros: spacingMicros,
          enforceDistinctness: enforceDistinctness,
        );
        if (score > bestScore + 1e-6) {
          bestScore = score;
          bestCandidate = candidate;
        }
      }

      if (bestCandidate == null) {
        break;
      }

      selected.add(bestCandidate);
      candidates.remove(bestCandidate);
    }

    final List<int> chosen = selected
        .map((_ScoredCandidate candidate) => candidate.asset.uploadedFileID)
        .toList(growable: false);
    if (reserveSelected && chosen.isNotEmpty) {
      cache.markUsed(chosen);
    }
    return chosen;
  }

  static void reserveUploadedFileIDs({
    required WrappedEngineContext context,
    required Iterable<int> uploadedFileIDs,
  }) {
    final _MediaSelectorCache cache = _cache[context] ??=
        _MediaSelectorCache.fromEngineContext(context);
    cache.markUsed(uploadedFileIDs);
  }
}

class _ScoredCandidate {
  _ScoredCandidate({
    required this.asset,
    required double initialScore,
    required bool preferNamedPeople,
  }) : baseScore = _computeBaseScore(
         asset: asset,
         initialScore: initialScore,
         preferNamedPeople: preferNamedPeople,
       );

  final _MediaAsset asset;
  final double baseScore;

  double adjustedScore(
    List<_ScoredCandidate> alreadySelected, {
    int? spacingMicros,
    required bool enforceDistinctness,
  }) {
    double score = baseScore;

    for (final _ScoredCandidate other in alreadySelected) {
      if (enforceDistinctness) {
        final double? similarity = asset.embeddingSimilarity(other.asset);
        if (similarity != null) {
          if (similarity >= WrappedMediaSelector._kSimilarityRejectThreshold) {
            return double.negativeInfinity;
          }
          if (similarity >= WrappedMediaSelector._kSimilarityPenaltyStart) {
            final double proximity =
                ((similarity - WrappedMediaSelector._kSimilarityPenaltyStart) /
                        (WrappedMediaSelector._kSimilarityRejectThreshold -
                            WrappedMediaSelector._kSimilarityPenaltyStart))
                    .clamp(0.0, 1.0);
            final double multiplier =
                1 - proximity * WrappedMediaSelector._kSimilarityPenaltyWeight;
            score *= math.max(multiplier, 0.05);
          }
        }
      }

      if (spacingMicros != null &&
          spacingMicros > 0 &&
          asset.captureMicros > 0 &&
          other.asset.captureMicros > 0) {
        final int delta = (asset.captureMicros - other.asset.captureMicros)
            .abs();
        if (delta < spacingMicros) {
          final double ratio =
              1 - (delta.toDouble() / math.max(spacingMicros.toDouble(), 1.0));
          score -= ratio * WrappedMediaSelector._kTimePenaltyWeight;
        }
      }
    }

    return score;
  }

  static double _computeBaseScore({
    required _MediaAsset asset,
    required double initialScore,
    required bool preferNamedPeople,
  }) {
    double score = WrappedMediaSelector._kBaseScoreFloor + initialScore;
    if (!score.isFinite || score.isNaN) {
      score = WrappedMediaSelector._kBaseScoreFloor;
    }

    if (asset.isFavorite) {
      score += WrappedMediaSelector._kFavoriteBoost;
    }

    if (preferNamedPeople) {
      if (asset.namedPersonCount > 0) {
        score += WrappedMediaSelector._kNamedPersonBaseBoost;
        final int extras = asset.namedPersonCount - 1;
        if (extras > 0) {
          score +=
              math.min(extras, 4) *
              WrappedMediaSelector._kNamedPersonExtraBoost;
        }
        if (asset.peopleDelightScore > 0) {
          score +=
              asset.peopleDelightScore *
              WrappedMediaSelector._kPeopleDelightWeight;
        }
      } else if (asset.totalFaceCount > 0) {
        score += WrappedMediaSelector._kFacePresenceBoost;
      }
    } else if (asset.totalFaceCount > 1) {
      score +=
          math.min(asset.totalFaceCount, 4) *
          WrappedMediaSelector._kFaceCountWeight;
    }

    if (asset.documentSimilarity > 0) {
      score -= _penalize(
        asset.documentSimilarity,
        WrappedMediaSelector._kDocumentPenaltyStart,
        WrappedMediaSelector._kDocumentPenaltyWeight,
      );
    }

    if (asset.screenshotSimilarity > 0) {
      score -= _penalize(
        asset.screenshotSimilarity,
        WrappedMediaSelector._kScreenshotPenaltyStart,
        WrappedMediaSelector._kScreenshotPenaltyWeight,
      );
      if (asset.screenshotSimilarity >=
          WrappedMediaSelector._kScreenshotHardCutoff) {
        score -= WrappedMediaSelector._kScreenshotHardPenalty;
      }
    }

    return score;
  }

  static double _penalize(
    double similarity,
    double startThreshold,
    double weight,
  ) {
    if (similarity <= startThreshold) {
      return 0.0;
    }
    final double excess = similarity - startThreshold;
    return excess * weight;
  }
}

class _MediaSelectorCache {
  _MediaSelectorCache._({required Map<int, _MediaAsset> assets})
    : _assets = assets,
      _usedUploadedFileIDs = <int>{};

  final Map<int, _MediaAsset> _assets;
  final Set<int> _usedUploadedFileIDs;

  _MediaAsset? assetFor(int uploadedFileID) {
    return _assets[uploadedFileID];
  }

  bool isUsed(int uploadedFileID) {
    return uploadedFileID > 0 && _usedUploadedFileIDs.contains(uploadedFileID);
  }

  void markUsed(Iterable<int> uploadedFileIDs) {
    for (final int id in uploadedFileIDs) {
      if (id > 0) {
        _usedUploadedFileIDs.add(id);
      }
    }
  }

  factory _MediaSelectorCache.fromEngineContext(WrappedEngineContext context) {
    final Map<int, EnteFile> fileById = <int, EnteFile>{
      for (final EnteFile file in context.files)
        if (file.uploadedFileID != null) file.uploadedFileID!: file,
    };
    final Set<int> archivedCollectionIDs = context.archivedCollectionIDs;

    final Map<int, _EmbeddingVector> imageVectors = <int, _EmbeddingVector>{};
    context.aesthetics.clipEmbeddings.forEach((
      int fileID,
      List<double> values,
    ) {
      if (values.isEmpty) {
        return;
      }
      final _EmbeddingVector? vector = _EmbeddingVector.tryFromList(values);
      if (vector == null) {
        return;
      }
      imageVectors[fileID] = vector;
    });

    final Set<int> favorites = Set<int>.from(context.favoriteUploadedFileIDs);

    final Map<int, _PeopleCounts> peopleCounts = _buildPeopleCounts(
      context.people,
    );

    final _EmbeddingVector? screenshotQuery = _vectorForTextQuery(
      context,
      WrappedMediaSelector._kScreenshotQuery,
    );
    final _EmbeddingVector? documentQuery = _vectorForTextQuery(
      context,
      WrappedMediaSelector._kDocumentQuery,
    );
    final _EmbeddingVector? peopleDelightQuery = _vectorForTextQuery(
      context,
      WrappedMediaSelector._kPeopleDelightQuery,
    );

    final Map<int, _MediaAsset> assets = <int, _MediaAsset>{};
    fileById.forEach((int id, EnteFile file) {
      final int? collectionID = file.collectionID;
      if (collectionID != null &&
          archivedCollectionIDs.contains(collectionID)) {
        return;
      }
      if (file.magicMetadata.visibility == archiveVisibility) {
        return;
      }
      final _EmbeddingVector? embedding = imageVectors[id];
      final _PeopleCounts counts = peopleCounts[id] ?? const _PeopleCounts();
      final double screenshotSim = embedding == null || screenshotQuery == null
          ? 0.0
          : _cosineSimilarity(embedding, screenshotQuery);
      final double documentSim = embedding == null || documentQuery == null
          ? 0.0
          : _cosineSimilarity(embedding, documentQuery);
      final double peopleDelight =
          embedding == null || peopleDelightQuery == null
          ? 0.0
          : _cosineSimilarity(embedding, peopleDelightQuery);

      assets[id] = _MediaAsset(
        uploadedFileID: id,
        captureMicros: file.creationTime ?? 0,
        embedding: embedding,
        isFavorite: favorites.contains(id),
        namedPersonCount: counts.namedCount,
        totalFaceCount: counts.totalFaces,
        screenshotSimilarity: screenshotSim,
        documentSimilarity: documentSim,
        peopleDelightScore: peopleDelight,
      );
    });

    return _MediaSelectorCache._(assets: assets);
  }

  static Map<int, _PeopleCounts> _buildPeopleCounts(
    WrappedPeopleContext context,
  ) {
    if (!context.hasPeople) {
      return const <int, _PeopleCounts>{};
    }
    final Map<int, _PeopleCounts> counts = <int, _PeopleCounts>{};

    for (final WrappedPeopleFile file in context.files) {
      if (file.faces.isEmpty) {
        continue;
      }

      final Set<String> namedPersonIds = <String>{};
      int totalFaces = 0;

      for (final WrappedFaceRef face in file.faces) {
        totalFaces += 1;
        final String? personID = face.personID;
        if (personID == null) {
          continue;
        }
        final WrappedPersonEntry? entry = context.persons[personID];
        if (entry == null || entry.isHidden) {
          continue;
        }
        namedPersonIds.add(personID);
      }

      if (totalFaces == 0 && namedPersonIds.isEmpty) {
        continue;
      }

      counts[file.uploadedFileID] = _PeopleCounts(
        namedCount: namedPersonIds.length,
        totalFaces: totalFaces,
      );
    }
    return counts;
  }

  static _EmbeddingVector? _vectorForTextQuery(
    WrappedEngineContext context,
    String query,
  ) {
    final List<double>? values = context.aesthetics.textEmbeddings[query];
    if (values == null || values.isEmpty) {
      return null;
    }
    return _EmbeddingVector.tryFromList(values);
  }
}

class _MediaAsset {
  const _MediaAsset({
    required this.uploadedFileID,
    required this.captureMicros,
    required this.embedding,
    required this.isFavorite,
    required this.namedPersonCount,
    required this.totalFaceCount,
    required this.screenshotSimilarity,
    required this.documentSimilarity,
    required this.peopleDelightScore,
  });

  final int uploadedFileID;
  final int captureMicros;
  final _EmbeddingVector? embedding;
  final bool isFavorite;
  final int namedPersonCount;
  final int totalFaceCount;
  final double screenshotSimilarity;
  final double documentSimilarity;
  final double peopleDelightScore;

  double? embeddingSimilarity(_MediaAsset other) {
    final _EmbeddingVector? a = embedding;
    final _EmbeddingVector? b = other.embedding;
    if (a == null || b == null) {
      return null;
    }
    return _cosineSimilarity(a, b);
  }
}

class _EmbeddingVector {
  _EmbeddingVector._({required this.vector, required this.norm});

  static _EmbeddingVector? tryFromList(List<double> values) {
    final Vector vector = Vector.fromList(values, dtype: DType.float32);
    final double norm = vector.norm();
    if (!norm.isFinite || norm <= 0) {
      return null;
    }
    return _EmbeddingVector._(vector: vector, norm: norm);
  }

  final Vector vector;
  final double norm;

  bool get hasMagnitude => norm > 0;
}

class _PeopleCounts {
  const _PeopleCounts({this.namedCount = 0, this.totalFaces = 0});

  final int namedCount;
  final int totalFaces;
}

double _cosineSimilarity(_EmbeddingVector a, _EmbeddingVector b) {
  if (!a.hasMagnitude || !b.hasMagnitude) {
    return 0.0;
  }
  final double denom = a.norm * b.norm;
  if (denom <= 0) {
    return 0.0;
  }
  return a.vector.dot(b.vector) / denom;
}
