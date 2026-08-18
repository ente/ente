part of "smart_memories_service.dart";

class _LocationCluster {
  final List<EnteFile> files;
  double _latitudeSum;
  double _longitudeSum;
  Location _center;

  _LocationCluster(EnteFile file)
    : files = [file],
      _latitudeSum = file.location!.latitude!,
      _longitudeSum = file.location!.longitude!,
      _center = file.location!;

  _LocationCluster.fromFiles(Iterable<EnteFile> files)
    : files = List<EnteFile>.from(files),
      _latitudeSum = 0,
      _longitudeSum = 0,
      _center = const Location(latitude: 0, longitude: 0) {
    for (final file in this.files) {
      _latitudeSum += file.location!.latitude!;
      _longitudeSum += file.location!.longitude!;
    }
    _recalculateCenter();
  }

  Location get center => _center;

  int get firstCreationTime => files
      .map((file) => file.creationTime!)
      .reduce((value, element) => min(value, element));

  int get lastCreationTime => files
      .map((file) => file.creationTime!)
      .reduce((value, element) => max(value, element));

  void addFile(EnteFile file) {
    files.add(file);
    _latitudeSum += file.location!.latitude!;
    _longitudeSum += file.location!.longitude!;
    _recalculateCenter();
  }

  void addCluster(_LocationCluster cluster) {
    files.addAll(cluster.files);
    _latitudeSum += cluster._latitudeSum;
    _longitudeSum += cluster._longitudeSum;
    _recalculateCenter();
  }

  void _recalculateCenter() {
    _center = Location(
      latitude: _latitudeSum / files.length,
      longitude: _longitudeSum / files.length,
    );
  }
}

class _TripAnniversaryWindow {
  final DateTime start;
  final DateTime end;
  final int distanceDays;

  const _TripAnniversaryWindow({
    required this.start,
    required this.end,
    required this.distanceDays,
  });
}

class _TripSurfaceCandidate {
  final TripMemory trip;
  final String identityKey;
  final _TripAnniversaryWindow anniversaryWindow;
  final DateTime? lastShownAt;
  final bool cooldownExpired;

  const _TripSurfaceCandidate({
    required this.trip,
    required this.identityKey,
    required this.anniversaryWindow,
    required this.lastShownAt,
    required this.cooldownExpired,
  });
}

class TripMemoriesAnalysis {
  final List<BaseLocation> baseLocations;
  final Set<String> baseCountriesToExclude;
  final List<TripMemory> tripCandidates;

  const TripMemoriesAnalysis({
    required this.baseLocations,
    required this.baseCountriesToExclude,
    required this.tripCandidates,
  });
}

class TripMemoriesCalculatorV2 {
  static const _maxTemporalGapDays = 15;

  // Spatial distance constants in this class use kilometers.
  static const _tripClusterRadius = 25.0;

  static const _chainHopDistance = 800.0;

  static const _baseOverlapRadius = 10.0;

  static const _baseMergeRadius = 1.5;

  static const _minBasePhotos = 10;
  static const _minBaseActiveDays = 10;
  static const _minBaseActiveWeeks = 6;
  static const _minBaseActiveMonths = 2;
  static const _minBaseSpanDays = 45;
  static const _baseDensityWindowDays = 120;
  static const _minBaseActiveDaysInWindow = 12;

  static const _minTripDays = 2;
  static const _maxTripDays = 30;

  static const _minTripPhotos = 20;

  // Keep small clusters separate so stray photos cannot join valid trips.
  static const _minChainClusterPhotos = 5;

  static const _mergeWindowDays = 2;

  static const _mergeMaxDistance = 25.0;

  static const _tripDisplayDuration = Duration(days: 10);
  static const _seasonalTripBandDays = 45;

  static Future<(List<TripMemory>, List<BaseLocation>)> compute(
    Iterable<EnteFile> allFiles,
    Map<int, EnteFile> allFileIdsToFile,
    DateTime currentTime,
    List<TripsShownLog> shownTrips, {
    bool surfaceAll = false,
    required Iterable<ToShowMemory> cachedTripMemories,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required CitySearchIndex citySearchIndex,
  }) async {
    final analysis = analyze(
      allFiles,
      allFileIdsToFile,
      isLocalGalleryMode: isLocalGalleryMode,
      seenTimes: seenTimes,
      citySearchIndex: citySearchIndex,
    );
    return surface(
      analysis,
      allFileIdsToFile,
      currentTime,
      shownTrips,
      surfaceAll: surfaceAll,
      cachedTripMemories: cachedTripMemories,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
      citySearchIndex: citySearchIndex,
    );
  }

