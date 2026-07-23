part of 'package:photos/services/wrapped/candidate_builders.dart';

class AestheticsCandidateBuilder extends WrappedCandidateBuilder {
  const AestheticsCandidateBuilder();

  static const double _kCountThreshold = 0.20;
  static const double _kDisplayThreshold = 0.225;
  static const double _kMonochromeCountThreshold = 0.175;
  static const double _kMonochromeDisplayThreshold = 0.175;
  static const double _kTopWowPerQueryThreshold = 0.175;
  static const double _kTopWowHighlightThreshold = 0.225;
  static const double _kColorScoreBoostMultiplier = 4.0;
  static const double _kBlurryFaceBlurThreshold = 50;
  static const int _kMaxMediaPerCard = 6;
  static const int _kMinBlurryFiles = 3;
  static const int _kMinColorBuckets = 2;
  static const int _kMinColorMatchesPerBucket = 10;
  static const int _kMinMonochromeMedia = 6;
  static const int _kTopWowMediaCount = 6;
  static const int _kTopWowCandidateMultiplier = 4;
  static const int _kTopWowMinIntersection = 3;

  static const List<_ColorSpec> _colorSpecs = <_ColorSpec>[
    _ColorSpec(
      displayName: "Red",
      query: "Photo strongly coloured red",
      hex: "#FF3B30",
    ),
    _ColorSpec(
      displayName: "Orange",
      query: "Photo strongly coloured orange",
      hex: "#FF9500",
    ),
    _ColorSpec(
      displayName: "Yellow",
      query: "Photo strongly coloured yellow",
      hex: "#FFCC00",
    ),
    _ColorSpec(
      displayName: "Green",
      query: "Photo strongly coloured green",
      hex: "#34C759",
    ),
    _ColorSpec(
      displayName: "Blue",
      query: "Photo strongly coloured blue",
      hex: "#007AFF",
    ),
    _ColorSpec(
      displayName: "Purple",
      query: "Photo strongly coloured purple",
      hex: "#AF52DE",
    ),
    _ColorSpec(
      displayName: "Pink",
      query: "Photo strongly coloured pink",
      hex: "#FF2D55",
    ),
  ];

  static const String _kMonochromeQuery = "Black and white photograph";

  static const List<String> _kWowQueries = <String>[
    "Award-winning photograph of everyday life",
    "Stunning candid photo with beautiful lighting",
    "Photo with cinematic composition and dramatic contrast",
  ];

  static Set<String> get requiredTextQueries {
    return <String>{
      for (final _ColorSpec spec in _colorSpecs) spec.query,
      _kMonochromeQuery,
      ..._kWowQueries,
    };
  }

  @override
  String get debugLabel => "aesthetics";

  @override
  Future<List<WrappedCard>> build(WrappedEngineContext context) async {
    if (!context.aesthetics.hasEmbeddings) {
      return const <WrappedCard>[];
    }

    final _AestheticsSnapshot snapshot = _AestheticsSnapshot.fromContext(
      context,
      colorSpecs: _colorSpecs,
    );
    if (!snapshot.hasEmbeddings) {
      return const <WrappedCard>[];
    }

    final List<WrappedCard> cards = <WrappedCard>[];

    final WrappedCard? blurryCard = _buildBlurryFacesCard(context, snapshot);
    if (blurryCard != null) {
      cards.add(blurryCard);
    }

    final WrappedCard? colorCard = _buildYearInColorCard(context, snapshot);
    if (colorCard != null) {
      cards.add(colorCard);
    }

    final WrappedCard? monochromeCard = _buildMonochromeCard(context, snapshot);
    if (monochromeCard != null) {
      cards.add(monochromeCard);
    }

    final WrappedCard? wowCard = _buildTopWowCard(context, snapshot);
    if (wowCard != null) {
      cards.add(wowCard);
    }

    return cards;
  }

