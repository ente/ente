import "dart:math" show Random;

import "package:collection/collection.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/models/base_location.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/on_this_day_memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/memories/trip_memory.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/memories/memories_computer.dart";
import "package:photos/services/memories/memory_sources.dart";
import "package:photos/src/rust/api/memories_api.dart" as rust;

class RustMemoriesComputer implements MemoriesComputer {
  final _logger = Logger("RustMemoriesComputer");

  static const _minimumClipIndexedFiles = 5;

  RustMLDataDB get _mlDataDB => isLocalGalleryMode
      ? RustMLDataDB.localGalleryInstance
      : RustMLDataDB.instance;

  @override
  Future<bool> isMlReady() async {
    if (!hasGrantedMLConsent || !localSettings.isMLLocalIndexingEnabled) {
      return false;
    }
    try {
      return await _mlDataDB.getClipIndexedFileCount() >=
          _minimumClipIndexedFiles;
    } catch (e, s) {
      _logger.warning("Failed to determine ML readiness", e, s);
      return false;
    }
  }

  @override
  Future<MemoriesResult> computeAll(
    DateTime now,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  }) async {
    final results = await _compute(
      [now],
      oldCache,
      mlEnabled: mlEnabled,
      surfaceAll: true,
    );
    return results?.single ?? MemoriesResult.failed();
  }

  @override
  Future<({MemoriesResult current, MemoriesResult next})> computeCurrentAndNext(
    DateTime current,
    DateTime next,
    MemoriesCache oldCache, {
    required bool mlEnabled,
  }) async {
    final results = await _compute(
      [current, next],
      oldCache,
      mlEnabled: mlEnabled,
      surfaceAll: false,
    );
    if (results == null) {
      return (current: MemoriesResult.failed(), next: MemoriesResult.failed());
    }
    return (current: results[0], next: results[1]);
  }

  @override
  Future<List<SmartMemory>> computeSimple() async {
    final inputs = await _loadInputs(mlEnabled: false, surfaceAll: false);
    _logger.info(
      "Computing simple memories over ${inputs.files.length} files (seed: "
      "${inputs.request.seed})",
    );
    final memories = await rust.computeSimpleMemories(
      request: inputs.request,
      period: _period(DateTime.now()),
    );
    return memories.map(inputs.smartMemory).toList();
  }

  Future<List<SmartMemory>> computeAllTrips(
    DateTime now, {
    required bool improved,
  }) async {
    final inputs = await _loadInputs(mlEnabled: false, surfaceAll: true);
    final detection = improved
        ? rust.TripDetection.improved
        : rust.TripDetection.legacy;
    _logger.info(
      "Computing all ${detection.name} trip memories over "
      "${inputs.files.length} files",
    );
    final memories = await rust.computeAllTripMemories(
      request: inputs.request,
      period: _period(now),
      cities: await locationService.getLocationIndex(),
      detection: detection,
    );
    return memories
        .map((memory) => inputs.smartMemory(memory, capMemories: false))
        .toList();
  }

  Future<List<MemoriesResult>?> _compute(
    List<DateTime> periods,
    MemoriesCache oldCache, {
    required bool mlEnabled,
    required bool surfaceAll,
  }) async {
    final inputs = await _loadInputs(
      oldCache: oldCache,
      mlEnabled: mlEnabled,
      surfaceAll: surfaceAll,
    );
    _logger.info(
      "Computing memories for ${periods.join(", ")} over "
      "${inputs.files.length} files (mlEnabled: $mlEnabled, seed: "
      "${inputs.request.seed})",
    );
    final rust.SmartMemories result;
    try {
      result = await rust.computeSmartMemories(
        request: inputs.request,
        periods: periods.map(_period).toList(),
        store: mlEnabled ? await _mlDataDB.store : null,
        cities: await locationService.getLocationIndex(),
      );
    } catch (e, s) {
      _logger.severe("Rust memories computation failed", e, s);
      return null;
    }
    final baseLocations = result.baseLocations.map(_baseLocation).toList();
    return [
      for (final memories in result.periods)
        MemoriesResult(
          memories.map(inputs.smartMemory).toList(),
          baseLocations,
        ),
    ];
  }

  Future<_Inputs> _loadInputs({
    MemoriesCache? oldCache,
    required bool mlEnabled,
    required bool surfaceAll,
  }) async {
    final files = await getFilesAndMapForMemories(
      useLocalIntIds: isLocalGalleryMode,
      requireLocalId: isLocalGalleryMode,
    );
    final collectionIDsToExclude = await getCollectionIDsToExclude();
    final seenTimes = await memoriesDB.getSeenTimes();
    final allPersons = (!mlEnabled || isLocalGalleryMode)
        ? const <PersonEntity>[]
        : await PersonService.instance.getPersons();
    final persons = allPersons
        .where((person) => !person.data.hideFromMemories)
        .toList();
    final currentUserEmail = isLocalGalleryMode
        ? null
        : Configuration.instance.getEmail();
    final me = currentUserEmail == null
        ? null
        : persons.firstWhereOrNull(
            (person) => person.data.email == currentUserEmail,
          );
    final currentUserID = isLocalGalleryMode
        ? null
        : Configuration.instance.getUserID();
    final request = rust.MemoriesRequest(
      files: [
        for (final entry in files.entries)
          _memoryFile(entry.key, entry.value, currentUserID),
      ],
      excludedCollectionIds: Int64List.fromList(
        collectionIDsToExclude.toList(),
      ),
      people: persons.map(_memoryPerson).toList(),
      peopleHiddenFromMemories: [
        for (final person in allPersons)
          if (person.data.hideFromMemories) person.remoteID,
      ],
      mePersonId: me?.remoteID,
      showsUnnamedPeople: mlEnabled && localSettings.showLocalGalleryModeOption,
      shownPeople: [
        for (final log in oldCache?.peopleShownLogs ?? <PeopleShownLog>[])
          rust.ShownPerson(
            personId: log.personID,
            memoryType: rust.PeopleMemoryType.values.byName(
              log.peopleMemoryType.name,
            ),
            lastTimeShown: log.lastTimeShown,
          ),
      ],
      shownTrips: [
        for (final log in oldCache?.tripsShownLogs ?? <TripsShownLog>[])
          rust.ShownTrip(
            key: log.tripKey,
            location: _coordinate(log.location),
            lastTimeShown: log.lastTimeShown,
          ),
      ],
      cachedTrips: [
        for (final memory in oldCache?.toShowMemories ?? <ToShowMemory>[])
          if (memory.type == MemoryType.trips)
            rust.CachedTrip(
              identityKey: memory.tripIdentityKey,
              firstDateToShow: memory.firstTimeToShow,
              lastDateToShow: memory.lastTimeToShow,
            ),
      ],
      shownClipMemories: [
        for (final log in oldCache?.clipShownLogs ?? <ClipShownLog>[])
          rust.ShownClipMemory(
            kind: rust.ClipMemoryType.values.byName(log.clipMemoryType.name),
            lastTimeShown: log.lastTimeShown,
          ),
      ],
      surfaceAll: surfaceAll,
      localGalleryMode: isLocalGalleryMode,
      seed: _seed(),
    );
    return _Inputs(
      request: request,
      files: files,
      seenTimes: seenTimes,
      persons: {for (final person in persons) person.remoteID: person},
    );
  }

  static rust.MemoryFile _memoryFile(
    int id,
    EnteFile file,
    int? currentUserID,
  ) {
    final creationTime = file.creationTime!;
    return rust.MemoryFile(
      id: id,
      creationTime: creationTime,
      localDateTime: file.pubMagicMetadata?.dateTime,
      utcOffsetSeconds: DateTime.fromMicrosecondsSinceEpoch(
        creationTime,
      ).timeZoneOffset.inSeconds,
      collectionId: file.collectionID,
      location: file.hasLocation ? _coordinate(file.location!) : null,
      shared:
          currentUserID != null &&
          file.ownerID != null &&
          file.ownerID != currentUserID,
    );
  }

  static rust.MemoryPerson _memoryPerson(PersonEntity person) {
    final birthDate = DateTime.tryParse(person.data.birthDate ?? "");
    return rust.MemoryPerson(
      id: person.remoteID,
      isIgnored: person.data.isIgnored,
      birthDate: birthDate == null
          ? null
          : rust.LocalDate(
              year: birthDate.year,
              month: birthDate.month,
              day: birthDate.day,
            ),
    );
  }

  static rust.Period _period(DateTime time) => rust.Period(
    now: time.microsecondsSinceEpoch,
    utcOffsetSeconds: time.timeZoneOffset.inSeconds,
  );

  static rust.Coordinate _coordinate(Location location) => rust.Coordinate(
    latitude: location.latitude!,
    longitude: location.longitude!,
  );

  static BigInt _seed() {
    final random = Random.secure();
    return (BigInt.from(random.nextInt(1 << 32)) << 32) |
        BigInt.from(random.nextInt(1 << 32));
  }

  static BaseLocation _baseLocation(rust.BaseLocation base) => BaseLocation(
    base.fileIds.inner.toList(),
    _location(base.location),
    base.isCurrent,
  );

  static Location _location(rust.Coordinate coordinate) =>
      Location(latitude: coordinate.latitude, longitude: coordinate.longitude);
}