  static TripMemoriesAnalysis analyze(
    Iterable<EnteFile> allFiles,
    Map<int, EnteFile> allFileIdsToFile, {
    required bool isLocalGalleryMode,
    required Map<int, int> seenTimes,
    required CitySearchIndex citySearchIndex,
  }) {
    if (allFiles.isEmpty) {
      return const TripMemoriesAnalysis(
        baseLocations: <BaseLocation>[],
        baseCountriesToExclude: <String>{},
        tripCandidates: <TripMemory>[],
      );
    }

    final filesWithLocation = allFiles.where((f) => f.hasLocation).toList()
      ..sort((a, b) => a.creationTime!.compareTo(b.creationTime!));
    final baseLocations = _detectBaseLocations(
      filesWithLocation,
      isLocalGalleryMode: isLocalGalleryMode,
    );
    final baseCountriesToExclude = _baseCountriesToExcludeFromTripTitles(
      baseLocations,
      allFileIdsToFile,
      citySearchIndex,
      seenTimes,
    );

    if (filesWithLocation.isEmpty) {
      return TripMemoriesAnalysis(
        baseLocations: baseLocations,
        baseCountriesToExclude: baseCountriesToExclude,
        tripCandidates: const <TripMemory>[],
      );
    }

    // Returning to a base separates otherwise nearby trips.
    final temporalBlocks = _segmentAwayFilesByTime(
      filesWithLocation,
      baseLocations,
    );

    final rawTripCandidates = <TripMemory>[];
    for (final block in temporalBlocks) {
      var spatialClusters = _clusterByLocation(
        block,
        radius: _tripClusterRadius,
      );
      spatialClusters = _mergeChainedClusters(spatialClusters);

      for (final cluster in spatialClusters) {
        final files = List<EnteFile>.from(cluster.files)
          ..sort((a, b) => a.creationTime!.compareTo(b.creationTime!));
        final location = cluster.center;

        if (!_isValidTrip(files, location, baseLocations)) continue;

        rawTripCandidates.add(
          TripMemory(
            Memory.fromFiles(files, seenTimes),
            0,
            0,
            location,
            tripKey: _buildTripKey(
              location,
              files.first.creationTime!,
              files.last.creationTime!,
            ),
            firstCreationTime: files.first.creationTime!,
            lastCreationTime: files.last.creationTime!,
          ),
        );
      }
    }

    final mergedTrips = _mergeNearbyTrips(rawTripCandidates);

    final tripCandidates = mergedTrips
        .where((trip) => trip.memories.length >= _minTripPhotos)
        .map(_ensureTripKey)
        .toList();

    return TripMemoriesAnalysis(
      baseLocations: baseLocations,
      baseCountriesToExclude: baseCountriesToExclude,
      tripCandidates: tripCandidates,
    );
  }

  static Future<(List<TripMemory>, List<BaseLocation>)> surface(
    TripMemoriesAnalysis analysis,
    Map<int, EnteFile> allFileIdsToFile,
    DateTime currentTime,
    List<TripsShownLog> shownTrips, {
    bool surfaceAll = false,
    required Iterable<ToShowMemory> cachedTripMemories,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required CitySearchIndex citySearchIndex,
  }) async {
    final nowInMicroseconds = currentTime.microsecondsSinceEpoch;
    final windowEnd = currentTime
        .add(kMemoriesUpdateFrequency)
        .microsecondsSinceEpoch;
    final cutOffTime = currentTime.subtract(const Duration(days: 365));
    final baseLocations = analysis.baseLocations;
    final baseCountriesToExclude = analysis.baseCountriesToExclude;
    final validTrips = analysis.tripCandidates
        .where(
          (trip) =>
              trip.averageCreationTime() < cutOffTime.microsecondsSinceEpoch,
        )
        .toList();

    final List<TripMemory> memoryResults = [];

    if (surfaceAll) {
      return _surfaceAll(
        memoryResults,
        baseLocations,
        validTrips,
        allFileIdsToFile,
        baseCountriesToExclude,
        nowInMicroseconds,
        windowEnd,
        seenTimes: seenTimes,
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
        citySearchIndex: citySearchIndex,
      );
    }

    return _surfaceScheduled(
      memoryResults,
      baseLocations,
      validTrips,
      currentTime,
      nowInMicroseconds,
      shownTrips,
      baseCountriesToExclude: baseCountriesToExclude,
      cachedTripMemories: cachedTripMemories,
      isLocalGalleryMode: isLocalGalleryMode,
      mlEnabled: mlEnabled,
      seenTimes: seenTimes,
      fileIdToFaces: fileIdToFaces,
      faceIDsToPersonID: faceIDsToPersonID,
      fileIDToImageEmbedding: fileIDToImageEmbedding,
      clipPositiveTextVector: clipPositiveTextVector,
      citySearchIndex: citySearchIndex,
    );
  }

