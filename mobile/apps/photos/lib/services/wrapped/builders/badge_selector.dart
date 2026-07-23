part of "package:photos/services/wrapped/candidate_builders.dart";

class WrappedBadgeSelection {
  const WrappedBadgeSelection({
    required this.badgeKey,
    required this.card,
    required this.candidatesMeta,
  });

  final String badgeKey;
  final WrappedCard card;
  final List<Map<String, Object?>> candidatesMeta;
}

class WrappedBadgeSelector {
  const WrappedBadgeSelector._();

  static const String _kBadgeKeyConsistency = "consistency_champ";
  static const String _kBadgeKeyPortraitPro = "portrait_pro";
  static const String _kBadgeKeyPeoplePerson = "people_person";
  static const String _kBadgeKeyGlobetrotter = "globetrotter";
  static const String _kBadgeKeyMinimalist = "minimalist_shooter";

  static Set<String> get requiredTextQueries => const <String>{};

  static WrappedBadgeSelection select({
    required WrappedEngineContext context,
    required List<WrappedCard> existingCards,
  }) {
    // Existing cards kept for future badge tweaks (no-op for now).
    existingCards;

    final _BadgeComputationContext metrics =
        _BadgeComputationContext.fromEngineContext(context: context);

    final List<_BadgeCandidate> candidates = <_BadgeCandidate>[];
    void addCandidate(_BadgeCandidate? candidate) {
      if (candidate != null) {
        candidates.add(candidate);
      }
    }

    addCandidate(_buildConsistencyChamp(metrics));
    addCandidate(_buildPortraitPro(metrics));
    addCandidate(_buildPeoplePerson(metrics));
    addCandidate(_buildGlobetrotter(metrics));
    addCandidate(_buildMinimalist(metrics));

    if (candidates.isEmpty) {
      final WrappedCard fallbackCard = WrappedCard(
        type: WrappedCardType.badge,
        title: "Ente Rewind ${context.year} is on its way",
        subtitle: "Full story coming soon.",
        meta: <String, Object?>{
          "generatedAt": context.now.toIso8601String(),
          "isStub": true,
        },
      );
      return WrappedBadgeSelection(
        badgeKey: _kBadgeKeyConsistency,
        card: fallbackCard,
        candidatesMeta: const <Map<String, Object?>>[],
      );
    }

    final List<_BadgeCandidate> eligible = candidates
        .where((_BadgeCandidate candidate) {
          if (!candidate.eligible) {
            return false;
          }
          if (candidate.score <= 0) {
            return false;
          }
          return true;
        })
        .toList(growable: false);

    eligible.sort(_badgeComparator);

    final _BadgeCandidate primary = eligible.isNotEmpty
        ? eligible.first
        : candidates.last;

    final List<Map<String, Object?>> candidatesMeta =
        candidates
            .map((_BadgeCandidate candidate) {
              return candidate.toMetaMap();
            })
            .toList(growable: false)
          ..sort((Map<String, Object?> a, Map<String, Object?> b) {
            final double scoreA = (a["score"] as num?)?.toDouble() ?? 0;
            final double scoreB = (b["score"] as num?)?.toDouble() ?? 0;
            final int scoreCompare = scoreB.compareTo(scoreA);
            if (scoreCompare != 0) {
              return scoreCompare;
            }
            return (a["key"] as String).compareTo(b["key"] as String);
          });

    final WrappedCard badgeCard = WrappedCard(
      type: WrappedCardType.badge,
      title: primary.title,
      subtitle: primary.subtitle,
      media: primary.mediaRefs,
      meta: primary.meta
        ..addAll(<String, Object?>{
          "candidates": candidatesMeta,
          "badgeKey": primary.key,
        }),
    );

    return WrappedBadgeSelection(
      badgeKey: primary.key,
      card: badgeCard,
      candidatesMeta: candidatesMeta,
    );
  }