  WrappedCard? _buildBlurryFacesCard(
    WrappedEngineContext context,
    _AestheticsSnapshot snapshot,
  ) {
    final List<_BlurryCandidate> candidates = snapshot.blurryCandidates;
    if (candidates.length < _kMinBlurryFiles) {
      return null;
    }

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      candidates.map((candidate) => candidate.uploadedFileID),
    );
    if (candidateIds.length < _kMinBlurryFiles) {
      return null;
    }

    final Set<int> candidateSet = candidateIds.toSet();
    final Map<int, double> scoreHints = <int, double>{
      for (final _BlurryCandidate candidate in candidates)
        if (candidateSet.contains(candidate.uploadedFileID))
          candidate.uploadedFileID: candidate.faceScore,
    };
    final int maxMediaCount = math.min(_kMaxMediaPerCard, candidateIds.length);

    final List<MediaRef> mediaRefs = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: maxMediaCount,
      scoreHints: scoreHints,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 21),
    );

    if (mediaRefs.isEmpty) {
      return null;
    }

    final Map<int, _BlurryCandidate> candidateById = <int, _BlurryCandidate>{
      for (final _BlurryCandidate candidate in candidates)
        candidate.uploadedFileID: candidate,
    };
    final List<_BlurryCandidate> selectedCandidates = mediaRefs
        .map((MediaRef ref) => candidateById[ref.uploadedFileID])
        .whereType<_BlurryCandidate>()
        .toList(growable: false);

    if (selectedCandidates.isEmpty) {
      return null;
    }

    final Set<String> nameSet = <String>{
      for (final _BlurryCandidate candidate in selectedCandidates)
        ...candidate.personNames,
    }..removeWhere((String name) => name.isEmpty);

    final double averageBlur = _average(
      selectedCandidates
          .map((candidate) => candidate.blurScore)
          .toList(growable: false),
    );
    final double averageScore = _average(
      selectedCandidates
          .map((candidate) => candidate.faceScore)
          .toList(growable: false),
    );

    final Map<String, Object?> meta = <String, Object?>{
      "totalCandidates": candidates.length,
      "detailChips": const <String>[],
      if (nameSet.isNotEmpty) "personNames": nameSet.toList(growable: false),
      "averageBlur": averageBlur,
      "averageFaceScore": averageScore,
    };

    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      maxMediaCount * 2,
    );

    return WrappedCard(
      type: WrappedCardType.blurryFaces,
      title: "Perfectly imperfect moments",
      subtitle: _buildBlurrySubtitle(nameSet),
      media: mediaRefs,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  WrappedCard? _buildYearInColorCard(
    WrappedEngineContext context,
    _AestheticsSnapshot snapshot,
  ) {
    final List<_ColorBucket> eligibleBuckets = snapshot.colorBuckets.where((
      bucket,
    ) {
      return bucket.matches.length >= _kMinColorMatchesPerBucket;
    }).toList()..sort((a, b) => b.matches.length.compareTo(a.matches.length));

    if (eligibleBuckets.length < _kMinColorBuckets) {
      return null;
    }

    final int highestCount = eligibleBuckets.first.matches.length;
    final List<_ColorBucket> tiedBuckets = eligibleBuckets
        .where((_ColorBucket bucket) => bucket.matches.length == highestCount)
        .toList(growable: false);
    final math.Random randomizer = math.Random(snapshot.year);
    final _ColorBucket chosenBucket = tiedBuckets.length <= 1
        ? tiedBuckets.first
        : tiedBuckets[randomizer.nextInt(tiedBuckets.length)];

    final List<_ClipMatch> prioritizedMatches = _limitMatches(<_ClipMatch>[
      ...chosenBucket.matches.where(
        (match) => match.score >= _kDisplayThreshold,
      ),
      ...chosenBucket.matches,
    ]);
    if (prioritizedMatches.length < _kMaxMediaPerCard) {
      return null;
    }

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      prioritizedMatches.map((match) => match.uploadedFileID),
    );
    if (candidateIds.length < _kMaxMediaPerCard) {
      return null;
    }
    final Set<int> candidateSet = candidateIds.toSet();
    final Map<int, double> scoreHints = <int, double>{
      for (final _ClipMatch match in prioritizedMatches)
        if (candidateSet.contains(match.uploadedFileID))
          match.uploadedFileID: math.max(
            0.0,
            (match.score - _kCountThreshold) * _kColorScoreBoostMultiplier,
          ),
    };

    final List<MediaRef> selection = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: _kMaxMediaPerCard,
      scoreHints: scoreHints,
      minimumSpacing: const Duration(days: 1),
      enforceDistinctness: false,
    );
    List<MediaRef> media = selection;

    if (media.length < _kMaxMediaPerCard) {
      final Set<int> seen = media.map((ref) => ref.uploadedFileID).toSet();
      final List<MediaRef> expanded = List<MediaRef>.from(
        media,
        growable: true,
      );
      for (final int id in candidateIds) {
        if (seen.add(id)) {
          expanded.add(MediaRef(id));
        }
        if (expanded.length >= _kMaxMediaPerCard) {
          break;
        }
      }
      if (expanded.length < _kMaxMediaPerCard) {
        return null;
      }
      media = expanded;
    }

    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      _kMaxMediaPerCard * 2,
    );
    final Map<String, Object?> meta = <String, Object?>{
      "dominantColor": chosenBucket.spec.displayName,
      if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
    };

    final String subtitle =
        "${chosenBucket.spec.displayName} stole your palette.";

    return WrappedCard(
      type: WrappedCardType.yearInColor,
      title: "Color crush",
      subtitle: subtitle,
      media: media,
      meta: meta,
    );
  }

  WrappedCard? _buildMonochromeCard(
    WrappedEngineContext context,
    _AestheticsSnapshot snapshot,
  ) {
    final List<_ClipMatch> matches = snapshot.monochromeMatches;
    if (matches.length < _kMinMonochromeMedia) {
      return null;
    }

    final List<_ClipMatch> prioritizedMatches = _limitMatches(<_ClipMatch>[
      ...matches.where((match) => match.score >= _kMonochromeDisplayThreshold),
      ...matches,
    ]);

    if (prioritizedMatches.length < _kMaxMediaPerCard) {
      return null;
    }

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      prioritizedMatches.map((match) => match.uploadedFileID),
    );
    if (candidateIds.length < _kMaxMediaPerCard) {
      return null;
    }

    final Set<int> candidateSet = candidateIds.toSet();
    final Map<int, double> scoreHints = <int, double>{
      for (final _ClipMatch match in prioritizedMatches)
        if (candidateSet.contains(match.uploadedFileID))
          match.uploadedFileID: match.score,
    };

    final List<MediaRef> primarySelection =
        WrappedMediaSelector.selectMediaRefs(
          context: context,
          candidateUploadedFileIDs: candidateIds,
          maxCount: _kMaxMediaPerCard,
          scoreHints: scoreHints,
          minimumSpacing: const Duration(days: 21),
          enforceDistinctness: false,
        );
    final List<MediaRef> media = List<MediaRef>.from(
      primarySelection,
      growable: true,
    );

    if (media.length < _kMaxMediaPerCard) {
      final Set<int> seen = media
          .map((MediaRef ref) => ref.uploadedFileID)
          .toSet();

      for (final int id in candidateIds) {
        if (seen.add(id)) {
          media.add(MediaRef(id));
        }
        if (media.length >= _kMaxMediaPerCard) {
          break;
        }
      }
    }

    if (media.length < _kMaxMediaPerCard) {
      return null;
    }

    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      _kMaxMediaPerCard * 2,
    );
    final Map<String, Object?> meta = <String, Object?>{
      "matchCount": matches.length,
      "detailChips": const <String>[],
      if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
    };

    return WrappedCard(
      type: WrappedCardType.monochrome,
      title: "Mono mood",
      subtitle: "You kept these black-and-white captures in rotation.",
      media: media,
      meta: meta,
    );
  }

  WrappedCard? _buildTopWowCard(
    WrappedEngineContext context,
    _AestheticsSnapshot snapshot,
  ) {
    final List<_ClipMatch> intersection = snapshot.topWowMatches;
    if (intersection.length < _kTopWowMinIntersection) {
      return null;
    }

    const int desiredCount = _kTopWowMediaCount;
    final Map<int, _ClipMatch> candidateMap = <int, _ClipMatch>{
      for (final _ClipMatch match in intersection) match.uploadedFileID: match,
    };

    if (candidateMap.length < desiredCount) {
      for (final String query in AestheticsCandidateBuilder._kWowQueries) {
        final List<_ClipMatch> queryMatches = snapshot
            .matchesForQuery(query)
            .toList(growable: false);
        for (final _ClipMatch match in queryMatches) {
          candidateMap.putIfAbsent(match.uploadedFileID, () => match);
          if (candidateMap.length >=
              desiredCount * _kTopWowCandidateMultiplier) {
            break;
          }
        }
        if (candidateMap.length >= desiredCount * _kTopWowCandidateMultiplier) {
          break;
        }
      }
    }

    final List<_ClipMatch> candidates = candidateMap.values.toList(
      growable: false,
    )..sort((_ClipMatch a, _ClipMatch b) => b.score.compareTo(a.score));

    if (candidates.length < desiredCount) {
      return null;
    }

    final Set<int> intersectionIds = intersection
        .map((match) => match.uploadedFileID)
        .toSet();

    final List<_ClipMatch> limitedCandidates = _limitMatches(candidates);
    if (limitedCandidates.length < desiredCount) {
      return null;
    }

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      limitedCandidates.map((match) => match.uploadedFileID),
    );
    if (candidateIds.length < desiredCount) {
      return null;
    }
    final Set<int> candidateSet = candidateIds.toSet();

    final Map<int, double> scoreHints = <int, double>{
      for (final _ClipMatch match in limitedCandidates)
        if (candidateSet.contains(match.uploadedFileID))
          match.uploadedFileID:
              match.score *
              (intersectionIds.contains(match.uploadedFileID) ? 1.5 : 1.0),
    };

    final List<MediaRef> selection = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: desiredCount,
      scoreHints: scoreHints,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 21),
    );
    List<MediaRef> media = selection;

    if (media.length < desiredCount) {
      final Set<int> seen = media.map((ref) => ref.uploadedFileID).toSet();
      final List<MediaRef> expanded = List<MediaRef>.from(
        media,
        growable: true,
      );
      for (final int id in candidateIds) {
        if (seen.add(id)) {
          expanded.add(MediaRef(id));
        }
        if (expanded.length >= desiredCount) {
          break;
        }
      }
      if (expanded.length < desiredCount) {
        return null;
      }
      media = expanded;
    }

    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      desiredCount * 2,
    );
    final Map<String, Object?> meta = <String, Object?>{
      "queries": AestheticsCandidateBuilder._kWowQueries,
      "detailChips": const <String>[],
      if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
    };

    return WrappedCard(
      type: WrappedCardType.top9Wow,
      title: "Wonderful captures",
      subtitle: "Your showstoppers look gallery-ready.",
      media: media,
      meta: meta,
    );
  }

  static List<_ClipMatch> _limitMatches(Iterable<_ClipMatch> matches) {
    final List<_ClipMatch> limited = <_ClipMatch>[];
    final Set<int> seen = <int>{};
    for (final _ClipMatch match in matches) {
      final int id = match.uploadedFileID;
      if (id <= 0 || !seen.add(id)) {
        continue;
      }
      limited.add(match);
      if (limited.length >= kWrappedSelectorCandidateCap) {
        break;
      }
    }
    return limited;
  }

  String? _buildBlurrySubtitle(Set<String> names) {
    if (names.isEmpty) {
      return "Soft-focus favorites that still made the cut.";
    }
    final List<String> sorted = names.toList(growable: false)..sort();
    if (sorted.length == 1) {
      return "Soft-focus laughs with ${sorted.first}.";
    }
    if (sorted.length == 2) {
      return "Soft-focus laughs with ${sorted[0]} & ${sorted[1]}.";
    }
    return "Soft-focus laughs with ${sorted[0]}, ${sorted[1]} and crew.";
  }

  static double _average(List<double> values) {
    if (values.isEmpty) {
      return 0.0;
    }
    double total = 0.0;
    for (final double value in values) {
      total += value;
    }
    return total / values.length;
  }
}

