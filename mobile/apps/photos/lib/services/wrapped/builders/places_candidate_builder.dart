part of 'package:photos/services/wrapped/candidate_builders.dart';

class PlacesCandidateBuilder extends WrappedCandidateBuilder {
  const PlacesCandidateBuilder();

  static const double _kCityClusterRadiusKm = 12.0;
  static const double _kSpotClusterRadiusKm = 0.1;
  static const int _kMinCityCaptures = 12;
  static const int _kMinSpotCaptures = 6;
  static const int _kMinSpotDistinctDays = 2;
  static const double _kMaxCityLabelDistanceKm = 120.0;
  static const int _kTopCityMediaCount = 3;
  static const int _kSpotMediaCount = 6;

  @override
  String get debugLabel => "places";

  @override
  Future<List<WrappedCard>> build(WrappedEngineContext context) async {
    final _PlacesDataset dataset = _PlacesDataset.fromContext(context);
    if (!dataset.hasAnyContent) {
      return const <WrappedCard>[];
    }

    final List<WrappedCard> cards = <WrappedCard>[];

    final WrappedCard? topCities = _buildTopCitiesCard(context, dataset);
    if (topCities != null) {
      cards.add(topCities);
    }

    final WrappedCard? mostVisited = _buildMostVisitedSpotCard(
      context,
      dataset,
      takenIds: cardsMediaIds(cards),
    );
    if (mostVisited != null) {
      cards.add(mostVisited);
    }

    return cards;
  }

