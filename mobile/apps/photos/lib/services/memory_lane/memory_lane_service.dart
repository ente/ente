import "dart:async";

import "package:collection/collection.dart";
import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/ml_consent_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/memory_lane/memory_lane_cache_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

@visibleForTesting
int? eligibleCreationTimeCutoffMicros(String? birthDateString) {
  if (birthDateString == null || birthDateString.isEmpty) {
    return null;
  }
  final birthDate = DateTime.tryParse(birthDateString);
  if (birthDate == null) {
    return null;
  }
  final year = birthDate.year + 3;
  final lastDay = DateTime(year, birthDate.month + 1, 0).day;
  return DateTime(
    year,
    birthDate.month,
    birthDate.day.clamp(1, lastDay),
  ).microsecondsSinceEpoch;
}

class MemoryLaneService {
  MemoryLaneService._internal() {
    __isFeatureEnabled = hasGrantedMLConsent;
  }

  static final MemoryLaneService instance = MemoryLaneService._internal();

  static const _minimumYears = 2;
  static const _minimumFacesPerYear = 4;
  static const _recomputeCooldown = Duration(hours: 2);
  static const _timelineLogicVersion = 3;
  static const _startupBackfillDelay = Duration(seconds: 15);
  static const _startupBackfillBatchSize = 200;

  final Logger _logger = Logger("MemoryLaneService");
  final MemoryLaneCacheService _cacheService = MemoryLaneCacheService.instance;
  final MLDataDB _mlDataDB = MLDataDB.instance;
  final FilesDB _filesDB = FilesDB.instance;
  final TaskQueue<String> _precomputeQueue = TaskQueue(
    maxConcurrentTasks: 1,
    taskTimeout: const Duration(minutes: 5),
    maxQueueSize: 1000,
  );
  final TaskQueue<String> _cropReadinessQueue = TaskQueue(
    maxConcurrentTasks: 1,
    taskTimeout: const Duration(minutes: 5),
    maxQueueSize: 1000,
  );

  final ValueNotifier<Set<String>> readyPersonIds = ValueNotifier<Set<String>>(
    {},
  );

  final Map<String, int> _lastForcedComputeMicros = {};
  final Map<String, bool> _pendingRequests = {};
  final Set<String> _cropReadinessInFlight = {};

  bool __isFeatureEnabled = false;
  // TODO: this should be removed, but flagService does not fire MLConsentChangedEvent on remote flags sync
  bool get isFeatureEnabled =>
      hasGrantedMLConsent && __isFeatureEnabled && flagService.facesTimeline;
  bool _initialized = false;

  Timer? _startupBackfillTimer;

  Future<void> init() async {
    if (_initialized) {
      return;
    }
    try {
      await _cacheService.init();
      await _cacheService.ensureComputeLogVersion(_timelineLogicVersion);
      await _refreshReadyPersonIds();
      Bus.instance.on<PeopleChangedEvent>().listen(_handlePeopleChange);
      Bus.instance.on<MLConsentChangedEvent>().listen(_handleMlConsentChange);
      _scheduleStartupBackfill();
      _initialized = true;
      await _queueFullRecompute();
    } catch (e, s) {
      _logger.severe("Initialization failed", e, s);
    }
  }

  void _handleMlConsentChange(MLConsentChangedEvent event) {
    if (event.enabled) {
      return;
    }
    __isFeatureEnabled = false;
    _startupBackfillTimer?.cancel();
    _startupBackfillTimer = null;
  }