class _AestheticsSnapshot {
  _AestheticsSnapshot({
    required this.year,
    required this.colorSpecs,
    required List<_ImageEmbedding> imageEmbeddings,
    required Map<String, _TextEmbedding> textEmbeddings,
    required Map<int, EnteFile> fileByUploadedId,
    required this.peopleContext,
  }) : imageEmbeddings = List<_ImageEmbedding>.unmodifiable(imageEmbeddings),
       textEmbeddings = Map<String, _TextEmbedding>.unmodifiable(
         textEmbeddings,
       ),
       fileByUploadedId = Map<int, EnteFile>.unmodifiable(fileByUploadedId);

  final int year;
  final List<_ColorSpec> colorSpecs;
  final List<_ImageEmbedding> imageEmbeddings;
  final Map<String, _TextEmbedding> textEmbeddings;
  final Map<int, EnteFile> fileByUploadedId;
  final WrappedPeopleContext peopleContext;

  bool get hasEmbeddings => imageEmbeddings.isNotEmpty;

  List<_BlurryCandidate>? _cachedBlurryCandidates;
  List<_ColorBucket>? _cachedColorBuckets;
  List<_ClipMatch>? _cachedMonochromeMatches;
  List<_ClipMatch>? _cachedTopWowMatches;
  final Map<String, List<_ClipMatch>> _queryMatchCache =
      <String, List<_ClipMatch>>{};