  WrappedCard? _buildTopCitiesCard(
    WrappedEngineContext context,
    _PlacesDataset dataset,
  ) {
    if (dataset.cityClusters.isEmpty || dataset.totalCount == 0) {
      return null;
    }
    final List<_PlaceClusterSummary> topClusters = dataset.cityClusters
        .take(3)
        .toList(growable: false);
    if (topClusters.isEmpty) {
      return null;
    }

    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final List<String> nameHighlights = <String>[
      for (final _PlaceClusterSummary cluster in topClusters)
        cluster.displayLabel,
    ];

    final List<String> detailChips = <String>[
      for (final _PlaceClusterSummary cluster in topClusters)
        "${cluster.displayLabel}: ${numberFormat.format(cluster.totalCount)}",
    ];

    final String subtitle = switch (nameHighlights.length) {
      0 => "You kept moving and the camera tagged along.",
      1 =>
        "${nameHighlights.first} soaked up ${numberFormat.format(topClusters.first.totalCount)} captures.",
      2 =>
        "${nameHighlights.first} and ${nameHighlights[1]} were your go-to cities.",
      _ => "${_formatList(nameHighlights)} kept pulling you back.",
    };

    final List<int> mediaIds = _collectMediaIds(
      context: context,
      clusters: topClusters,
      maxCount: _kTopCityMediaCount,
    );
    if (mediaIds.isEmpty) {
      return null;
    }

    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: mediaIds,
      maxCount: _kTopCityMediaCount,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 45),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      mediaIds,
      _kTopCityMediaCount * 2,
    );

    final Map<String, Object?> meta = <String, Object?>{
      "year": context.year,
      "totalGeotaggedCount": dataset.totalCount,
      "displayDurationMillis": 6500,
      "cities": <Map<String, Object?>>[
        for (final _PlaceClusterSummary cluster in topClusters)
          <String, Object?>{
            "name": cluster.label?.city,
            "country": cluster.label?.country,
            "displayLabel": cluster.displayLabel,
            "count": cluster.totalCount,
            "distinctDays": cluster.distinctDays,
            "centerLatitude": cluster.centerLatitude,
            "centerLongitude": cluster.centerLongitude,
            "sharePercent": _percentOf(
              cluster.totalCount / dataset.totalCount.toDouble(),
            ),
            "distanceKm": cluster.label?.distanceKm,
            "firstCapture": cluster.firstCaptureIsoString,
            "lastCapture": cluster.lastCaptureIsoString,
          },
      ],
      "detailChips": detailChips,
    };

    return WrappedCard(
      type: WrappedCardType.topCities,
      title: "City circuit",
      subtitle: subtitle,
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  WrappedCard? _buildMostVisitedSpotCard(
    WrappedEngineContext context,
    _PlacesDataset dataset, {
    Set<int>? takenIds,
  }) {
    if (dataset.spotClusters.isEmpty || dataset.totalCount == 0) {
      return null;
    }
    final Iterable<_PlaceClusterSummary> eligible = dataset.spotClusters.where(
      (_PlaceClusterSummary summary) =>
          summary.totalCount >= _kMinSpotCaptures &&
          summary.distinctDays >= _kMinSpotDistinctDays,
    );
    final _PlaceClusterSummary? cluster = eligible.isEmpty
        ? null
        : eligible.first;
    if (cluster == null) {
      return null;
    }
    final NumberFormat numberFormat = NumberFormat.decimalPattern();

    final List<int> mediaIds = _collectMediaIds(
      context: context,
      clusters: <_PlaceClusterSummary>[cluster],
      maxCount: _kSpotMediaCount,
      exclude: takenIds,
      preferDistinctDays: true,
    );
    if (mediaIds.isEmpty) {
      return null;
    }

    final String countText = numberFormat.format(cluster.totalCount);
    final int distinctDays = cluster.distinctDays;
    final String subtitle = distinctDays <= 0
        ? "You made $countText memories here."
        : distinctDays == 1
        ? "You made $countText memories here in a single day."
        : "You made $countText memories here across ${numberFormat.format(distinctDays)} days.";

    final List<MediaRef> media = WrappedMediaSelector.selectMediaRefs(
      context: context,
      candidateUploadedFileIDs: mediaIds,
      maxCount: _kSpotMediaCount,
      preferNamedPeople: true,
      minimumSpacing: const Duration(days: 30),
    );
    final List<int> metaUploadedIDs = buildMetaUploadedIDs(
      mediaIds,
      _kSpotMediaCount * 2,
    );

    final int sharePercent = _percentOf(
      cluster.totalCount / dataset.totalCount.toDouble(),
    );
    final List<String> detailChips = _cleanChips(<String>[
      if (sharePercent > 0) "Share: $sharePercent%",
    ]);

    final Map<String, Object?> meta = <String, Object?>{
      "year": context.year,
      "displayDurationMillis": 6500,
      "spot": <String, Object?>{
        "name": cluster.label?.city,
        "country": cluster.label?.country,
        "displayLabel": cluster.displayLabel,
        "count": cluster.totalCount,
        "distinctDays": cluster.distinctDays,
        "centerLatitude": cluster.centerLatitude,
        "centerLongitude": cluster.centerLongitude,
        "sharePercent": _percentOf(
          cluster.totalCount / dataset.totalCount.toDouble(),
        ),
        "distanceKm": cluster.label?.distanceKm,
        "firstCapture": cluster.firstCaptureIsoString,
        "lastCapture": cluster.lastCaptureIsoString,
      },
      "detailChips": detailChips,
    };

    return WrappedCard(
      type: WrappedCardType.mostVisitedSpot,
      title: "Go-to spot",
      subtitle: subtitle,
      media: media,
      meta: meta
        ..addAll(<String, Object?>{
          if (metaUploadedIDs.isNotEmpty) "uploadedFileIDs": metaUploadedIDs,
        }),
    );
  }

  Set<int> cardsMediaIds(List<WrappedCard> cards) {
    final Set<int> ids = <int>{};
    for (final WrappedCard card in cards) {
      for (final MediaRef media in card.media) {
        ids.add(media.uploadedFileID);
      }
    }
    return ids;
  }

  List<int> _collectMediaIds({
    required WrappedEngineContext context,
    required List<_PlaceClusterSummary> clusters,
    required int maxCount,
    Set<int>? exclude,
    bool preferDistinctDays = false,
  }) {
    final Set<int> seen = exclude != null ? Set<int>.from(exclude) : <int>{};
    final List<int> collected = <int>[];
    if (clusters.isEmpty || maxCount <= 0) {
      return collected;
    }

    const int candidateLimit = kWrappedSelectorCandidateCap;
    for (final _PlaceClusterSummary cluster in clusters) {
      final int perClusterLimit = math.min(
        candidateLimit,
        math.max(cluster.totalCount, maxCount),
      );
      final List<int> clusterIds = cluster.sampleMediaIds(
        perClusterLimit,
        preferDistinctDays: preferDistinctDays,
      );
      for (final int id in clusterIds) {
        if (id <= 0 || seen.contains(id)) {
          continue;
        }
        if (!context.isSelectableUploadedFileID(id)) {
          continue;
        }
        collected.add(id);
        seen.add(id);
        if (collected.length >= candidateLimit) {
          return collected;
        }
      }
    }
    return collected;
  }

  static int _percentOf(double ratio) {
    if (!ratio.isFinite || ratio <= 0) {
      return 0;
    }
    return (ratio * 100).round();
  }

  static String _formatList(List<String> values) {
    if (values.isEmpty) {
      return "";
    }
    if (values.length == 1) {
      return values.first;
    }
    if (values.length == 2) {
      return "${values.first} & ${values[1]}";
    }
    return "${values.take(values.length - 1).join(', ')} & ${values.last}";
  }
}

