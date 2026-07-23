part of 'package:photos/services/wrapped/candidate_builders.dart';

class PeopleCandidateBuilder extends WrappedCandidateBuilder {
  const PeopleCandidateBuilder();

  static const int _kMinFacesForTopPerson = 6;
  static const int _kMinFacesPerNewPerson = 4;
  static const int _kMinClusterFacesForNewPerson = 10;

  @override
  String get debugLabel => "people";

  @override
  Future<List<WrappedCard>> build(WrappedEngineContext context) async {
    final WrappedPeopleContext peopleContext = context.people;
    final _PeopleDataset dataset = _PeopleDataset.fromContext(
      peopleContext,
      context.year,
    );
    if (!dataset.hasAnyContent) {
      return const <WrappedCard>[];
    }

    final List<WrappedCard> cards = <WrappedCard>[];

    final WrappedCard? topPersonCard = _buildTopPersonCard(context, dataset);
    if (topPersonCard != null) {
      cards.add(topPersonCard);
    }

    final WrappedCard? topThreeCard = _buildTopThreePeopleCard(
      context,
      dataset,
    );
    if (topThreeCard != null) {
      cards.add(topThreeCard);
    }

    final WrappedCard? groupVsSoloCard = _buildGroupVsSoloCard(
      context,
      dataset,
    );
    if (groupVsSoloCard != null) {
      cards.add(groupVsSoloCard);
    }

    final WrappedCard? newFacesCard = _buildNewFacesCard(context, dataset);
    if (newFacesCard != null) {
      cards.add(newFacesCard);
    }

    return cards;
  }