  static List<BaseLocation> _detectBaseLocations(
    List<EnteFile> filesWithLocation, {
    required bool isLocalGalleryMode,
  }) {
    final smallRadiusClusters = _mergeNearbyLocationClusters(
      _clusterByLocation(filesWithLocation, radius: baseRadius),
      radius: _baseMergeRadius,
    );

    final List<BaseLocation> baseLocations = [];
    for (final cluster in smallRadiusClusters) {
      final files = cluster.files;
      final location = cluster.center;
      if (!_isValidBaseLocation(files)) continue;

      final creationTimes = files.map((file) => file.creationTime!).toList()
        ..sort();
      final lastCreationTime = DateTime.fromMicrosecondsSinceEpoch(
        creationTimes.last,
      );
      final bool isCurrent = lastCreationTime.isAfter(
        DateTime.now().subtract(const Duration(days: 90)),
      );
      baseLocations.add(
        BaseLocation(
          files
              .map(
                (file) => SmartMemoriesService._memoryFileId(
                  file,
                  isLocalGalleryMode: isLocalGalleryMode,
                ),
              )
              .whereType<int>()
              .toList(),
          location,
          isCurrent,
        ),
      );
    }
    return baseLocations;
  }

  static List<List<EnteFile>> _segmentAwayFilesByTime(
    List<EnteFile> sortedFiles,
    List<BaseLocation> baseLocations,
  ) {
    final blocks = <List<EnteFile>>[];
    var currentBlock = <EnteFile>[];
    EnteFile? lastAwayFile;
    var sawBasePhotoSinceLastAway = false;

    for (final file in sortedFiles) {
      if (_isNearAnyBase(file.location!, baseLocations)) {
        if (currentBlock.isNotEmpty) {
          sawBasePhotoSinceLastAway = true;
        }
        continue;
      }

      if (currentBlock.isEmpty) {
        currentBlock = [file];
        lastAwayFile = file;
        sawBasePhotoSinceLastAway = false;
        continue;
      }

      final gapMicros = file.creationTime! - lastAwayFile!.creationTime!;
      final gapDays = gapMicros ~/ microSecondsInDay;
      if (gapDays > _maxTemporalGapDays || sawBasePhotoSinceLastAway) {
        blocks.add(currentBlock);
        currentBlock = [file];
      } else {
        currentBlock.add(file);
      }
      lastAwayFile = file;
      sawBasePhotoSinceLastAway = false;
    }

    if (currentBlock.isNotEmpty) {
      blocks.add(currentBlock);
    }
    return blocks;
  }

  static List<_LocationCluster> _clusterByLocation(
    Iterable<EnteFile> files, {
    required double radius,
  }) {
    final clusters = <_LocationCluster>[];
    for (final file in files) {
      bool added = false;
      for (final cluster in clusters) {
        if (isFileInsideLocationTag(cluster.center, file.location!, radius)) {
          cluster.addFile(file);
          added = true;
          break;
        }
      }
      if (!added) {
        clusters.add(_LocationCluster(file));
      }
    }
    return clusters;
  }

  static List<_LocationCluster> _mergeNearbyLocationClusters(
    List<_LocationCluster> clusters, {
    required double radius,
  }) {
    final mergedClusters = List<_LocationCluster>.from(clusters);
    bool didMerge = true;
    while (didMerge) {
      didMerge = false;
      for (int i = 0; i < mergedClusters.length; i++) {
        for (int j = i + 1; j < mergedClusters.length; j++) {
          final distance = calculateDistance(
            mergedClusters[i].center,
            mergedClusters[j].center,
          );
          if (distance > radius) continue;

          mergedClusters[i].addCluster(mergedClusters[j]);
          mergedClusters.removeAt(j);
          didMerge = true;
          break;
        }
        if (didMerge) break;
      }
    }
    return mergedClusters;
  }