class _PlacesDataset {
  _PlacesDataset._({
    required this.totalCount,
    required List<_PlaceClusterSummary> cityClusters,
    required List<_PlaceClusterSummary> spotClusters,
  }) : cityClusters = List<_PlaceClusterSummary>.unmodifiable(cityClusters),
       spotClusters = List<_PlaceClusterSummary>.unmodifiable(spotClusters);

  final int totalCount;
  final List<_PlaceClusterSummary> cityClusters;
  final List<_PlaceClusterSummary> spotClusters;

  bool get hasAnyContent => cityClusters.isNotEmpty || spotClusters.isNotEmpty;

  static _PlacesDataset fromContext(WrappedEngineContext context) {
    final List<_GeoFile> geoFiles = <_GeoFile>[];
    for (final EnteFile file in context.files) {
      if (!file.hasLocation) {
        continue;
      }
      final Location? location = file.location;
      if (location == null ||
          location.latitude == null ||
          location.longitude == null) {
        continue;
      }
      final double lat = location.latitude!;
      final double lng = location.longitude!;
      if (!lat.isFinite || !lng.isFinite) {
        continue;
      }
      final int? uploadedId = file.uploadedFileID;
      final int? captureMicros = file.creationTime;
      if (uploadedId == null || uploadedId <= 0) {
        continue;
      }
      if (captureMicros == null || captureMicros <= 0) {
        continue;
      }
      geoFiles.add(
        _GeoFile(
          uploadedFileID: uploadedId,
          captureMicros: captureMicros,
          latitude: lat,
          longitude: lng,
        ),
      );
    }

    if (geoFiles.isEmpty) {
      return _PlacesDataset._(
        totalCount: 0,
        cityClusters: const <_PlaceClusterSummary>[],
        spotClusters: const <_PlaceClusterSummary>[],
      );
    }

    final List<_PlaceClusterSummary> cityClusters =
        _summariesForRadius(
              geoFiles: geoFiles,
              radiusKm: PlacesCandidateBuilder._kCityClusterRadiusKm,
              cities: context.cities,
            )
            .where(
              (_PlaceClusterSummary summary) =>
                  summary.totalCount >=
                  PlacesCandidateBuilder._kMinCityCaptures,
            )
            .toList(growable: false)
          ..sort(
            (_PlaceClusterSummary a, _PlaceClusterSummary b) =>
                b.totalCount.compareTo(a.totalCount),
          );

    final List<_PlaceClusterSummary> spotClusters =
        _summariesForRadius(
              geoFiles: geoFiles,
              radiusKm: PlacesCandidateBuilder._kSpotClusterRadiusKm,
              cities: context.cities,
            )
            .where(
              (_PlaceClusterSummary summary) =>
                  summary.totalCount >=
                  PlacesCandidateBuilder._kMinSpotCaptures,
            )
            .toList(growable: false)
          ..sort((_PlaceClusterSummary a, _PlaceClusterSummary b) {
            final int countCompare = b.totalCount.compareTo(a.totalCount);
            if (countCompare != 0) {
              return countCompare;
            }
            return b.distinctDays.compareTo(a.distinctDays);
          });

    return _PlacesDataset._(
      totalCount: geoFiles.length,
      cityClusters: cityClusters,
      spotClusters: spotClusters,
    );
  }

  static List<_PlaceClusterSummary> _summariesForRadius({
    required List<_GeoFile> geoFiles,
    required double radiusKm,
    required List<WrappedCity> cities,
  }) {
    final List<_PlaceCluster> clusters = _clusterGeoFiles(geoFiles, radiusKm);
    return clusters
        .map((_PlaceCluster cluster) {
          final _ClusterLabel? label = _resolveLabel(
            cluster.centerLatitude,
            cluster.centerLongitude,
            cities,
          );
          return _PlaceClusterSummary.fromCluster(
            cluster: cluster,
            label: label,
          );
        })
        .toList(growable: false);
  }