  List<_BlurryCandidate> get blurryCandidates {
    return _cachedBlurryCandidates ??= _computeBlurryCandidates();
  }

  List<_ColorBucket> get colorBuckets {
    return _cachedColorBuckets ??= _computeColorBuckets();
  }

  List<_ClipMatch> get monochromeMatches {
    return _cachedMonochromeMatches ??= _matchesForQuery(
      AestheticsCandidateBuilder._kMonochromeQuery,
    );
  }

  List<_ClipMatch> get topWowMatches {
    return _cachedTopWowMatches ??= _computeTopWow();
  }

  List<_ClipMatch> matchesForQuery(String query) {
    final List<_ClipMatch> matches = _matchesForQuery(query);
    return List<_ClipMatch>.from(matches, growable: false);
  }

  factory _AestheticsSnapshot.fromContext(
    WrappedEngineContext context, {
    required List<_ColorSpec> colorSpecs,
  }) {
    final Map<int, EnteFile> fileByUploadedId = <int, EnteFile>{
      for (final EnteFile file in context.files)
        if (file.uploadedFileID != null) file.uploadedFileID!: file,
    };

    final List<_ImageEmbedding> imageEmbeddings = <_ImageEmbedding>[];
    context.aesthetics.clipEmbeddings.forEach((
      int fileID,
      List<double> values,
    ) {
      if (values.isEmpty) {
        return;
      }
      final EnteFile? file = fileByUploadedId[fileID];
      if (file == null) {
        return;
      }
      final _ImageEmbedding embedding = _ImageEmbedding(
        uploadedFileID: fileID,
        values: values,
        captureMicros: file.creationTime ?? 0,
      );
      if (embedding.norm <= 0) {
        return;
      }
      imageEmbeddings.add(embedding);
    });

    final Map<String, _TextEmbedding> textEmbeddings = <String, _TextEmbedding>{
      for (final MapEntry<String, List<double>> entry
          in context.aesthetics.textEmbeddings.entries)
        if (entry.value.isNotEmpty)
          entry.key: _TextEmbedding(
            values: List<double>.from(entry.value, growable: false),
          ),
    };

    return _AestheticsSnapshot(
      year: context.year,
      colorSpecs: colorSpecs,
      imageEmbeddings: imageEmbeddings,
      textEmbeddings: textEmbeddings,
      fileByUploadedId: fileByUploadedId,
      peopleContext: context.people,
    );
  }