  static List<_LocationCluster> _mergeChainedClusters(
    List<_LocationCluster> clusters,
  ) {
    if (clusters.length <= 1) return clusters;

    final sortedClusters = List<_LocationCluster>.from(clusters)
      ..sort((a, b) => a.firstCreationTime.compareTo(b.firstCreationTime));

    final chainable = <_LocationCluster>[];
    final tooSmall = <_LocationCluster>[];
    for (final cluster in sortedClusters) {
      if (cluster.files.length >= _minChainClusterPhotos) {
        chainable.add(cluster);
      } else {
        tooSmall.add(cluster);
      }
    }

    if (chainable.isEmpty) return clusters;

    final merged = <_LocationCluster>[];
    var currentCluster = _LocationCluster.fromFiles(chainable.first.files);

    for (int i = 1; i < chainable.length; i++) {
      final next = chainable[i];
      final distance = calculateDistance(currentCluster.center, next.center);
      final gapDays =
          DateTime.fromMicrosecondsSinceEpoch(next.firstCreationTime)
              .difference(
                DateTime.fromMicrosecondsSinceEpoch(
                  currentCluster.lastCreationTime,
                ),
              )
              .inDays;
      final allFiles = [...currentCluster.files, ...next.files];
      final times = allFiles.map((f) => f.creationTime!);
      final spanDays = DateTime.fromMicrosecondsSinceEpoch(times.reduce(max))
          .difference(DateTime.fromMicrosecondsSinceEpoch(times.reduce(min)))
          .inDays;
      if (distance <= _chainHopDistance &&
          gapDays <= _mergeWindowDays &&
          spanDays <= _maxTripDays) {
        currentCluster.addCluster(next);
      } else {
        merged.add(currentCluster);
        currentCluster = _LocationCluster.fromFiles(next.files);
      }
    }
    merged.add(currentCluster);

    return [...merged, ...tooSmall];
  }

  static bool _isValidTrip(
    List<EnteFile> files,
    Location location,
    List<BaseLocation> bases,
  ) {
    if (files.length < _minTripPhotos) return false;

    final times = files.map((f) => f.creationTime!).toList()..sort();
    final first = DateTime.fromMicrosecondsSinceEpoch(times.first);
    final last = DateTime.fromMicrosecondsSinceEpoch(times.last);
    final days = last.difference(first).inDays;
    if (days < _minTripDays) return false;

    return !_isNearAnyBase(location, bases);
  }

  static bool _isValidBaseLocation(List<EnteFile> files) {
    if (files.length < _minBasePhotos) return false;

    final creationTimes = files.map((file) => file.creationTime!).toList()
      ..sort();
    final uniqueDays = <int>{};
    final uniqueWeeks = <int>{};
    final uniqueMonths = <int>{};

    for (final creationTime in creationTimes) {
      final date = DateTime.fromMicrosecondsSinceEpoch(creationTime);
      uniqueDays.add(
        DateTime(date.year, date.month, date.day).microsecondsSinceEpoch,
      );
      final weekStart = DateTime(
        date.year,
        date.month,
        date.day,
      ).subtract(Duration(days: date.weekday - 1));
      uniqueWeeks.add(weekStart.microsecondsSinceEpoch);
      uniqueMonths.add(date.year * 100 + date.month);
    }

    final firstCreationTime = DateTime.fromMicrosecondsSinceEpoch(
      creationTimes.first,
    );
    final lastCreationTime = DateTime.fromMicrosecondsSinceEpoch(
      creationTimes.last,
    );
    final daysRange = lastCreationTime.difference(firstCreationTime).inDays;
    final sortedUniqueDays = uniqueDays.toList()..sort();

    return uniqueDays.length >= _minBaseActiveDays &&
        uniqueWeeks.length >= _minBaseActiveWeeks &&
        uniqueMonths.length >= _minBaseActiveMonths &&
        _hasDenseResidenceWindow(sortedUniqueDays) &&
        daysRange >= _minBaseSpanDays;
  }

  static bool _hasDenseResidenceWindow(List<int> sortedUniqueDays) {
    if (sortedUniqueDays.length < _minBaseActiveDaysInWindow) {
      return false;
    }

    var windowStart = 0;
    for (int windowEnd = 0; windowEnd < sortedUniqueDays.length; windowEnd++) {
      while (sortedUniqueDays[windowEnd] - sortedUniqueDays[windowStart] >
          _baseDensityWindowDays * microSecondsInDay) {
        windowStart++;
      }
      if (windowEnd - windowStart + 1 >= _minBaseActiveDaysInWindow) {
        return true;
      }
    }
    return false;
  }