  Future<void> _queueFullRecompute({bool force = false}) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning("Full recompute skipped: PersonService unavailable");
      return;
    }
    final persons = await PersonService.instance.getPersons();
    for (final person in persons) {
      if (person.data.isIgnored) {
        await _handleIgnoredPerson(person.remoteID);
        continue;
      }
      schedulePersonRecompute(person.remoteID, force: force);
    }
  }

  void schedulePersonRecompute(String personId, {bool force = false}) {
    if (personId.isEmpty) {
      return;
    }
    _pendingRequests[personId] = (_pendingRequests[personId] ?? false) || force;
    _precomputeQueue
        .addTask(personId, () async {
          final requestForce = _pendingRequests.remove(personId) ?? force;
          await _recomputeTimelineForPerson(personId, force: requestForce);
        })
        .catchError((e, s) {
          _pendingRequests.remove(personId);
          _logger.severe("Recompute failed for $personId", e, s);
        });
  }

  Future<void> ensureTimelineReachability(String personId) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (personId.isEmpty) {
      return;
    }
    final timeline = await _cacheService.getTimeline(personId);
    if (timeline == null || !timeline.isEligible || timeline.entries.isEmpty) {
      await _refreshReadyPersonIds();
      schedulePersonRecompute(personId);
      return;
    }
    if (await _areTimelineFaceCropsCached(timeline)) {
      await _refreshReadyPersonIds();
      return;
    }
    await _refreshReadyPersonIds();
    _queueTimelineCropReadiness(personId);
  }

  Future<MemoryLanePersonTimeline?> getTimeline(String personId) async {
    if (!isFeatureEnabled) {
      return null;
    }
    final timeline = await _cacheService.getTimeline(personId);
    if (timeline == null || timeline.entries.isEmpty) {
      return timeline;
    }

    final hiddenFiles = await SearchService.instance.getHiddenFiles();
    final hiddenFileIds = hiddenFiles
        .map((e) => e.uploadedFileID)
        .whereType<int>()
        .toSet();
    final containsHiddenEntry = timeline.entries.any(
      (entry) => hiddenFileIds.contains(entry.fileId),
    );
    if (!containsHiddenEntry) {
      if (timeline.isEligible && !await _areTimelineFaceCropsCached(timeline)) {
        _logger.info("Missing face crops for $personId");
        _queueTimelineCropReadiness(personId);
        await _refreshReadyPersonIds();
        return null;
      }
      return timeline;
    }

    _logger.info("Removing timeline with hidden files for $personId");
    await _cacheService.removeTimeline(personId);
    await _refreshReadyPersonIds();
    schedulePersonRecompute(personId, force: true);
    return null;
  }

  bool hasReadyTimelineSync(String personId) {
    if (!isFeatureEnabled) {
      return false;
    }
    return readyPersonIds.value.contains(personId);
  }

  Future<bool> _areTimelineFaceCropsCached(
    MemoryLanePersonTimeline timeline,
  ) async {
    if (!timeline.isEligible || timeline.entries.isEmpty) {
      return false;
    }
    return areFullFaceCropsCached(
      timeline.entries.map((entry) => entry.faceId),
      useTempCache: false,
    );
  }

  void _queueTimelineCropReadiness(String personId) {
    if (_cropReadinessInFlight.contains(personId)) {
      return;
    }
    _cropReadinessInFlight.add(personId);
    _cropReadinessQueue
        .addTask(personId, () async {
          try {
            await _repairTimelineCropReadiness(personId);
          } finally {
            _cropReadinessInFlight.remove(personId);
          }
        })
        .catchError((e, s) {
          _cropReadinessInFlight.remove(personId);
          _logger.warning("Crop repair task failed for $personId", e, s);
        });
  }

  Future<void> _repairTimelineCropReadiness(String personId) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Crop repair skipped for $personId: PersonService unavailable",
      );
      return;
    }
    final timeline = await _cacheService.getTimeline(personId);
    if (timeline == null || !timeline.isEligible || timeline.entries.isEmpty) {
      await _refreshReadyPersonIds();
      return;
    }
    if (await _areTimelineFaceCropsCached(timeline)) {
      await _refreshReadyPersonIds();
      return;
    }
    final person = await PersonService.instance.getPerson(personId);
    if (person == null) {
      await _cacheService.removeTimeline(personId);
      await _refreshReadyPersonIds();
      return;
    }
    if (person.data.isIgnored) {
      await _handleIgnoredPerson(personId);
      return;
    }

    final fileIds = timeline.entries.map((entry) => entry.fileId).toSet();
    final filesById = await _filesDB.getFileIDToFileFromIDs(fileIds.toList());
    final cropsReady = await _ensureFaceCrops(
      personId,
      timeline.entries,
      filesById,
    );
    await _refreshReadyPersonIds();
    if (!cropsReady) {
      _logger.warning("Crop repair failed for $personId");
    }
  }

  Future<void> _handleIgnoredPerson(String personId) async {
    _pendingRequests.remove(personId);
    await _cacheService.removeTimeline(personId);
    await _refreshReadyPersonIds();
  }

  void _handlePeopleChange(PeopleChangedEvent event) {
    if (!isFeatureEnabled) {
      return;
    }
    if (event.type == PeopleEventType.syncDone) {
      return;
    }
    unawaited(_processPeopleChange(event));
  }

  Future<void> _processPeopleChange(PeopleChangedEvent event) async {
    final person = event.person;
    if (person == null) {
      _logger.warning("${event.type.name} event missing person");
      _scheduleStartupBackfill();
      return;
    }
    if (person.data.isIgnored) {
      await _handleIgnoredPerson(person.remoteID);
      return;
    }
    final logEntry = await _cacheService.getComputeLogEntry(person.remoteID);
    if (logEntry == null) {
      schedulePersonRecompute(person.remoteID, force: true);
      return;
    }
    final Set<String> faceIds = await _mlDataDB.getFaceIDsForPerson(
      person.remoteID,
    );
    final currentFaceCount = faceIds.length;
    final bool nameChanged = (logEntry.name ?? "") != person.data.name;
    final bool birthDateChanged =
        (logEntry.birthDate ?? "") != (person.data.birthDate ?? "");
    final bool faceCountChanged = logEntry.faceCount != currentFaceCount;

    if (!nameChanged && !birthDateChanged && !faceCountChanged) {
      return;
    }

    final timeline = await _cacheService.getTimeline(person.remoteID);
    final Set<String> currentFaceIdSet = faceIds;

    if (_timelineFacesMissing(timeline, currentFaceIdSet)) {
      schedulePersonRecompute(person.remoteID);
      return;
    }

    if (birthDateChanged) {
      schedulePersonRecompute(person.remoteID);
      return;
    }

    if (!faceCountChanged) {
      return;
    }

    final facesPerYear = await _countEligibleFacesByYear(
      faceIds,
      eligibleCreationTimeCutoffMicros(person.data.birthDate),
    );
    if (_hasNewYearWithTenFaces(timeline, facesPerYear)) {
      schedulePersonRecompute(person.remoteID);
      return;
    }
  }

  void _scheduleStartupBackfill() {
    _startupBackfillTimer?.cancel();
    _startupBackfillTimer = Timer(_startupBackfillDelay, () {
      unawaited(_runStartupBackfill());
    });
  }

  Future<void> _runStartupBackfill() async {
    if (!isFeatureEnabled) {
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning("Startup backfill skipped: PersonService unavailable");
      return;
    }
    try {
      final persons = await PersonService.instance.getPersons();
      final computeLog = await _cacheService.getComputeLog();
      final alreadyComputed = computeLog.values
          .where((entry) => entry.logicVersion == _timelineLogicVersion)
          .map((entry) => entry.personId)
          .toSet();
      final missingIds = <String>[];
      for (final person in persons) {
        if (person.data.isIgnored) {
          continue;
        }
        if (alreadyComputed.contains(person.remoteID)) {
          continue;
        }
        missingIds.add(person.remoteID);
        if (missingIds.length >= _startupBackfillBatchSize) {
          break;
        }
      }
      if (missingIds.isEmpty) {
        return;
      }
      for (final personId in missingIds) {
        schedulePersonRecompute(personId, force: true);
      }
    } catch (e, s) {
      _logger.severe("Startup backfill failed", e, s);
    }
  }

  Future<Map<int, int>> _countEligibleFacesByYear(
    Iterable<String> faceIds,
    int? minCreationTimeMicros,
  ) async {
    if (faceIds.isEmpty) {
      return {};
    }
    final uniqueFileIds = faceIds
        .map(getFileIdFromFaceId<int>)
        .toSet()
        .toList();
    final fileMap = await _filesDB.getFileIDToFileFromIDs(uniqueFileIds);
    final hiddenFiles = await SearchService.instance.getHiddenFiles();
    final hiddenFileIds = hiddenFiles
        .map((e) => e.uploadedFileID)
        .whereType<int>()
        .toSet();
    final counts = <int, int>{};
    for (final faceId in faceIds) {
      final fileId = getFileIdFromFaceId<int>(faceId);
      if (hiddenFileIds.contains(fileId)) {
        continue;
      }
      final file = fileMap[fileId];
      final creationTime = file?.creationTime;
      if (creationTime == null || creationTime <= 0) {
        continue;
      }
      if (minCreationTimeMicros != null &&
          creationTime < minCreationTimeMicros) {
        continue;
      }
      final year = DateTime.fromMicrosecondsSinceEpoch(creationTime).year;
      counts[year] = (counts[year] ?? 0) + 1;
    }
    return counts;
  }

  bool _timelineFacesMissing(
    MemoryLanePersonTimeline? timeline,
    Set<String> currentFaceIds,
  ) {
    if (timeline == null || timeline.entries.isEmpty) {
      return false;
    }
    for (final entry in timeline.entries) {
      if (!currentFaceIds.contains(entry.faceId)) {
        return true;
      }
    }
    return false;
  }

  bool _hasNewYearWithTenFaces(
    MemoryLanePersonTimeline? timeline,
    Map<int, int> facesPerYear,
  ) {
    if (facesPerYear.isEmpty) {
      return false;
    }
    final timelineYears =
        timeline?.entries.map((entry) => entry.year).toSet() ?? {};
    for (final entry in facesPerYear.entries) {
      if (!timelineYears.contains(entry.key) && entry.value >= 10) {
        return true;
      }
    }
    return false;
  }

  Future<void> _recomputeTimelineForPerson(
    String personId, {
    required bool force,
  }) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Recompute skipped for $personId: PersonService unavailable",
      );
      return;
    }

    final person = await PersonService.instance.getPerson(personId);
    if (person == null) {
      await _cacheService.removeTimeline(personId);
      await _refreshReadyPersonIds();
      return;
    }
    if (person.data.isIgnored) {
      await _handleIgnoredPerson(personId);
      return;
    }

    final nowMicros = DateTime.now().microsecondsSinceEpoch;
    final existing = await _cacheService.getTimeline(personId);
    final lastComputedMicros = existing?.updatedAtMicros;
    final lastForcedMicros = _lastForcedComputeMicros[personId];
    if (!force && lastComputedMicros != null) {
      final remaining = nowMicros - lastComputedMicros;
      if (remaining < _recomputeCooldown.inMicroseconds) {
        return;
      }
    }
    if (!force && lastForcedMicros != null) {
      final remaining = nowMicros - lastForcedMicros;
      if (remaining < _recomputeCooldown.inMicroseconds) {
        return;
      }
    }

    if (force) {
      _lastForcedComputeMicros[personId] = nowMicros;
    }

    final faceIds = await _mlDataDB.getFaceIDsForPerson(personId);
    final (timeline, filesById) = await _computeTimeline(
      faceIds,
      personId,
      nowMicros,
      eligibleCreationTimeCutoffMicros(person.data.birthDate),
    );
    await _cacheService.upsertTimeline(timeline);
    await _cacheService.upsertComputeLogEntry(
      MemoryLaneComputeLogEntry(
        personId: personId,
        name: person.data.name,
        birthDate: person.data.birthDate,
        faceCount: faceIds.length,
        lastComputedMicros: nowMicros,
        logicVersion: _timelineLogicVersion,
      ),
    );
    if (!timeline.isEligible) {
      await _refreshReadyPersonIds();
      return;
    }
    final cropsReady = await _ensureFaceCrops(
      personId,
      timeline.entries,
      filesById,
    );
    await _refreshReadyPersonIds();
    if (!cropsReady) {
      _logger.warning("Crop repair failed for $personId");
      _queueTimelineCropReadiness(personId);
    }
  }

  Future<(MemoryLanePersonTimeline, Map<int, EnteFile>)> _computeTimeline(
    Set<String> faceIds,
    String personId,
    int nowMicros,
    int? minCreationTimeMicros,
  ) async {
    if (faceIds.isEmpty) {
      return (
        MemoryLanePersonTimeline(
          personId: personId,
          isEligible: false,
          updatedAtMicros: nowMicros,
          entries: const [],
        ),
        const <int, EnteFile>{},
      );
    }

    final List<int> uniqueFileIds = faceIds
        .map(getFileIdFromFaceId<int>)
        .toSet()
        .toList();
    final fileMap = await _filesDB.getFileIDToFileFromIDs(uniqueFileIds);
    final hiddenFiles = await SearchService.instance.getHiddenFiles();
    final hiddenFileIds = hiddenFiles
        .map((e) => e.uploadedFileID)
        .whereType<int>()
        .toSet();

    final faces = <_TimelineFaceData>[];
    final facesByFileId = <int, Map<String, Face>>{};
    for (final faceId in faceIds) {
      final fileId = getFileIdFromFaceId<int>(faceId);
      if (hiddenFileIds.contains(fileId)) {
        continue;
      }
      final file = fileMap[fileId];
      if (file == null) {
        continue;
      }
      final creationTime = file.creationTime;
      if (creationTime == null || creationTime <= 0) {
        continue;
      }
      Map<String, Face>? facesForFile = facesByFileId[fileId];
      if (facesForFile == null) {
        final fetchedFaces = await _mlDataDB.getFacesForGivenFileID(fileId);
        if (fetchedFaces == null) {
          facesForFile = {};
        } else {
          facesForFile = {for (final face in fetchedFaces) face.faceID: face};
        }
        facesByFileId[fileId] = facesForFile;
      }
      final faceDetails = facesForFile[faceId];
      final faceScore = faceDetails?.score ?? 0.0;
      final blurScore = faceDetails?.blur ?? 0.0;
      final date = DateTime.fromMicrosecondsSinceEpoch(creationTime);
      faces.add(
        _TimelineFaceData(
          faceId: faceId,
          fileId: fileId,
          creationTimeMicros: creationTime,
          year: date.year,
          score: faceScore,
          blur: blurScore,
        ),
      );
    }

    if (minCreationTimeMicros != null) {
      faces.removeWhere(
        (face) => face.creationTimeMicros < minCreationTimeMicros,
      );
    }

    if (faces.isEmpty) {
      return (
        MemoryLanePersonTimeline(
          personId: personId,
          isEligible: false,
          updatedAtMicros: nowMicros,
          entries: const [],
        ),
        fileMap,
      );
    }

    final selectionResult = await Computer.shared().compute(
      _selectTimelineEntriesTask,
      param: {
        "faces": faces.map((face) => face.toJson()).toList(),
        "minYears": _minimumYears,
        "minFaces": _minimumFacesPerYear,
        "minCreationTime": minCreationTimeMicros,
      },
      taskName: "faces_timeline_select",
    );

    if (!(selectionResult["isEligible"] as bool)) {
      return (
        MemoryLanePersonTimeline(
          personId: personId,
          isEligible: false,
          updatedAtMicros: nowMicros,
          entries: const [],
        ),
        fileMap,
      );
    }

    final entriesJson = (selectionResult["entries"] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final entries = entriesJson
        .map(
          (entryJson) => MemoryLaneEntry(
            faceId: entryJson["faceId"] as String,
            fileId: entryJson["fileId"] as int,
            creationTimeMicros: entryJson["creationTime"] as int,
            year: entryJson["year"] as int,
          ),
        )
        .toList();

    return (
      MemoryLanePersonTimeline(
        personId: personId,
        isEligible: true,
        updatedAtMicros: nowMicros,
        entries: entries,
      ),
      fileMap,
    );
  }

  Future<bool> _ensureFaceCrops(
    String personId,
    List<MemoryLaneEntry> entries,
    Map<int, EnteFile> fileMap,
  ) async {
    if (entries.isEmpty) {
      return false;
    }
    final byFile = groupBy(entries, (entry) => entry.fileId);
    var allCropsReady = true;
    for (final group in byFile.entries) {
      if (group.value.isEmpty) {
        continue;
      }
      final file = fileMap[group.key];
      if (file == null) {
        allCropsReady = false;
        _logger.warning("Missing file ${group.key} for $personId crops");
        continue;
      }
      final faces = await _mlDataDB.getFacesForGivenFileID(group.key) ?? [];
      if (faces.isEmpty) {
        allCropsReady = false;
        _logger.warning("No faces for $personId file ${group.key}");
        continue;
      }
      final selectedFaces = group.value
          .map(
            (entry) =>
                faces.firstWhereOrNull((face) => face.faceID == entry.faceId),
          )
          .whereType<Face>()
          .toList();
      if (selectedFaces.length != group.value.length) {
        allCropsReady = false;
        _logger.warning("Missing faces for $personId file ${group.key}");
        continue;
      }
      final cropMap = await getCachedFaceCrops(
        file,
        selectedFaces,
        useFullFile: true,
        useTempCache: false,
      );
      if (cropMap == null) {
        allCropsReady = false;
        continue;
      }
      if (selectedFaces.any((face) => (cropMap[face.faceID] ?? []).isEmpty)) {
        allCropsReady = false;
        _logger.warning("Missing crop for $personId file ${group.key}");
        continue;
      }
    }
    return allCropsReady;
  }

  Future<void> prewarmTimelineFrames(
    String personId, {
    int frameCount = 6,
  }) async {
    if (!isFeatureEnabled) {
      return;
    }
    try {
      final timeline = await _cacheService.getTimeline(personId);
      if (timeline == null ||
          !timeline.isEligible ||
          timeline.entries.isEmpty) {
        return;
      }
      final entries = timeline.entries.take(frameCount).toList();
      if (entries.isEmpty) {
        return;
      }
      final uniqueFileIds = entries
          .map((entry) => entry.fileId)
          .toSet()
          .toList();
      final filesById = await _filesDB.getFileIDToFileFromIDs(uniqueFileIds);
      final Map<int, Future<List<Face>?>> facesFutures = {};
      for (final entry in entries) {
        final file = filesById[entry.fileId];
        if (file == null) {
          continue;
        }
        final facesFuture = facesFutures.putIfAbsent(
          entry.fileId,
          () => _mlDataDB.getFacesForGivenFileID(entry.fileId),
        );
        final faces = await facesFuture;
        final face = faces?.firstWhereOrNull(
          (element) => element.faceID == entry.faceId,
        );
        if (face == null) {
          continue;
        }
        await getCachedFaceCrops(
          file,
          [face],
          useFullFile: true,
          useTempCache: false,
        );
      }
    } catch (e, s) {
      _logger.fine("Prewarm failed for $personId", e, s);
    }
  }

  Future<void> _refreshReadyPersonIds() async {
    final cache = await _cacheService.getCache();
    final current = <String>{};
    for (final timeline in cache.allTimelines) {
      if (!timeline.isEligible) {
        continue;
      }
      if (await _areTimelineFaceCropsCached(timeline)) {
        current.add(timeline.personId);
      }
    }
    readyPersonIds.value = current;
  }
}