  List<_BlurryCandidate> _computeBlurryCandidates() {
    final List<_BlurryCandidate> candidates = <_BlurryCandidate>[];
    if (!peopleContext.hasPeople) {
      return candidates;
    }

    for (final WrappedPeopleFile file in peopleContext.files) {
      final EnteFile? asset = fileByUploadedId[file.uploadedFileID];
      if (asset == null) {
        continue;
      }

      final Set<String> names = <String>{};
      double bestScore = 0.0;
      double blurScore = double.infinity;

      for (final WrappedFaceRef face in file.faces) {
        if (face.score < kMinimumQualityFaceScore) {
          continue;
        }
        if (face.blur >= AestheticsCandidateBuilder._kBlurryFaceBlurThreshold) {
          continue;
        }
        bestScore = math.max(bestScore, face.score);
        blurScore = math.min(blurScore, face.blur);

        final String? personID = face.personID;
        if (personID == null) {
          continue;
        }
        final WrappedPersonEntry? entry = peopleContext.persons[personID];
        if (entry == null || entry.isHidden) {
          continue;
        }
        if (entry.displayName.isNotEmpty) {
          names.add(entry.displayName);
        }
      }

      if (names.isEmpty || blurScore == double.infinity) {
        continue;
      }

      candidates.add(
        _BlurryCandidate(
          uploadedFileID: file.uploadedFileID,
          captureMicros: file.captureMicros,
          personNames: names,
          blurScore: blurScore,
          faceScore: bestScore,
        ),
      );
    }

    candidates.sort((a, b) {
      final int blurCompare = a.blurScore.compareTo(b.blurScore);
      if (blurCompare != 0) {
        return blurCompare;
      }
      final int scoreCompare = b.faceScore.compareTo(a.faceScore);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.captureMicros.compareTo(a.captureMicros);
    });

    return candidates;
  }