  static List<TripMemory> _mergeNearbyTrips(List<TripMemory> trips) {
    final sortedTrips = List<TripMemory>.from(trips)
      ..sort((a, b) => a.firstCreationTime!.compareTo(b.firstCreationTime!));
    final merged = <TripMemory>[];
    for (final trip in sortedTrips) {
      final tripFirst = DateTime.fromMicrosecondsSinceEpoch(
        trip.firstCreationTime!,
      );
      final tripLast = DateTime.fromMicrosecondsSinceEpoch(
        trip.lastCreationTime!,
      );
      bool didMerge = false;
      for (int i = 0; i < merged.length; i++) {
        final other = merged[i];
        final otherFirst = DateTime.fromMicrosecondsSinceEpoch(
          other.firstCreationTime!,
        );
        final otherLast = DateTime.fromMicrosecondsSinceEpoch(
          other.lastCreationTime!,
        );
        final timeClose =
            tripFirst.isBefore(
              otherLast.add(const Duration(days: _mergeWindowDays)),
            ) &&
            tripLast.isAfter(
              otherFirst.subtract(const Duration(days: _mergeWindowDays)),
            );
        final spaceClose =
            calculateDistance(trip.location, other.location) <
            _mergeMaxDistance;
        final mergedFirst = tripFirst.isBefore(otherFirst)
            ? tripFirst
            : otherFirst;
        final mergedLast = tripLast.isAfter(otherLast) ? tripLast : otherLast;
        final mergedSpanDays = mergedLast.difference(mergedFirst).inDays;
        if (timeClose && spaceClose && mergedSpanDays <= _maxTripDays) {
          final combinedMemories = other.memories + trip.memories;
          final mergedLocation = _representativeLocationFromMemories(
            combinedMemories,
          );
          final mergedFirstCreationTime = min(
            other.firstCreationTime!,
            trip.firstCreationTime!,
          );
          final mergedLastCreationTime = max(
            other.lastCreationTime!,
            trip.lastCreationTime!,
          );
          merged[i] = TripMemory(
            combinedMemories,
            0,
            0,
            mergedLocation,
            tripKey: _buildTripKey(
              mergedLocation,
              mergedFirstCreationTime,
              mergedLastCreationTime,
            ),
            firstCreationTime: mergedFirstCreationTime,
            lastCreationTime: mergedLastCreationTime,
          );
          didMerge = true;
          break;
        }
      }
      if (!didMerge) merged.add(trip);
    }
    return merged;
  }

  static bool _isNearAnyBase(
    Location location,
    List<BaseLocation> baseLocations,
  ) {
    for (final baseLocation in baseLocations) {
      if (isFileInsideLocationTag(
        baseLocation.location,
        location,
        _baseOverlapRadius,
      )) {
        return true;
      }
    }
    return false;
  }

  static Location _representativeLocationFromMemories(List<Memory> memories) {
    return _representativeLocationFromFiles(Memory.filesFromMemories(memories));
  }

  static Location _representativeLocationFromFiles(Iterable<EnteFile> files) {
    final filesWithLocation = files
        .where((file) => file.hasLocation)
        .toList(growable: false);
    assert(filesWithLocation.isNotEmpty);

    double latitudeSum = 0;
    double longitudeSum = 0;
    for (final file in filesWithLocation) {
      latitudeSum += file.location!.latitude!;
      longitudeSum += file.location!.longitude!;
    }

    return Location(
      latitude: latitudeSum / filesWithLocation.length,
      longitude: longitudeSum / filesWithLocation.length,
    );
  }

  static TripMemory _ensureTripKey(TripMemory trip) {
    if (trip.tripKey != null && trip.tripKey!.isNotEmpty) {
      return trip;
    }
    return trip.copyWith(
      tripKey: _buildTripKey(
        trip.location,
        trip.firstCreationTime!,
        trip.lastCreationTime!,
      ),
    );
  }

  static String _buildTripKey(
    Location location,
    int firstCreationTime,
    int lastCreationTime,
  ) {
    final latitude = (location.latitude ?? 0).toStringAsFixed(2);
    final longitude = (location.longitude ?? 0).toStringAsFixed(2);
    final firstDay = firstCreationTime ~/ microSecondsInDay;
    final lastDay = lastCreationTime ~/ microSecondsInDay;
    return "trip_${latitude}_${longitude}_${firstDay}_$lastDay";
  }

  static String _tripIdentityKey(TripMemory trip) {
    return "trip:${_ensureTripKey(trip).tripKey!}";
  }