  static int _badgeComparator(_BadgeCandidate a, _BadgeCandidate b) {
    final int scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) {
      return scoreCompare;
    }
    final int sampleCompare = b.sampleSize.compareTo(a.sampleSize);
    if (sampleCompare != 0) {
      return sampleCompare;
    }
    final int hashCompare = a.deterministicTieBreaker.compareTo(
      b.deterministicTieBreaker,
    );
    if (hashCompare != 0) {
      return hashCompare;
    }
    return a.key.compareTo(b.key);
  }

  static _BadgeCandidate _buildConsistencyChamp(
    _BadgeComputationContext metrics,
  ) {
    final double streakScore = metrics.longestStreakDays <= 0
        ? 0
        : metrics.longestStreakDays / 150.0;
    final double activeRatio = metrics.daysWithCaptures / 365.0;
    final double score = _clamp01(
      0.5 * _clamp01(streakScore) + 0.5 * _clamp01(activeRatio),
    );

    final bool eligible =
        metrics.daysWithCaptures >= 15 &&
        metrics.longestStreakDays >= 3 &&
        metrics.totalCount > 0;

    final String subtitle = metrics.longestStreakDays > 0
        ? "You're the consistency champ! ${metrics.longestStreakDays} days without missing a beat."
        : "You're the consistency champ! The lens stayed alive all year.";

    final List<String> chips = <String>[
      "Active days: ${metrics.daysWithCaptures}",
      if (metrics.longestStreakDays > 0)
        "Longest streak: ${metrics.longestStreakDays}",
    ];

    return _BadgeCandidate(
      key: _kBadgeKeyConsistency,
      name: "Consistency Champ",
      title: "Consistency Champ",
      subtitle: subtitle,
      emoji: "🔥",
      gradientStart: "#FF7A18",
      gradientEnd: "#AF002D",
      mediaRefs: metrics.highlightMedia,
      detailChips: chips,
      score: score,
      eligible: eligible,
      sampleSize: metrics.daysWithCaptures,
      debugWhy:
          "Streak ${metrics.longestStreakDays}d, active ratio ${metrics.daysWithCaptures}/${metrics.elapsedDays}",
      extras: <String, Object?>{
        "longestStreakDays": metrics.longestStreakDays,
        "daysWithCaptures": metrics.daysWithCaptures,
      },
    );
  }

  static _BadgeCandidate? _buildPortraitPro(_BadgeComputationContext metrics) {
    if (!metrics.peopleStats.hasFaceMoments) {
      return null;
    }
    final int totalFaceMoments = metrics.peopleStats.totalFaceMoments;
    if (totalFaceMoments <= 0) {
      return null;
    }
    final int soloMoments = metrics.peopleStats.soloMoments;
    final double share = totalFaceMoments == 0
        ? 0
        : soloMoments / totalFaceMoments.toDouble();
    final double score = _clamp01(share);
    final int soloPercent = _percentOf(share);
    final bool eligible =
        totalFaceMoments >= 20 && soloMoments >= 12 && score >= 0.5;

    final List<String> chips = <String>[
      "Solo portraits: $soloMoments",
      "Share: $soloPercent%",
    ];
    final List<MediaRef> heroMedia = metrics.peopleStats
        .soloSampleFileIDs(3)
        .map(MediaRef.new)
        .toList(growable: false);

    return _BadgeCandidate(
      key: _kBadgeKeyPortraitPro,
      name: "Portrait Pro",
      title: "Portrait Pro",
      subtitle:
          "You're a portrait pro! $soloPercent% one-on-one moments captured.",
      emoji: "🎯",
      gradientStart: "#B721FF",
      gradientEnd: "#21D4FD",
      mediaRefs: heroMedia,
      detailChips: chips,
      score: score,
      eligible: eligible,
      sampleSize: soloMoments,
      debugWhy: "Solo share $soloPercent% ($soloMoments/$totalFaceMoments)",
      extras: <String, Object?>{
        "soloMoments": soloMoments,
        "totalFaceMoments": totalFaceMoments,
      },
    );
  }

  static _BadgeCandidate? _buildPeoplePerson(_BadgeComputationContext metrics) {
    if (!metrics.peopleStats.hasFaceMoments || metrics.totalCount <= 0) {
      return null;
    }
    final int totalNamedMoments = metrics.peopleStats.totalNamedFaceMoments;
    if (totalNamedMoments <= 0) {
      return null;
    }
    final double share = totalNamedMoments / metrics.totalCount.toDouble();
    final double score = _clamp01(share);
    final int percent = _percentOf(share);

    final bool eligible =
        metrics.totalCount >= 80 && totalNamedMoments >= 16 && score >= 0.30;

    final List<String> chips = <String>[
      "Moments with people: $totalNamedMoments",
    ];

    final List<MediaRef> heroMedia = metrics.peopleStats.topNamedPeople
        .map((_PersonStats stats) => stats.topMediaFileIDs(1))
        .expand((List<int> ids) => ids)
        .where((int id) => id > 0)
        .take(3)
        .map(MediaRef.new)
        .toList(growable: false);

    return _BadgeCandidate(
      key: _kBadgeKeyPeoplePerson,
      name: "People Person",
      title: "People Person",
      subtitle:
          "You're a people person! Your crew lit up $percent% of your year.",
      emoji: "🤝",
      gradientStart: "#F857A6",
      gradientEnd: "#FF5858",
      mediaRefs: heroMedia,
      detailChips: chips,
      score: score,
      eligible: eligible,
      sampleSize: totalNamedMoments,
      debugWhy:
          "People coverage $percent% ($totalNamedMoments/${metrics.totalCount})",
      extras: <String, Object?>{
        "totalNamedMoments": totalNamedMoments,
        "totalCount": metrics.totalCount,
      },
    );
  }

  static _BadgeCandidate? _buildGlobetrotter(_BadgeComputationContext metrics) {
    if (metrics.placesStats == null || metrics.placesStats!.totalCount <= 0) {
      return null;
    }
    final _BadgePlaceStats placeStats = metrics.placesStats!;
    final int uniqueCities = placeStats.uniqueCities;
    final int uniqueCountries = placeStats.uniqueCountries;
    final int geoCount = placeStats.totalCount;
    if (geoCount <= 0) {
      return null;
    }

    final int outsidePrimaryCount = placeStats.outsidePrimaryCountryCount;
    final double outsideShare = metrics.totalCount == 0
        ? 0
        : outsidePrimaryCount / metrics.totalCount.toDouble();
    final double score = _clamp01(outsideShare);
    final bool eligible =
        geoCount >= 40 &&
        (uniqueCities >= 3 || uniqueCountries >= 2) &&
        score >= 0.25;

    final int geoSharePercent = metrics.totalCount == 0
        ? 0
        : _percentOf(geoCount / metrics.totalCount);

    final int awayPercent = _percentOf(outsideShare);

    final List<String> chips = <String>[
      "Cities: $uniqueCities",
      "Countries: $uniqueCountries",
      "Geotagged: $geoSharePercent%",
      "Away from base: $awayPercent%",
    ];

    return _BadgeCandidate(
      key: _kBadgeKeyGlobetrotter,
      name: "Globetrotter",
      title: "Globetrotter",
      subtitle:
          "You're a globetrotter! $uniqueCities cities across $uniqueCountries countries this year.",
      emoji: "🌍",
      gradientStart: "#00B09B",
      gradientEnd: "#96C93D",
      mediaRefs: placeStats.heroMedia.map(MediaRef.new).toList(growable: false),
      detailChips: chips,
      score: score,
      eligible: eligible,
      sampleSize: geoCount,
      debugWhy:
          "$uniqueCities cities, $uniqueCountries countries, outside share $awayPercent%",
      extras: <String, Object?>{
        "uniqueCities": uniqueCities,
        "uniqueCountries": uniqueCountries,
        "geotaggedCount": geoCount,
      },
    );
  }

  static _BadgeCandidate _buildMinimalist(_BadgeComputationContext metrics) {
    final bool eligible = metrics.totalCount > 0;

    final double volumeScore = metrics.totalCount <= 0
        ? 0
        : 150 / metrics.totalCount;
    final double calmDaysRatio = metrics.elapsedDays <= 0
        ? 0
        : (metrics.elapsedDays - metrics.daysWithCaptures) /
              metrics.elapsedDays;
    final double score = _clamp01(
      0.5 * _clamp01(volumeScore) + 0.5 * _clamp01(calmDaysRatio),
    );

    final String subtitle =
        "You're a minimalist shooter! ${metrics.daysWithCaptures} intentful days behind the lens.";
    final List<String> chips = <String>[
      "Active days: ${metrics.daysWithCaptures}",
    ];

    return _BadgeCandidate(
      key: _kBadgeKeyMinimalist,
      name: "Minimalist Shooter",
      title: "Minimalist Shooter",
      subtitle: subtitle,
      emoji: "🧘",
      gradientStart: "#304352",
      gradientEnd: "#D7D2CC",
      mediaRefs: metrics.highlightMedia,
      detailChips: chips,
      score: score,
      eligible: eligible,
      sampleSize: metrics.totalCount,
      debugWhy:
          "Total ${metrics.totalCount}, active days ${metrics.daysWithCaptures}",
      extras: <String, Object?>{
        "totalCount": metrics.totalCount,
        "daysWithCaptures": metrics.daysWithCaptures,
      },
    );
  }

  static double _clamp01(double value) {
    if (value.isNaN) {
      return 0;
    }
    if (value <= 0) {
      return 0;
    }
    if (value >= 1) {
      return 1;
    }
    return value;
  }

  static int _percentOf(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return (_clamp01(value) * 100).round();
  }
}