  static _ClusterLabel? _resolveLabel(
    double lat,
    double lng,
    List<WrappedCity> cities,
  ) {
    if (cities.isEmpty) {
      return null;
    }
    WrappedCity? closest;
    double bestDistance = PlacesCandidateBuilder._kMaxCityLabelDistanceKm;
    for (final WrappedCity city in cities) {
      if (city.latitude == 0 && city.longitude == 0) {
        continue;
      }
      final double distance = _distanceKm(
        lat,
        lng,
        city.latitude,
        city.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        closest = city;
      }
    }
    if (closest == null) {
      return null;
    }
    return _ClusterLabel(
      city: closest.name,
      country: closest.country,
      distanceKm: bestDistance,
    );
  }
}

class _PlaceClusterSummary {
  _PlaceClusterSummary._({
    required List<_GeoFile> files,
    required this.centerLatitude,
    required this.centerLongitude,
    required this.distinctDays,
    required this.firstCaptureMicros,
    required this.lastCaptureMicros,
    this.label,
  }) : files = List<_GeoFile>.unmodifiable(files);

  final List<_GeoFile> files;
  final double centerLatitude;
  final double centerLongitude;
  final int distinctDays;
  final int firstCaptureMicros;
  final int lastCaptureMicros;
  final _ClusterLabel? label;

  int get totalCount => files.length;

  DateTime? get firstCapture => firstCaptureMicros <= 0
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(firstCaptureMicros);
  DateTime? get lastCapture => lastCaptureMicros <= 0
      ? null
      : DateTime.fromMicrosecondsSinceEpoch(lastCaptureMicros);

  String? get firstCaptureIsoString => firstCapture?.toIso8601String();
  String? get lastCaptureIsoString => lastCapture?.toIso8601String();

  String get displayLabel {
    if (label != null) {
      final String? name = label!.city.isNotEmpty
          ? label!.city
          : (label!.country.isNotEmpty ? label!.country : null);
      if (name != null && name.trim().isNotEmpty) {
        return name;
      }
    }
    return _formatCoordinates(centerLatitude, centerLongitude);
  }

  List<int> sampleMediaIds(int maxCount, {bool preferDistinctDays = false}) {
    if (files.isEmpty) {
      return const <int>[];
    }
    final List<_GeoFile> sorted = files.toList(growable: false)
      ..sort(
        (_GeoFile a, _GeoFile b) => a.captureMicros.compareTo(b.captureMicros),
      );
    final List<_GeoFile> unique = <_GeoFile>[];
    final Set<int> seenIds = <int>{};
    for (final _GeoFile file in sorted) {
      if (seenIds.add(file.uploadedFileID)) {
        unique.add(file);
      }
    }
    if (unique.isEmpty) {
      return const <int>[];
    }

    final List<_GeoFile> samplingSource = preferDistinctDays
        ? _preferDistinctDaySource(unique, maxCount)
        : unique;

    if (samplingSource.isEmpty) {
      return const <int>[];
    }
    if (samplingSource.length <= maxCount) {
      return samplingSource
          .map((_GeoFile file) => file.uploadedFileID)
          .toList(growable: false);
    }

    final Set<int> usedIndices = <int>{};
    final List<int> selected = <int>[];
    for (int i = 0; i < maxCount; i++) {
      final int denominator = math.max(maxCount - 1, 1);
      final double ratio = maxCount == 1 ? 0 : i / denominator;
      int index = (ratio * (samplingSource.length - 1)).round();
      index = _findClosestAvailableIndex(
        index: index,
        length: samplingSource.length,
        used: usedIndices,
      );
      usedIndices.add(index);
      selected.add(samplingSource[index].uploadedFileID);
    }
    return selected;
  }

  List<_GeoFile> _preferDistinctDaySource(List<_GeoFile> unique, int maxCount) {
    final Map<int, _GeoFile> firstPerDay = <int, _GeoFile>{};
    for (final _GeoFile file in unique) {
      final DateTime timestamp = DateTime.fromMicrosecondsSinceEpoch(
        file.captureMicros,
      );
      final DateTime day = DateTime(
        timestamp.year,
        timestamp.month,
        timestamp.day,
      );
      final int dayKey = day.millisecondsSinceEpoch;
      firstPerDay.putIfAbsent(dayKey, () => file);
    }
    final List<MapEntry<int, _GeoFile>> dayEntries =
        firstPerDay.entries.toList()..sort(
          (MapEntry<int, _GeoFile> a, MapEntry<int, _GeoFile> b) =>
              a.key.compareTo(b.key),
        );
    final List<_GeoFile> distinctDayFiles = dayEntries
        .map((MapEntry<int, _GeoFile> entry) => entry.value)
        .toList();
    if (distinctDayFiles.length >= maxCount) {
      return distinctDayFiles;
    }
    final Set<int> seenIds = distinctDayFiles
        .map((_GeoFile file) => file.uploadedFileID)
        .toSet();
    final List<_GeoFile> fallback = <_GeoFile>[
      for (final _GeoFile file in unique)
        if (!seenIds.contains(file.uploadedFileID)) file,
    ];
    if (fallback.isEmpty) {
      return distinctDayFiles;
    }
    return <_GeoFile>[...distinctDayFiles, ...fallback];
  }