  static List<String> _activeCachedTripIdentityKeys(
    Iterable<ToShowMemory> cachedTripMemories,
    DateTime currentTime,
  ) {
    final nowMicros = currentTime.microsecondsSinceEpoch;
    final active = <String>[];
    final seen = <String>{};
    for (final cachedTrip in cachedTripMemories) {
      if (cachedTrip.type != MemoryType.trips ||
          !cachedTrip.isRelevantAt(nowMicros)) {
        continue;
      }
      final identityKey = cachedTrip.tripIdentityKey;
      if (seen.add(identityKey)) {
        active.add(identityKey);
      }
    }
    return active.take(kTripSurfaceSlots).toList(growable: false);
  }

  static DateTime? _lastShownAtForTrip(
    TripMemory trip,
    List<TripsShownLog> shownTrips,
  ) {
    DateTime? latestShownAt;
    final tripKey = trip.tripKey;
    for (final shownTrip in shownTrips) {
      final sameTripKey =
          tripKey != null &&
          shownTrip.tripKey != null &&
          tripKey == shownTrip.tripKey;
      final sameLegacyLocation =
          shownTrip.tripKey == null &&
          calculateDistance(trip.location, shownTrip.location) <
              _baseOverlapRadius;
      if (!sameTripKey && !sameLegacyLocation) {
        continue;
      }
      final shownAt = DateTime.fromMicrosecondsSinceEpoch(
        shownTrip.lastTimeShown,
      );
      if (latestShownAt == null || shownAt.isAfter(latestShownAt)) {
        latestShownAt = shownAt;
      }
    }
    return latestShownAt;
  }

  static _TripAnniversaryWindow _nearestAnniversaryWindow(
    TripMemory trip,
    DateTime currentTime,
  ) {
    final tripStart = DateTime.fromMicrosecondsSinceEpoch(
      trip.firstCreationTime!,
    );
    final tripEnd = DateTime.fromMicrosecondsSinceEpoch(trip.lastCreationTime!);
    final yearOffset = tripEnd.year - tripStart.year;
    _TripAnniversaryWindow? bestWindow;

    for (final startYear in <int>[
      currentTime.year - 1,
      currentTime.year,
      currentTime.year + 1,
    ]) {
      final projectedStart = _copyDateToYear(tripStart, startYear);
      final projectedEnd = _copyDateToYear(tripEnd, startYear + yearOffset);
      final candidateWindow = _TripAnniversaryWindow(
        start: projectedStart,
        end: projectedEnd,
        distanceDays: _distanceToWindowInDays(
          currentTime,
          projectedStart,
          projectedEnd,
        ),
      );
      if (bestWindow == null ||
          candidateWindow.distanceDays < bestWindow.distanceDays ||
          (candidateWindow.distanceDays == bestWindow.distanceDays &&
              candidateWindow.start
                      .difference(currentTime)
                      .abs()
                      .compareTo(
                        bestWindow.start.difference(currentTime).abs(),
                      ) <
                  0)) {
        bestWindow = candidateWindow;
      }
    }

    return bestWindow!;
  }

  static DateTime _copyDateToYear(DateTime source, int year) {
    final lastDayOfMonth = DateTime(year, source.month + 1, 0).day;
    final day = min(source.day, lastDayOfMonth);
    return DateTime(
      year,
      source.month,
      day,
      source.hour,
      source.minute,
      source.second,
      source.millisecond,
      source.microsecond,
    );
  }

  static int _distanceToWindowInDays(
    DateTime currentTime,
    DateTime start,
    DateTime end,
  ) {
    if (!currentTime.isBefore(start) && !currentTime.isAfter(end)) {
      return 0;
    }
    if (currentTime.isBefore(start)) {
      return start.difference(currentTime).inDays;
    }
    return currentTime.difference(end).inDays;
  }

  static int _compareBoolFalseFirst(bool a, bool b) {
    if (a == b) return 0;
    return a ? 1 : -1;
  }

  static int _compareLastShownOldestFirst(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    return a.compareTo(b);
  }

  static int _compareSeasonalCandidates(
    _TripSurfaceCandidate a,
    _TripSurfaceCandidate b,
  ) {
    final cooldownCompare = _compareBoolFalseFirst(
      !a.cooldownExpired,
      !b.cooldownExpired,
    );
    if (cooldownCompare != 0) return cooldownCompare;

    final distanceCompare = a.anniversaryWindow.distanceDays.compareTo(
      b.anniversaryWindow.distanceDays,
    );
    if (distanceCompare != 0) return distanceCompare;

    final shownCompare = _compareLastShownOldestFirst(
      a.lastShownAt,
      b.lastShownAt,
    );
    if (shownCompare != 0) return shownCompare;

    return b.trip.averageCreationTime().compareTo(a.trip.averageCreationTime());
  }