class _BadgeCandidate {
  _BadgeCandidate({
    required this.key,
    required this.name,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.gradientStart,
    required this.gradientEnd,
    required this.mediaRefs,
    required this.detailChips,
    required this.score,
    required this.eligible,
    required this.sampleSize,
    required this.debugWhy,
    Map<String, Object?>? extras,
  }) : meta = <String, Object?>{
         "emoji": emoji,
         "gradient": <String>[gradientStart, gradientEnd],
         "detailChips": detailChips,
         "score": score,
         "uploadedFileIDs": mediaRefs
             .map((MediaRef ref) => ref.uploadedFileID)
             .where((int id) => id > 0)
             .toList(growable: false),
         "extras": extras ?? const <String, Object?>{},
       },
       deterministicTieBreaker = _stableHash(key);

  final String key;
  final String name;
  final String title;
  final String subtitle;
  final String emoji;
  final String gradientStart;
  final String gradientEnd;
  final List<MediaRef> mediaRefs;
  final List<String> detailChips;
  final double score;
  final bool eligible;
  final int sampleSize;
  final String debugWhy;
  final Map<String, Object?> meta;
  final int deterministicTieBreaker;

  Map<String, Object?> toMetaMap() {
    return <String, Object?>{
      "key": key,
      "name": name,
      "score": score,
      "eligible": eligible,
      "sampleSize": sampleSize,
      "debugWhy": debugWhy,
      "emoji": emoji,
      "gradient": <String>[gradientStart, gradientEnd],
      "detailChips": detailChips,
      "subtitle": subtitle,
      "title": title,
      ...((meta["extras"] as Map<String, Object?>?) ?? const {}),
    };
  }
}