  static int _findClosestAvailableIndex({
    required int index,
    required int length,
    required Set<int> used,
  }) {
    if (!used.contains(index)) {
      return index;
    }
    for (int offset = 1; offset < length; offset++) {
      final int before = index - offset;
      if (before >= 0 && !used.contains(before)) {
        return before;
      }
      final int after = index + offset;
      if (after < length && !used.contains(after)) {
        return after;
      }
    }
    return index.clamp(0, length - 1);
  }

  static _PlaceClusterSummary fromCluster({
    required _PlaceCluster cluster,
    _ClusterLabel? label,
  }) {
    final List<_GeoFile> sorted = cluster.files.toList(growable: false)
      ..sort(
        (_GeoFile a, _GeoFile b) => a.captureMicros.compareTo(b.captureMicros),
      );
    final Set<int> dayKeys = <int>{};
    for (final _GeoFile file in sorted) {
      final DateTime timestamp = DateTime.fromMicrosecondsSinceEpoch(
        file.captureMicros,
      );
      final DateTime day = DateTime(
        timestamp.year,
        timestamp.month,
        timestamp.day,
      );
      dayKeys.add(day.millisecondsSinceEpoch);
    }
    final int firstMicros = sorted.first.captureMicros;
    final int lastMicros = sorted.last.captureMicros;

    return _PlaceClusterSummary._(
      files: sorted,
      centerLatitude: cluster.centerLatitude,
      centerLongitude: cluster.centerLongitude,
      distinctDays: dayKeys.length,
      firstCaptureMicros: firstMicros,
      lastCaptureMicros: lastMicros,
      label: label,
    );
  }
}

class _PlaceCluster {
  _PlaceCluster(_GeoFile initial)
    : files = <_GeoFile>[initial],
      _sumLat = initial.latitude,
      _sumLng = initial.longitude;

  final List<_GeoFile> files;
  double _sumLat;
  double _sumLng;

  double get centerLatitude => _sumLat / files.length;
  double get centerLongitude => _sumLng / files.length;

  void add(_GeoFile file) {
    files.add(file);
    _sumLat += file.latitude;
    _sumLng += file.longitude;
  }
}

class _GeoFile {
  const _GeoFile({
    required this.uploadedFileID,
    required this.captureMicros,
    required this.latitude,
    required this.longitude,
  });

  final int uploadedFileID;
  final int captureMicros;
  final double latitude;
  final double longitude;
}

class _ClusterLabel {
  const _ClusterLabel({
    required this.city,
    required this.country,
    required this.distanceKm,
  });

  final String city;
  final String country;
  final double distanceKm;
}

List<_PlaceCluster> _clusterGeoFiles(List<_GeoFile> files, double radiusKm) {
  if (files.isEmpty) {
    return const <_PlaceCluster>[];
  }
  final List<_PlaceCluster> clusters = <_PlaceCluster>[];
  for (final _GeoFile file in files) {
    _PlaceCluster? bestCluster;
    double bestDistance = radiusKm;
    for (final _PlaceCluster cluster in clusters) {
      final double distance = _distanceKm(
        file.latitude,
        file.longitude,
        cluster.centerLatitude,
        cluster.centerLongitude,
      );
      if (distance <= radiusKm && distance < bestDistance) {
        bestDistance = distance;
        bestCluster = cluster;
      }
    }
    if (bestCluster == null) {
      clusters.add(_PlaceCluster(file));
    } else {
      bestCluster.add(file);
    }
  }
  return clusters;
}

double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadiusKm = 6371.0;
  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);
  final double a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRadians(double degrees) {
  return degrees * math.pi / 180;
}

String _formatCoordinates(double latitude, double longitude) {
  final String latHemisphere = latitude >= 0 ? "N" : "S";
  final String lonHemisphere = longitude >= 0 ? "E" : "W";
  return "${latitude.abs().toStringAsFixed(2)}°$latHemisphere · "
      "${longitude.abs().toStringAsFixed(2)}°$lonHemisphere";
}