  static int _compareEvergreenCandidates(
    _TripSurfaceCandidate a,
    _TripSurfaceCandidate b,
  ) {
    final cooldownCompare = _compareBoolFalseFirst(
      !a.cooldownExpired,
      !b.cooldownExpired,
    );
    if (cooldownCompare != 0) return cooldownCompare;

    final shownCompare = _compareLastShownOldestFirst(
      a.lastShownAt,
      b.lastShownAt,
    );
    if (shownCompare != 0) return shownCompare;

    final distanceCompare = a.anniversaryWindow.distanceDays.compareTo(
      b.anniversaryWindow.distanceDays,
    );
    if (distanceCompare != 0) return distanceCompare;

    return b.trip.averageCreationTime().compareTo(a.trip.averageCreationTime());
  }

  static Future<(List<TripMemory>, List<BaseLocation>)> _surfaceAll(
    List<TripMemory> memoryResults,
    List<BaseLocation> baseLocations,
    List<TripMemory> validTrips,
    Map<int, EnteFile> allFileIdsToFile,
    Set<String> baseCountriesToExclude,
    int nowInMicroseconds,
    int windowEnd, {
    required Map<int, int> seenTimes,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required CitySearchIndex citySearchIndex,
  }) async {
    for (final baseLocation in baseLocations) {
      String name = "Base (${baseLocation.isCurrentBase ? 'current' : 'old'})";
      final files = baseLocation.fileIDs
          .map((fileID) => allFileIdsToFile[fileID]!)
          .toList();
      final String? locationName = SmartMemoriesService._tryFindLocationName(
        Memory.fromFiles(files, seenTimes),
        citySearchIndex,
        base: true,
      );
      if (locationName != null) {
        name =
            "$locationName (Base, ${baseLocation.isCurrentBase ? 'current' : 'old'})";
      }
      memoryResults.add(
        TripMemory(
          Memory.fromFiles(files, seenTimes),
          nowInMicroseconds,
          windowEnd,
          baseLocation.location,
          locationName: name,
        ),
      );
    }
    for (final trip in validTrips) {
      final year = DateTime.fromMicrosecondsSinceEpoch(
        trip.averageCreationTime(),
      ).year;
      final String? locationName = SmartMemoriesService._tryFindLocationName(
        trip.memories,
        citySearchIndex,
        excludedCountryNames: baseCountriesToExclude,
      );
      final photoSelection = await SmartMemoriesService._bestSelection(
        List<Memory>.of(trip.memories),
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
      );
      memoryResults.add(
        trip.copyWith(
          memories: photoSelection,
          tripYear: year,
          locationName: locationName,
          firstDateToShow: nowInMicroseconds,
          lastDateToShow: windowEnd,
        ),
      );
    }
    return (memoryResults, baseLocations);
  }