class _BadgeComputationContext {
  _BadgeComputationContext({
    required this.year,
    required this.totalCount,
    required this.daysWithCaptures,
    required this.elapsedDays,
    required this.longestStreakDays,
    required this.peopleStats,
    this.placesStats,
    required this.highlightMedia,
  });

  final int year;
  final int totalCount;
  final int daysWithCaptures;
  final int elapsedDays;
  final int longestStreakDays;
  final _PeopleDataset peopleStats;
  final _BadgePlaceStats? placesStats;
  final List<MediaRef> highlightMedia;

  static _BadgeComputationContext fromEngineContext({
    required WrappedEngineContext context,
  }) {
    final _StatsSnapshot statsSnapshot = _StatsSnapshot.fromContext(context);
    final _PeopleDataset peopleDataset = _PeopleDataset.fromContext(
      context.people,
      context.year,
    );
    final _PlacesDataset placesDataset = _PlacesDataset.fromContext(context);

    final int totalCount = statsSnapshot.totalCount;

    final Set<int> highlightIds = _collectUnique(<List<int>>[
      statsSnapshot.firstCaptureUploadedIDs,
      statsSnapshot.lastCaptureUploadedIDs,
      statsSnapshot.streakStartUploadedIDs,
      statsSnapshot.busiestDayMediaUploadedIDs,
    ]);

    final _BadgePlaceStats? placeStats = placesDataset.totalCount > 0
        ? _BadgePlaceStats(placesDataset)
        : null;

    return _BadgeComputationContext(
      year: context.year,
      totalCount: totalCount,
      daysWithCaptures: statsSnapshot.daysWithCaptures,
      elapsedDays: statsSnapshot.elapsedDays,
      longestStreakDays: statsSnapshot.longestStreakDays,
      peopleStats: peopleDataset,
      placesStats: placeStats,
      highlightMedia: highlightIds.map(MediaRef.new).toList(growable: false),
    );
  }