class _Inputs {
  final rust.MemoriesRequest request;
  final Map<int, EnteFile> files;
  final Map<int, int> seenTimes;
  final Map<String, PersonEntity> persons;

  _Inputs({
    required this.request,
    required this.files,
    required this.seenTimes,
    required this.persons,
  });

  SmartMemory smartMemory(rust.Memory memory, {bool capMemories = true}) {
    final memories = [
      for (final fileID in memory.fileIds.inner)
        if (files[fileID] case final file?) Memory.fromFile(file, seenTimes),
    ];
    final first = _resolveBoundary(memory.firstDateToShow);
    final last = _resolveBoundary(memory.lastDateToShow);
    return switch (memory.kind) {
      rust.MemoryKind_OnThisDay() => OnThisDayMemory(memories, first, last),
      rust.MemoryKind_People(field0: final people) => _peopleMemory(
        memories,
        first,
        last,
        people,
      ),
      rust.MemoryKind_Trip(field0: final trip) => TripMemory(
        memories,
        first,
        last,
        RustMemoriesComputer._location(trip.location),
        locationName: trip.locationName,
        tripYear: trip.year,
        tripKey: trip.key,
        capMemories: capMemories,
      ),
      rust.MemoryKind_Base(field0: final base) => TripMemory(
        memories,
        first,
        last,
        RustMemoriesComputer._location(base.location),
        locationName: _baseName(base),
        capMemories: capMemories,
      ),
      rust.MemoryKind_Clip(field0: final clipType) => ClipMemory(
        memories,
        first,
        last,
        ClipMemoryType.values.byName(clipType.name),
      ),
      rust.MemoryKind_Time(field0: final time) => _timeMemory(
        memories,
        first,
        last,
        time,
      ),
      rust.MemoryKind_Filler(:final yearsAgo) => FillerMemory(
        memories,
        yearsAgo,
        first,
        last,
      ),
    };
  }