  WrappedCard? _buildTopPersonCard(
    WrappedEngineContext context,
    _PeopleDataset dataset,
  ) {
    final _PersonStats? topPerson = dataset.topNamedPerson;
    if (topPerson == null || topPerson.faceCount < _kMinFacesForTopPerson) {
      return null;
    }

    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final int uniqueMoments = topPerson.uniqueMoments;
    final double share =
        dataset.totalNamedFaceCount == 0 || topPerson.faceCount == 0
        ? 0
        : topPerson.faceCount / dataset.totalNamedFaceCount;
    final int sharePercent = _percentOf(share);
    final List<String> chips = _cleanChips(<String>[
      "Appearances: ${numberFormat.format(topPerson.faceCount)}",
      if (sharePercent > 0) "Share: $sharePercent%",
      if (topPerson.firstSeenYear != null &&
          topPerson.firstSeenYear == dataset.year)
        "First year: ${topPerson.firstSeenYear}",
    ]);

    final String displayName = topPerson.displayNameForTitle.trim();
    final bool endsWithS =
        displayName.isNotEmpty && displayName.toLowerCase().endsWith("s");
    final String title = displayName.isEmpty
        ? "Your star"
        : endsWithS
        ? "$displayName spotlight"
        : "$displayName's spotlight";
    final String? heroName = displayName.isNotEmpty ? displayName : null;
    final String subtitle = heroName != null
        ? "$heroName was the star of your year!"
        : "Someone special was the star of your year!";

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      topPerson.topMediaFileIDs(kWrappedSelectorCandidateCap),
    );
    final Set<int> candidateSet = candidateIds.toSet();
    const int maxMediaCount = 5;
    final Map<int, double> scoreHints = <int, double>{
      for (final MapEntry<int, double> entry
          in topPerson.mediaScoreHints().entries)
        if (candidateSet.contains(entry.key)) entry.key: entry.value,
    };
    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: maxMediaCount,
      scoreHints: scoreHints,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 30),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      maxMediaCount * 2,
    );

    final Map<String, Object?> meta = <String, Object?>{
      "personId": topPerson.personEntry.personID,
      "displayName": topPerson.displayNameForTitle,
      "appearanceCount": topPerson.faceCount,
      "uniqueMoments": uniqueMoments,
      "sharePercent": sharePercent,
      "detailChips": chips,
      "displayDurationMillis": 7500,
    };

    return WrappedCard(
      type: WrappedCardType.topPerson,
      title: title,
      subtitle: subtitle,
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  WrappedCard? _buildTopThreePeopleCard(
    WrappedEngineContext context,
    _PeopleDataset dataset,
  ) {
    if (dataset.topNamedPeople.length < 3) {
      return null;
    }
    final List<_PersonStats> topThree = dataset.topNamedPeople
        .take(3)
        .toList(growable: false);
    final NumberFormat numberFormat = NumberFormat.decimalPattern();

    final List<String> names = topThree
        .map((_PersonStats stats) => stats.displayNameForTitle)
        .toList(growable: false);
    final List<String> chips = _cleanChips(<String>[
      for (final _PersonStats stats in topThree)
        "${stats.displayNameForTitle}: ${numberFormat.format(stats.faceCount)} shots",
    ]);

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      topThree
          .map(
            (_PersonStats stats) =>
                stats.topMediaFileIDs(kWrappedSelectorCandidateCap),
          )
          .expand((List<int> ids) => ids),
    );
    final Set<int> candidateSet = candidateIds.toSet();
    const int maxMediaCount = 4;

    final Map<int, double> scoreHints = <int, double>{};
    for (final _PersonStats stats in topThree) {
      final Map<int, double> personHints = stats.mediaScoreHints();
      for (final MapEntry<int, double> entry in personHints.entries) {
        if (!candidateSet.contains(entry.key)) {
          continue;
        }
        scoreHints.update(
          entry.key,
          (double value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: maxMediaCount,
      scoreHints: scoreHints,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 21),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      maxMediaCount * 2,
    );

    final Map<String, Object?> meta = <String, Object?>{
      "personIds": topThree
          .map((_PersonStats stats) => stats.personEntry.personID)
          .toList(growable: false),
      "detailChips": chips,
      "displayDurationMillis": 7000,
    };

    return WrappedCard(
      type: WrappedCardType.topThreePeople,
      title: "Core crew",
      subtitle:
          "${_formatNameList(names)} kept showing up in your favorite frames.",
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  WrappedCard? _buildGroupVsSoloCard(
    WrappedEngineContext context,
    _PeopleDataset dataset,
  ) {
    if (!dataset.hasFaceMoments) {
      return null;
    }
    final int totalMoments = dataset.totalFaceMoments;
    if (totalMoments <= 0) {
      return null;
    }
    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final int groupPercent = _percentOf(
      dataset.groupMoments / totalMoments.toDouble(),
    );
    final int soloPercent = _percentOf(
      dataset.soloMoments / totalMoments.toDouble(),
    );
    final int duoPercent = _percentOf(
      dataset.duoMoments / totalMoments.toDouble(),
    );

    final bool hasGroup = groupPercent > 0;
    final bool hasSolo = soloPercent > 0;
    final bool hasDuo = duoPercent > 0;
    final List<String> intimateParts = <String>[
      if (hasSolo) "$soloPercent% were one-on-one moments",
      if (hasDuo) "$duoPercent% played out in small circles",
    ];
    final String? intimateSummary = intimateParts.isEmpty
        ? null
        : intimateParts.length == 1
        ? intimateParts.first
        : "${intimateParts[0]} and ${intimateParts[1]}";

    final String subtitle;
    if (hasGroup && intimateSummary != null) {
      subtitle =
          "You made $groupPercent% of your memories in groups, while $intimateSummary.";
    } else if (hasGroup) {
      subtitle = "You made $groupPercent% of your memories in groups.";
    } else if (intimateSummary != null) {
      subtitle = "You kept things close—$intimateSummary.";
    } else {
      subtitle = "You balanced time with friends and quiet moments.";
    }

    final List<String> chips = _cleanChips(<String>[
      if (dataset.groupMoments > 0)
        "Group shots: ${numberFormat.format(dataset.groupMoments)}",
      if (dataset.duoMoments > 0)
        "Duo shots: ${numberFormat.format(dataset.duoMoments)}",
      if (dataset.soloMoments > 0)
        "Solo shots: ${numberFormat.format(dataset.soloMoments)}",
    ]);

    final List<int> candidateIds = limitSelectorCandidates(context, <int>[
      ...dataset.groupSampleFileIDs(kWrappedSelectorCandidateCap),
      ...dataset.soloSampleFileIDs(kWrappedSelectorCandidateCap),
    ]);
    const int maxMediaCount = 5;

    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: maxMediaCount,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 45),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      maxMediaCount * 2,
    );

    final Map<String, Object?> meta = <String, Object?>{
      "groupShots": dataset.groupMoments,
      "soloShots": dataset.soloMoments,
      "duoShots": dataset.duoMoments,
      "totalFaceMoments": totalMoments,
      "groupSharePercent": groupPercent,
      "soloSharePercent": soloPercent,
      "duoSharePercent": duoPercent,
      "detailChips": chips,
      "displayDurationMillis": 6500,
    };

    return WrappedCard(
      type: WrappedCardType.groupVsSolo,
      title: "Sharing memories",
      subtitle: subtitle,
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  WrappedCard? _buildNewFacesCard(
    WrappedEngineContext context,
    _PeopleDataset dataset,
  ) {
    final List<_PersonStats> newPeople = dataset.topPeople
        .where((_PersonStats stats) {
          final int? firstSeenYear = stats.firstSeenYear;
          if (firstSeenYear == null || firstSeenYear != dataset.year) {
            return false;
          }
          if (stats.faceCount < _kMinFacesPerNewPerson) {
            return false;
          }
          if (stats.personEntry.totalClusterFaceCount <
              _kMinClusterFacesForNewPerson) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    if (newPeople.isEmpty) {
      return null;
    }

    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final int count = newPeople.length;
    final List<_PersonStats> highlights = newPeople
        .take(3)
        .toList(growable: false);
    final List<String> highlightNames = highlights
        .map((_PersonStats stats) => stats.displayNameForTitle)
        .toList(growable: false);
    final String subtitleNames = highlightNames.isEmpty
        ? ""
        : "${_formatNameList(highlightNames)} joined your story.";

    final List<String> chips = _cleanChips(<String>[
      for (int index = 0; index < highlights.length && index < 3; index += 1)
        () {
          final _PersonStats stats = highlights[index];
          final String name = stats.displayNameForTitle.trim();
          final String labelName = name.isNotEmpty
              ? name
              : "New friend ${index + 1}";
          final String countLabel = stats.faceCount == 1
              ? "1 memory"
              : "${numberFormat.format(stats.faceCount)} memories";
          return "$labelName: $countLabel";
        }(),
    ]);

    final List<int> candidateIds = limitSelectorCandidates(
      context,
      highlights
          .map(
            (_PersonStats stats) =>
                stats.topMediaFileIDs(kWrappedSelectorCandidateCap),
          )
          .expand((List<int> ids) => ids),
    );
    final Set<int> candidateSet = candidateIds.toSet();
    const int maxMediaCount = 5;

    final Map<int, double> scoreHints = <int, double>{};
    for (final _PersonStats stats in highlights) {
      final Map<int, double> personHints = stats.mediaScoreHints();
      for (final MapEntry<int, double> entry in personHints.entries) {
        if (!candidateSet.contains(entry.key)) {
          continue;
        }
        scoreHints.update(
          entry.key,
          (double value) => value + entry.value,
          ifAbsent: () => entry.value,
        );
      }
    }

    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: candidateIds,
      maxCount: maxMediaCount,
      scoreHints: scoreHints,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 30),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      candidateIds,
      maxMediaCount * 2,
    );

    final Map<String, Object?> meta = <String, Object?>{
      "newPersonCount": count,
      "highlightNames": highlightNames,
      "detailChips": chips,
      "displayDurationMillis": 6500,
    };

    final String subtitle = subtitleNames.isEmpty
        ? "${numberFormat.format(count)} new faces joined your story."
        : subtitleNames;

    return WrappedCard(
      type: WrappedCardType.newFaces,
      title: "Fresh faces",
      subtitle: subtitle,
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }
}

class _PeopleDataset {
  _PeopleDataset._({
    required this.year,
    required List<_PersonStats> topPeople,
    required List<_PersonStats> topNamedPeople,
    required this.selfPersonID,
    required this.totalNamedFaceCount,
    required this.totalFaceMoments,
    required this.totalNamedFaceMoments,
    required this.groupMoments,
    required this.soloMoments,
    required this.duoMoments,
    required List<_FileSample> groupSamples,
    required List<_FileSample> soloSamples,
  }) : _topPeople = List<_PersonStats>.unmodifiable(topPeople),
       _topNamedPeople = List<_PersonStats>.unmodifiable(topNamedPeople),
       _groupSamples = List<_FileSample>.unmodifiable(groupSamples),
       _soloSamples = List<_FileSample>.unmodifiable(soloSamples);

  final int year;
  final List<_PersonStats> _topPeople;
  final List<_PersonStats> _topNamedPeople;
  final String? selfPersonID;
  final int totalNamedFaceCount;
  final int totalFaceMoments;
  final int totalNamedFaceMoments;
  final int groupMoments;
  final int soloMoments;
  final int duoMoments;
  final List<_FileSample> _groupSamples;
  final List<_FileSample> _soloSamples;

  bool get hasAnyContent =>
      hasFaceMoments || _topPeople.isNotEmpty || _topNamedPeople.isNotEmpty;

  bool get hasFaceMoments => totalFaceMoments > 0;

  List<_PersonStats> get topPeople => _topPeople;

  List<_PersonStats> get topNamedPeople => _topNamedPeople;

  _PersonStats? get topNamedPerson =>
      _topNamedPeople.isEmpty ? null : _topNamedPeople.first;

  List<int> groupSampleFileIDs(int count) {
    return _groupSamples
        .map((_FileSample sample) => sample.fileID)
        .where((int id) => id > 0)
        .take(count)
        .toList(growable: false);
  }

  List<int> soloSampleFileIDs(int count) {
    return _soloSamples
        .map((_FileSample sample) => sample.fileID)
        .where((int id) => id > 0)
        .take(count)
        .toList(growable: false);
  }

  static _PeopleDataset fromContext(WrappedPeopleContext context, int year) {
    if (context.files.isEmpty) {
      return _PeopleDataset._empty(year);
    }

    final String? selfPersonID = context.selfPersonID;
    final Map<String, _PersonStats> personStats = <String, _PersonStats>{};
    final Map<String, int> firstSeenYear = <String, int>{
      for (final MapEntry<String, int> entry
          in context.personFirstCaptureMicros.entries)
        entry.key: DateTime.fromMicrosecondsSinceEpoch(entry.value).year,
    };

    int totalNamedFaceCount = 0;
    int totalFaceMoments = 0;
    int totalNamedFaceMoments = 0;
    int groupMoments = 0;
    int soloMoments = 0;
    int duoMoments = 0;
    final List<_FileSample> groupSamples = <_FileSample>[];
    final List<_FileSample> soloSamples = <_FileSample>[];
    final Set<int> seenGroupFiles = <int>{};
    final Set<int> seenSoloFiles = <int>{};

    for (final WrappedPeopleFile file in context.files) {
      if (file.faces.isEmpty) {
        continue;
      }
      final List<WrappedFaceRef> faces = file.faces;
      final bool includesSelf =
          selfPersonID != null &&
          faces.any((WrappedFaceRef face) => face.personID == selfPersonID);
      final bool hasNamedPerson = faces.any((WrappedFaceRef face) {
        final String? personID = face.personID;
        if (personID == null) {
          return false;
        }
        final WrappedPersonEntry? entry = context.persons[personID];
        if (entry == null || entry.isHidden || entry.isMe) {
          return false;
        }
        return entry.displayName.trim().isNotEmpty;
      });
      final int highQualityCount = faces
          .where((WrappedFaceRef face) => face.isHighQuality)
          .length;
      final int effectiveCount = highQualityCount > 0
          ? highQualityCount
          : faces.length;
      if (effectiveCount > 0) {
        totalFaceMoments += 1;
        if (hasNamedPerson) {
          totalNamedFaceMoments += 1;
        }
      }
      if (effectiveCount >= 3) {
        groupMoments += 1;
        if (seenGroupFiles.add(file.uploadedFileID)) {
          groupSamples.add(
            _FileSample(
              fileID: file.uploadedFileID,
              captureMicros: file.captureMicros,
            ),
          );
        }
      } else if (effectiveCount == 2) {
        duoMoments += 1;
      } else if (effectiveCount == 1) {
        soloMoments += 1;
        if (seenSoloFiles.add(file.uploadedFileID)) {
          soloSamples.add(
            _FileSample(
              fileID: file.uploadedFileID,
              captureMicros: file.captureMicros,
            ),
          );
        }
      }

      for (final WrappedFaceRef face in faces) {
        final String? personID = face.personID;
        if (personID == null) {
          continue;
        }
        if (selfPersonID != null && personID == selfPersonID) {
          continue;
        }
        final WrappedPersonEntry? personEntry = context.persons[personID];
        if (personEntry == null || personEntry.isHidden || personEntry.isMe) {
          continue;
        }
        totalNamedFaceCount += 1;
        final _PersonStats stats = personStats.putIfAbsent(
          personID,
          () => _PersonStats(personEntry),
        );
        stats.addFace(file: file, face: face, includesSelf: includesSelf);
      }
    }

    final List<_PersonStats> orderedPeople =
        personStats.values.toList(growable: false)
          ..sort((_PersonStats a, _PersonStats b) {
            if (b.faceCount != a.faceCount) {
              return b.faceCount.compareTo(a.faceCount);
            }
            if (b.uniqueMoments != a.uniqueMoments) {
              return b.uniqueMoments.compareTo(a.uniqueMoments);
            }
            return a.displayNameForTitle.toLowerCase().compareTo(
              b.displayNameForTitle.toLowerCase(),
            );
          });

    for (final _PersonStats stats in orderedPeople) {
      final int? seenYear = firstSeenYear[stats.personEntry.personID];
      stats.firstSeenYear = seenYear;
    }

    final List<_PersonStats> orderedNamedPeople = orderedPeople
        .where((_PersonStats stats) => stats.hasName)
        .toList(growable: false);

    groupSamples.sort(
      (_FileSample a, _FileSample b) =>
          b.captureMicros.compareTo(a.captureMicros),
    );
    soloSamples.sort(
      (_FileSample a, _FileSample b) =>
          b.captureMicros.compareTo(a.captureMicros),
    );

    return _PeopleDataset._(
      year: year,
      topPeople: orderedPeople,
      topNamedPeople: orderedNamedPeople,
      selfPersonID: selfPersonID,
      totalNamedFaceCount: totalNamedFaceCount,
      totalFaceMoments: totalFaceMoments,
      totalNamedFaceMoments: totalNamedFaceMoments,
      groupMoments: groupMoments,
      soloMoments: soloMoments,
      duoMoments: duoMoments,
      groupSamples: groupSamples,
      soloSamples: soloSamples,
    );
  }

  static _PeopleDataset _empty(int year) {
    return _PeopleDataset._(
      year: year,
      topPeople: const <_PersonStats>[],
      topNamedPeople: const <_PersonStats>[],
      selfPersonID: null,
      totalNamedFaceCount: 0,
      totalFaceMoments: 0,
      totalNamedFaceMoments: 0,
      groupMoments: 0,
      soloMoments: 0,
      duoMoments: 0,
      groupSamples: const <_FileSample>[],
      soloSamples: const <_FileSample>[],
    );
  }
}

class _PersonStats {
  _PersonStats(this.personEntry);

  final WrappedPersonEntry personEntry;
  final Map<int, _PersonCapture> _captures = <int, _PersonCapture>{};
  int faceCount = 0;
  int highQualityFaces = 0;
  int? firstSeenYear;

  int get uniqueMoments => _captures.length;

  bool get hasName => personEntry.displayName.trim().isNotEmpty;

  String get displayNameForTitle =>
      hasName ? personEntry.displayName.trim() : "Someone special";

  String get mentionForSentence =>
      hasName ? personEntry.displayName.trim() : "someone special";

  void addFace({
    required WrappedPeopleFile file,
    required WrappedFaceRef face,
    required bool includesSelf,
  }) {
    faceCount += 1;
    if (face.isHighQuality) {
      highQualityFaces += 1;
    }
    _PersonCapture? capture = _captures[file.uploadedFileID];
    if (capture == null) {
      capture = _PersonCapture(
        fileID: file.uploadedFileID,
        captureMicros: file.captureMicros,
        includesSelf: includesSelf,
      );
      _captures[file.uploadedFileID] = capture;
    }
    capture.registerFace(face, includesSelf: includesSelf);
  }

  List<int> topMediaFileIDs(int count) {
    final List<_PersonCapture> captures =
        _captures.values.toList(growable: false)
          ..sort((_PersonCapture a, _PersonCapture b) {
            if (a.includesSelf != b.includesSelf) {
              return a.includesSelf ? -1 : 1;
            }
            if (b.highQualityFaces != a.highQualityFaces) {
              return b.highQualityFaces.compareTo(a.highQualityFaces);
            }
            if ((b.bestScore ?? 0) != (a.bestScore ?? 0)) {
              return (b.bestScore ?? 0).compareTo(a.bestScore ?? 0);
            }
            return b.captureMicros.compareTo(a.captureMicros);
          });
    return captures
        .where((_PersonCapture capture) => capture.fileID > 0)
        .map((_PersonCapture capture) => capture.fileID)
        .take(count)
        .toList(growable: false);
  }

  Map<int, double> mediaScoreHints({double withSelfBoost = 0.25}) {
    if (withSelfBoost <= 0) {
      return <int, double>{};
    }
    final Map<int, double> hints = <int, double>{};
    for (final _PersonCapture capture in _captures.values) {
      if (capture.includesSelf && capture.fileID > 0) {
        hints[capture.fileID] = (hints[capture.fileID] ?? 0) + withSelfBoost;
      }
    }
    return hints;
  }
}

class _PersonCapture {
  _PersonCapture({
    required this.fileID,
    required this.captureMicros,
    this.includesSelf = false,
  });

  final int fileID;
  final int captureMicros;
  double? bestScore;
  int highQualityFaces = 0;
  bool includesSelf;

  void registerFace(WrappedFaceRef face, {required bool includesSelf}) {
    if (includesSelf) {
      this.includesSelf = true;
    }
    if (bestScore == null || face.score > bestScore!) {
      bestScore = face.score;
    }
    if (face.isHighQuality) {
      highQualityFaces += 1;
    }
  }
}

class _FileSample {
  const _FileSample({required this.fileID, required this.captureMicros});

  final int fileID;
  final int captureMicros;
}

List<String> _cleanChips(List<String> chips) {
  return chips
      .where((String chip) => chip.trim().isNotEmpty)
      .toList(growable: false);
}

String _formatNameList(List<String> names) {
  if (names.isEmpty) return "";
  if (names.length == 1) return names.first;
  if (names.length == 2) {
    return "${names[0]} and ${names[1]}";
  }
  return "${names[0]}, ${names[1]}, and ${names[2]}";
}

int _percentOf(double value) {
  if (value.isNaN || value.isInfinite) {
    return 0;
  }
  final double clamped = value.clamp(0.0, 1.0);
  return (clamped * 100).round();
}