  static Set<int> _collectUnique(List<List<int>> sources) {
    final Set<int> unique = <int>{};
    for (final List<int> source in sources) {
      for (final int id in source) {
        if (id > 0) {
          unique.add(id);
        }
      }
      if (unique.length >= 6) {
        break;
      }
    }
    return unique;
  }
}

class _BadgePlaceStats {
  _BadgePlaceStats._({
    required this.totalCount,
    required this.uniqueCities,
    required this.uniqueCountries,
    required this.heroMedia,
    required this.primaryCountryCount,
    required this.outsidePrimaryCountryCount,
  });

  factory _BadgePlaceStats(_PlacesDataset dataset) {
    final int totalCount = dataset.totalCount;
    final List<_PlaceClusterSummary> cityClusters = dataset.cityClusters;
    final int uniqueCities = cityClusters.length;
    final int uniqueCountries = cityClusters
        .map((_PlaceClusterSummary summary) => summary.label?.country)
        .whereType<String>()
        .toSet()
        .length;
    final List<int> heroMedia = cityClusters
        .expand(
          (_PlaceClusterSummary cluster) =>
              cluster.sampleMediaIds(2, preferDistinctDays: true),
        )
        .take(6)
        .toList(growable: false);

    final int primaryCountryCount = _primaryCountryCaptureCount(
      totalCount: totalCount,
      clusters: cityClusters,
    );
    final int outsidePrimaryCountryCount = math.max(
      totalCount - primaryCountryCount,
      0,
    );

    return _BadgePlaceStats._(
      totalCount: totalCount,
      uniqueCities: uniqueCities,
      uniqueCountries: uniqueCountries,
      heroMedia: heroMedia,
      primaryCountryCount: primaryCountryCount,
      outsidePrimaryCountryCount: outsidePrimaryCountryCount,
    );
  }

  static int _primaryCountryCaptureCount({
    required int totalCount,
    required List<_PlaceClusterSummary> clusters,
  }) {
    if (totalCount <= 0) {
      return 0;
    }
    if (clusters.isEmpty) {
      return totalCount;
    }
    final Map<String, int> histogram = <String, int>{};
    int accounted = 0;
    for (final _PlaceClusterSummary cluster in clusters) {
      final String countryKey;
      final String? labelCountry = cluster.label?.country;
      if (labelCountry == null || labelCountry.trim().isEmpty) {
        countryKey = "_unknown";
      } else {
        countryKey = labelCountry;
      }
      histogram[countryKey] = (histogram[countryKey] ?? 0) + cluster.totalCount;
      accounted += cluster.totalCount;
    }
    final int uncovered = math.max(totalCount - accounted, 0);
    if (uncovered > 0) {
      histogram["_unknown"] = (histogram["_unknown"] ?? 0) + uncovered;
    }
    return histogram.values.isEmpty
        ? totalCount
        : histogram.values.reduce(math.max);
  }

  final int totalCount;
  final int uniqueCities;
  final int uniqueCountries;
  final List<int> heroMedia;
  final int primaryCountryCount;
  final int outsidePrimaryCountryCount;
}

int _stableHash(String input) {
  int hash = 17;
  for (int i = 0; i < input.length; i += 1) {
    hash = (hash * 31 + input.codeUnitAt(i)) & 0x7fffffff;
  }
  return hash;
}