  List<_ColorBucket> _computeColorBuckets() {
    final List<_ColorBucket> buckets = <_ColorBucket>[];
    for (final _ColorSpec spec in colorSpecs) {
      final List<_ClipMatch> matches = _matchesForQuery(spec.query);
      if (matches.isEmpty) {
        continue;
      }
      buckets.add(_ColorBucket(spec: spec, matches: matches));
    }
    return buckets;
  }

  List<_ClipMatch> _computeTopWow() {
    final List<List<_ClipMatch>> matches = <List<_ClipMatch>>[
      for (final String query in AestheticsCandidateBuilder._kWowQueries)
        _matchesForQuery(query),
    ];
    if (matches.any((matchList) => matchList.isEmpty)) {
      return const <_ClipMatch>[];
    }

    final List<Map<int, _ClipMatch>> matchMaps = matches
        .map(
          (List<_ClipMatch> list) => <int, _ClipMatch>{
            for (final _ClipMatch match in list) match.uploadedFileID: match,
          },
        )
        .toList(growable: false);

    final Map<int, _ClipMatch> baseMap = matchMaps.first;
    final List<_ClipMatch> intersection = <_ClipMatch>[];
    baseMap.forEach((int fileID, _ClipMatch baseMatch) {
      if (baseMatch.score <
          AestheticsCandidateBuilder._kTopWowPerQueryThreshold) {
        return;
      }
      double combinedScore = baseMatch.score;
      double highlightScore = baseMatch.score;
      int captureMicros = baseMatch.captureMicros;
      for (int i = 1; i < matchMaps.length; i += 1) {
        final _ClipMatch? other = matchMaps[i][fileID];
        if (other == null) {
          return;
        }
        if (other.score <
            AestheticsCandidateBuilder._kTopWowPerQueryThreshold) {
          return;
        }
        combinedScore += other.score;
        highlightScore = math.max(highlightScore, other.score);
        captureMicros = math.max(captureMicros, other.captureMicros);
      }
      if (highlightScore <
          AestheticsCandidateBuilder._kTopWowHighlightThreshold) {
        return;
      }
      intersection.add(
        _ClipMatch(
          uploadedFileID: fileID,
          score: combinedScore,
          captureMicros: captureMicros,
        ),
      );
    });

    intersection.sort((a, b) {
      final int scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return b.captureMicros.compareTo(a.captureMicros);
    });

    return intersection;
  }