class _TimelineFaceData {
  final String faceId;
  final int fileId;
  final int creationTimeMicros;
  final int year;
  final double score;
  final double blur;

  const _TimelineFaceData({
    required this.faceId,
    required this.fileId,
    required this.creationTimeMicros,
    required this.year,
    required this.score,
    required this.blur,
  });

  Map<String, dynamic> toJson() => {
    "faceId": faceId,
    "fileId": fileId,
    "creationTime": creationTimeMicros,
    "year": year,
    "score": score,
    "blur": blur,
  };

  factory _TimelineFaceData.fromJson(Map<String, dynamic> json) {
    return _TimelineFaceData(
      faceId: json["faceId"] as String,
      fileId: json["fileId"] as int,
      creationTimeMicros: json["creationTime"] as int,
      year: json["year"] as int,
      score: (json["score"] as num?)?.toDouble() ?? 0.0,
      blur: (json["blur"] as num?)?.toDouble() ?? 0.0,
    );
  }
}

Map<String, dynamic> _selectTimelineEntriesTask(Map<String, dynamic> param) {
  final int minYears = param["minYears"];
  final int minFacesPerYear = param["minFaces"];
  final int? minCreationTimeMicros = param["minCreationTime"];

  final faces = (param["faces"] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .map(_TimelineFaceData.fromJson)
      .toList();

  if (minCreationTimeMicros != null) {
    faces.removeWhere(
      (face) => face.creationTimeMicros < minCreationTimeMicros,
    );
  }

  if (faces.isEmpty) {
    return {"isEligible": false, "eligibleYearCount": 0};
  }

  final eligible = groupBy(faces, (face) => face.year).entries
      .where((entry) => entry.value.length >= minFacesPerYear)
      .sortedBy((a) => a.key);

  if (eligible.length < minYears) {
    return {"isEligible": false, "eligibleYearCount": eligible.length};
  }

  final selected = eligible
      .expand((entry) => _pickFacesForYear(entry.value))
      .sortedBy((face) => face.creationTimeMicros)
      .map((face) => face.toJson())
      .toList();

  final years = eligible.map((entry) => entry.key).toList();

  return {"isEligible": true, "entries": selected, "years": years};
}

List<_TimelineFaceData> _pickFacesForYear(List<_TimelineFaceData> faces) {
  if (faces.isEmpty) {
    return [];
  }

  final byQuality = faces.sorted((a, b) {
    const highScoreThreshold = 0.8;
    final aIsHighScore = a.score >= highScoreThreshold;
    final bIsHighScore = b.score >= highScoreThreshold;
    if (aIsHighScore != bIsHighScore) {
      return aIsHighScore ? -1 : 1;
    }

    final scoreComparison = b.score.compareTo(a.score);
    if (scoreComparison != 0) {
      return scoreComparison;
    }

    final blurComparison = b.blur.compareTo(a.blur);
    if (blurComparison != 0) {
      return blurComparison;
    }

    return a.creationTimeMicros.compareTo(b.creationTimeMicros);
  });

  final byDays = groupBy(byQuality, (face) {
    final date = DateTime.fromMicrosecondsSinceEpoch(face.creationTimeMicros);
    return date.year * 10000 + date.month * 100 + date.day;
  });

  final picks = byDays.values.map((group) => group[0]).take(4).toList();

  if (picks.length == 4) {
    return picks;
  }

  final selectedIds = picks.map((face) => face.faceId).toSet();
  picks.addAll(
    byQuality
        .where((face) => !selectedIds.contains(face.faceId))
        .take(4 - picks.length),
  );

  return picks;
}