  static Future<(List<TripMemory>, List<BaseLocation>)> _surfaceScheduled(
    List<TripMemory> memoryResults,
    List<BaseLocation> baseLocations,
    List<TripMemory> validTrips,
    DateTime currentTime,
    int nowInMicroseconds,
    List<TripsShownLog> shownTrips, {
    required Set<String> baseCountriesToExclude,
    required Iterable<ToShowMemory> cachedTripMemories,
    required bool isLocalGalleryMode,
    required bool mlEnabled,
    required Map<int, int> seenTimes,
    required Map<int, List<FaceWithoutEmbedding>> fileIdToFaces,
    required Map<String, String> faceIDsToPersonID,
    required Map<int, EmbeddingVector> fileIDToImageEmbedding,
    required Vector clipPositiveTextVector,
    required CitySearchIndex citySearchIndex,
  }) async {
    final activeTripIdentityKeys = _activeCachedTripIdentityKeys(
      cachedTripMemories,
      currentTime,
    );
    final remainingSlots = max(
      0,
      kTripSurfaceSlots - activeTripIdentityKeys.length,
    );
    if (remainingSlots == 0 || validTrips.isEmpty) {
      return (memoryResults, baseLocations);
    }

    final excludedIdentityKeys = activeTripIdentityKeys.toSet();
    final candidates = <_TripSurfaceCandidate>[];
    for (final trip in validTrips) {
      final identityKey = _tripIdentityKey(trip);
      if (excludedIdentityKeys.contains(identityKey)) {
        continue;
      }
      final lastShownAt = _lastShownAtForTrip(trip, shownTrips);
      final cooldownExpired =
          lastShownAt == null ||
          currentTime.difference(lastShownAt) >= kTripShowTimeout;
      candidates.add(
        _TripSurfaceCandidate(
          trip: trip,
          identityKey: identityKey,
          anniversaryWindow: _nearestAnniversaryWindow(trip, currentTime),
          lastShownAt: lastShownAt,
          cooldownExpired: cooldownExpired,
        ),
      );
    }

    final selectedCandidates = <_TripSurfaceCandidate>[];
    final selectedKeys = <String>{...excludedIdentityKeys};

    final seasonalCandidates =
        candidates
            .where(
              (candidate) =>
                  candidate.cooldownExpired &&
                  candidate.anniversaryWindow.distanceDays <=
                      _seasonalTripBandDays,
            )
            .where((candidate) => !selectedKeys.contains(candidate.identityKey))
            .toList()
          ..sort(_compareSeasonalCandidates);
    for (final seasonalCandidate in seasonalCandidates) {
      if (selectedCandidates.length >= remainingSlots) break;
      selectedCandidates.add(seasonalCandidate);
      selectedKeys.add(seasonalCandidate.identityKey);
    }

    final evergreenCandidates =
        candidates
            .where(
              (candidate) =>
                  candidate.cooldownExpired &&
                  !selectedKeys.contains(candidate.identityKey),
            )
            .toList()
          ..sort(_compareEvergreenCandidates);
    for (final candidate in evergreenCandidates) {
      if (selectedCandidates.length >= remainingSlots) {
        break;
      }
      selectedCandidates.add(candidate);
      selectedKeys.add(candidate.identityKey);
    }

    final currentShownCount =
        activeTripIdentityKeys.length + selectedCandidates.length;
    if (isLocalGalleryMode && currentShownCount == 0 && candidates.isNotEmpty) {
      final fallbackSeasonalCandidates =
          candidates
              .where(
                (candidate) =>
                    candidate.anniversaryWindow.distanceDays <=
                        _seasonalTripBandDays &&
                    !selectedKeys.contains(candidate.identityKey),
              )
              .toList()
            ..sort(_compareSeasonalCandidates);
      final fallbackCandidates = fallbackSeasonalCandidates.isNotEmpty
          ? fallbackSeasonalCandidates
          : (candidates..sort(_compareEvergreenCandidates))
                .where(
                  (candidate) => !selectedKeys.contains(candidate.identityKey),
                )
                .toList();
      if (fallbackCandidates.isNotEmpty) {
        selectedCandidates.add(fallbackCandidates.first);
      }
    }

    final lastDateToShow = currentTime
        .add(_tripDisplayDuration)
        .microsecondsSinceEpoch;
    for (final candidate in selectedCandidates) {
      final trip = candidate.trip;
      final year = DateTime.fromMicrosecondsSinceEpoch(
        trip.averageCreationTime(),
      ).year;
      final String? locationName = SmartMemoriesService._tryFindLocationName(
        trip.memories,
        citySearchIndex,
        excludedCountryNames: baseCountriesToExclude,
      );
      final photoSelection = await SmartMemoriesService._bestSelection(
        List<Memory>.of(trip.memories),
        isLocalGalleryMode: isLocalGalleryMode,
        mlEnabled: mlEnabled,
        fileIdToFaces: fileIdToFaces,
        faceIDsToPersonID: faceIDsToPersonID,
        fileIDToImageEmbedding: fileIDToImageEmbedding,
        clipPositiveTextVector: clipPositiveTextVector,
      );
      memoryResults.add(
        trip.copyWith(
          memories: photoSelection,
          tripYear: year,
          locationName: locationName,
          firstDateToShow: nowInMicroseconds,
          lastDateToShow: lastDateToShow,
        ),
      );
    }
    return (memoryResults, baseLocations);
  }

  static Set<String> _baseCountriesToExcludeFromTripTitles(
    List<BaseLocation> baseLocations,
    Map<int, EnteFile> allFileIdsToFile,
    CitySearchIndex citySearchIndex,
    Map<int, int> seenTimes,
  ) {
    final excludedCountries = <String>{};
    for (final baseLocation in baseLocations) {
      final files = baseLocation.fileIDs
          .map((fileID) => allFileIdsToFile[fileID])
          .whereType<EnteFile>()
          .toList();
      if (files.isEmpty) {
        continue;
      }

      final countryName = SmartMemoriesService._tryFindCountryName(
        Memory.fromFiles(files, seenTimes),
        citySearchIndex,
      );
      if (countryName == null) {
        continue;
      }

      final normalizedCountry = SmartMemoriesService._normalizePlaceName(
        countryName,
      );
      if (normalizedCountry.isNotEmpty) {
        excludedCountries.add(normalizedCountry);
      }
    }
    return excludedCountries;
  }
}