  static int _resolveBoundary(rust.MemoryBoundary boundary) =>
      switch (boundary) {
        rust.MemoryBoundary_Timestamp(field0: final timestamp) => timestamp,
        rust.MemoryBoundary_CalendarDate(field0: final date) => DateTime(
          date.year,
          date.month,
          date.day,
        ).microsecondsSinceEpoch,
      };

  PeopleMemory _peopleMemory(
    List<Memory> memories,
    int first,
    int last,
    rust.PeopleMemory people,
  ) {
    final memoryType = PeopleMemoryType.values.byName(people.memoryType.name);
    final isMySpotlight =
        people.personId == request.mePersonId &&
        memoryType == PeopleMemoryType.spotlight;
    final activity = people.activity;
    final birthday = people.birthday;
    return PeopleMemory(
      memories,
      first,
      last,
      memoryType,
      people.personId,
      people.isUnnamedCluster || isMySpotlight
          ? null
          : persons[people.personId]?.data.name,
      activity: activity == null
          ? null
          : PeopleActivity.values.byName(activity.name),
      isUnnamedCluster: people.isUnnamedCluster,
      isBirthday: birthday == null ? null : !birthday.isUpcoming,
      newAge: birthday?.newAge,
    );
  }

  static TimeMemory _timeMemory(
    List<Memory> memories,
    int first,
    int last,
    rust.TimeMemory time,
  ) => switch (time) {
    rust.TimeMemory_Day(:final date, :final yearsAgo) => TimeMemory(
      memories,
      first,
      last,
      day: DateTime(date.year, date.month, date.day),
      yearsAgo: yearsAgo,
    ),
    rust.TimeMemory_Week(:final yearsAgo) => TimeMemory(
      memories,
      first,
      last,
      yearsAgo: yearsAgo,
    ),
    rust.TimeMemory_Month(:final year, :final month, :final yearsAgo) =>
      TimeMemory(
        memories,
        first,
        last,
        month: DateTime(year, month),
        yearsAgo: yearsAgo,
      ),
    rust.TimeMemory_LastWeek() => TimeMemory(
      memories,
      first,
      last,
      kind: TimeMemoryKind.lastWeek,
    ),
    rust.TimeMemory_LastMonth() => TimeMemory(
      memories,
      first,
      last,
      kind: TimeMemoryKind.lastMonth,
    ),
  };

  static String _baseName(rust.BaseMemory base) {
    final status = base.isCurrent ? "current" : "old";
    final locationName = base.locationName;
    return locationName == null
        ? "Base ($status)"
        : "$locationName (Base, $status)";
  }
}