  double _countThresholdForQuery(String query) {
    if (query == AestheticsCandidateBuilder._kMonochromeQuery) {
      return AestheticsCandidateBuilder._kMonochromeCountThreshold;
    }
    if (AestheticsCandidateBuilder._kWowQueries.contains(query)) {
      return AestheticsCandidateBuilder._kTopWowPerQueryThreshold;
    }
    return AestheticsCandidateBuilder._kCountThreshold;
  }

  List<_ClipMatch> _matchesForQuery(String query) {
    return _queryMatchCache.putIfAbsent(query, () {
      final _TextEmbedding? textEmbedding = textEmbeddings[query];
      if (textEmbedding == null || textEmbedding.norm <= 0) {
        return const <_ClipMatch>[];
      }
      final List<_ClipMatch> matches = <_ClipMatch>[];
      final double threshold = _countThresholdForQuery(query);
      for (final _ImageEmbedding imageEmbedding in imageEmbeddings) {
        if (imageEmbedding.norm <= 0) {
          continue;
        }
        final double similarity = _cosine(imageEmbedding, textEmbedding);
        if (similarity >= threshold) {
          matches.add(
            _ClipMatch(
              uploadedFileID: imageEmbedding.uploadedFileID,
              score: similarity,
              captureMicros: imageEmbedding.captureMicros,
            ),
          );
        }
      }
      matches.sort((a, b) => b.score.compareTo(a.score));
      if (matches.length > kWrappedSelectorCandidateCap) {
        matches.length = kWrappedSelectorCandidateCap;
      }
      return matches;
    });
  }

  static double _cosine(
    _ImageEmbedding imageEmbedding,
    _TextEmbedding textEmbedding,
  ) {
    final Float32List a = imageEmbedding.vector;
    final Float32List b = textEmbedding.vector;
    final int length = math.min(a.length, b.length);
    double dot = 0;
    for (int i = 0; i < length; i += 1) {
      dot += a[i] * b[i];
    }
    final double denom = imageEmbedding.norm * textEmbedding.norm;
    if (denom <= 0) {
      return 0.0;
    }
    return dot / denom;
  }
}

class _ColorSpec {
  const _ColorSpec({
    required this.displayName,
    required this.query,
    required this.hex,
  });

  final String displayName;
  final String query;
  final String hex;
}

class _ColorBucket {
  _ColorBucket({required this.spec, required List<_ClipMatch> matches})
    : matches = List<_ClipMatch>.unmodifiable(matches);

  final _ColorSpec spec;
  final List<_ClipMatch> matches;
}

class _ClipMatch {
  _ClipMatch({
    required this.uploadedFileID,
    required this.score,
    required this.captureMicros,
  });

  final int uploadedFileID;
  final double score;
  final int captureMicros;
}

class _ImageEmbedding {
  _ImageEmbedding({
    required this.uploadedFileID,
    required List<double> values,
    required this.captureMicros,
  }) : vector = Float32List.fromList(values),
       norm = _computeNorm(values);

  final int uploadedFileID;
  final Float32List vector;
  final double norm;
  final int captureMicros;

  static double _computeNorm(List<double> values) {
    double sum = 0.0;
    for (final double value in values) {
      sum += value * value;
    }
    if (sum <= 0) {
      return 0.0;
    }
    return math.sqrt(sum);
  }
}

class _TextEmbedding {
  _TextEmbedding({required List<double> values})
    : vector = Float32List.fromList(values),
      norm = _ImageEmbedding._computeNorm(values);

  final Float32List vector;
  final double norm;
}

class _BlurryCandidate {
  _BlurryCandidate({
    required this.uploadedFileID,
    required this.captureMicros,
    required Set<String> personNames,
    required this.blurScore,
    required this.faceScore,
  }) : personNames = Set<String>.unmodifiable(personNames);

  final int uploadedFileID;
  final int captureMicros;
  final Set<String> personNames;
  final double blurScore;
  final double faceScore;
}
