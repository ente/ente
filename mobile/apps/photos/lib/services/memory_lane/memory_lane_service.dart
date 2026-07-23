import "dart:async";

import "package:collection/collection.dart";
import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/memory_lane_changed_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/memory_lane/memory_lane_cache_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

typedef _TimelineComputationResult = ({
  MemoryLanePersonTimeline timeline,
  Map<int, EnteFile> filesById,
  int faceCount,
});

class MemoryLaneService {
  MemoryLaneService._internal();

  static final MemoryLaneService instance = MemoryLaneService._internal();

  static const _minimumYears = 2;
  static const _minimumFacesPerYear = 4;
  static const _minimumEligibleAgeYears = 3;
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
  final Map<String, _PendingRecomputeRequest> _pendingRequests = {};
  final Set<String> _cropReadinessInFlight = {};

  bool _initialized = false;

  StreamSubscription<PeopleChangedEvent>? _peopleChangedSubscription;
  Timer? _startupBackfillTimer;

  bool get isFeatureEnabled => flagService.facesTimeline;

  Future<void> init() async {
    if (_initialized) return;
    await _cacheService.init();
    await _cacheService.ensureComputeLogVersion(_timelineLogicVersion);
    await _refreshReadyPersonIds();
    _peopleChangedSubscription = Bus.instance.on<PeopleChangedEvent>().listen(
      _handlePeopleChange,
    );
    _scheduleStartupBackfill();
    _initialized = true;
  }

  Future<void> dispose() async {
    await _peopleChangedSubscription?.cancel();
    _startupBackfillTimer?.cancel();
    readyPersonIds.dispose();
  }

  Future<void> queueFullRecompute({
    bool force = false,
    String trigger = "",
  }) async {
    if (!isFeatureEnabled) {
      _logger.fine(
        "Memory Lane full recompute skipped ($trigger): feature disabled",
      );
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Memory Lane full recompute skipped: PersonService not initialized",
      );
      return;
    }
    final persons = await PersonService.instance.getPersons();
    for (final person in persons) {
      if (person.data.isIgnored) {
        await _handleIgnoredPerson(person.remoteID);
        continue;
      }
      schedulePersonRecompute(
        person.remoteID,
        force: force,
        trigger: trigger.isEmpty ? "full_recompute" : trigger,
      );
    }
  }

  void schedulePersonRecompute(
    String personId, {
    bool force = false,
    String trigger = "",
  }) {
    if (!isFeatureEnabled) {
      _logger.fine(
        "Memory Lane recompute skipped for $personId ($trigger): feature disabled",
      );
      return;
    }
    if (personId.isEmpty) return;
    final normalizedTrigger = trigger.isEmpty ? "unspecified" : trigger.trim();
    final existing = _pendingRequests[personId];
    if (existing != null) {
      existing.merge(force: force, trigger: normalizedTrigger);
    } else {
      _pendingRequests[personId] = _PendingRecomputeRequest(
        force: force,
        trigger: normalizedTrigger,
      );
    }
    _precomputeQueue
        .addTask(personId, () async {
          final request =
              _pendingRequests.remove(personId) ??
              _PendingRecomputeRequest(
                force: force,
                trigger: normalizedTrigger,
              );
          await _recomputeTimelineForPerson(
            personId,
            force: request.force,
            trigger: request.trigger,
          );
        })
        .catchError((error, stackTrace) {
          _pendingRequests.remove(personId);
          _logger.warning(
            "Memory Lane recompute task failed to enqueue for $personId",
            error,
            stackTrace,
          );
        });
  }

  Future<void> ensureTimelineReachability(
    String personId, {
    String trigger = "",
  }) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (personId.isEmpty) {
      return;
    }
    final normalizedTrigger = trigger.isEmpty
        ? "timeline_reachability"
        : trigger.trim();
    final timeline = await _cacheService.getTimeline(personId);
    if (timeline == null || !timeline.isReady || timeline.entries.isEmpty) {
      await _refreshReadyPersonIds();
      schedulePersonRecompute(personId, trigger: normalizedTrigger);
      return;
    }
    if (await _areTimelineFaceCropsCached(timeline)) {
      await _refreshReadyPersonIds();
      return;
    }
    await _refreshReadyPersonIds();
    _queueTimelineCropReadiness(personId, trigger: normalizedTrigger);
  }

  Future<MemoryLanePersonTimeline?> getTimeline(String personId) async {
    if (!isFeatureEnabled) return null;
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
      if (timeline.isReady && !await _areTimelineFaceCropsCached(timeline)) {
        _logger.info(
          "Memory Lane: cached timeline for $personId is missing face crops",
        );
        _queueTimelineCropReadiness(personId, trigger: "crop_cache_validation");
        await _refreshReadyPersonIds();
        return null;
      }
      return timeline;
    }

    _logger.info(
      "Memory Lane: evicting stale cached timeline for $personId due to hidden entries",
    );
    await _cacheService.removeTimeline(personId);
    await _refreshReadyPersonIds();
    schedulePersonRecompute(
      personId,
      force: true,
      trigger: "hidden_entry_validation",
    );
    return null;
  }

  bool hasReadyTimelineSync(String personId) {
    if (!isFeatureEnabled) {
      return false;
    }
    return readyPersonIds.value.contains(personId);
  }

  Future<bool> hasReadyTimeline(String personId) async {
    if (!isFeatureEnabled) return false;
    final timeline = await _cacheService.getTimeline(personId);
    return timeline != null &&
        timeline.isReady &&
        await _areTimelineFaceCropsCached(timeline);
  }

  Future<bool> _areTimelineFaceCropsCached(
    MemoryLanePersonTimeline timeline,
  ) async {
    if (!timeline.isReady || timeline.entries.isEmpty) {
      return false;
    }
    return areFullFaceCropsCached(
      timeline.entries.map((entry) => entry.faceId),
      useTempCache: false,
    );
  }

  void _queueTimelineCropReadiness(String personId, {required String trigger}) {
    if (_cropReadinessInFlight.contains(personId)) {
      return;
    }
    _cropReadinessInFlight.add(personId);
    _cropReadinessQueue
        .addTask(personId, () async {
          try {
            await _repairTimelineCropReadiness(personId, trigger: trigger);
          } finally {
            _cropReadinessInFlight.remove(personId);
          }
        })
        .catchError((error, stackTrace) {
          _cropReadinessInFlight.remove(personId);
          _logger.warning(
            "Memory Lane crop readiness task failed for $personId",
            error,
            stackTrace,
          );
        });
  }

  Future<void> _repairTimelineCropReadiness(
    String personId, {
    required String trigger,
  }) async {
    if (!isFeatureEnabled) {
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Memory Lane crop readiness skipped for $personId: PersonService not initialized",
      );
      return;
    }
    final timeline = await _cacheService.getTimeline(personId);
    if (timeline == null || !timeline.isReady || timeline.entries.isEmpty) {
      await _refreshReadyPersonIds();
      return;
    }
    if (await _areTimelineFaceCropsCached(timeline)) {
      await _refreshReadyPersonIds();
      Bus.instance.fire(
        MemoryLaneChangedEvent(
          personId: personId,
          status: MemoryLaneStatus.ready,
        ),
      );
      return;
    }
    final person = await PersonService.instance.getPerson(personId);
    if (person == null) {
      _logger.info("Memory Lane: person $personId missing, clearing cache");
      await _cacheService.removeTimeline(personId);
      await _refreshReadyPersonIds();
      Bus.instance.fire(
        MemoryLaneChangedEvent(
          personId: personId,
          status: MemoryLaneStatus.ineligible,
        ),
      );
      return;
    }
    if (person.data.isIgnored) {
      _logger.info("Memory Lane: person $personId ignored, clearing cache");
      await _handleIgnoredPerson(personId);
      return;
    }

    final fileIds = timeline.entries.map((entry) => entry.fileId).toSet();
    final filesById = await _filesDB.getFileIDToFileFromIDs(fileIds.toList());
    final cropsReady = await _ensureFaceCrops(
      person,
      timeline.entries,
      filesById,
    );
    await _refreshReadyPersonIds();
    if (cropsReady) {
      Bus.instance.fire(
        MemoryLaneChangedEvent(
          personId: personId,
          status: MemoryLaneStatus.ready,
        ),
      );
    } else {
      _logger.warning(
        "Memory Lane crop readiness failed for $personId (trigger: $trigger)",
      );
    }
  }

  Future<void> _handleIgnoredPerson(String personId) async {
    _pendingRequests.remove(personId);
    await _cacheService.removeTimeline(personId);
    await _refreshReadyPersonIds();
    Bus.instance.fire(
      MemoryLaneChangedEvent(
        personId: personId,
        status: MemoryLaneStatus.ineligible,
      ),
    );
  }

  void _handlePeopleChange(PeopleChangedEvent event) {
    if (!isFeatureEnabled) {
      _logger.fine(
        "Memory Lane people change ignored (${event.type.name}): feature disabled",
      );
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
      _logger.warning(
        "Memory Lane: people event ${event.type.name} missing person data",
      );
      _scheduleStartupBackfill();
      return;
    }
    if (person.data.isIgnored) {
      await _handleIgnoredPerson(person.remoteID);
      return;
    }
    final String triggerPrefix = "people_event_${event.type.name}";
    final logEntry = await _cacheService.getComputeLogEntry(person.remoteID);
    if (logEntry == null) {
      _logger.info(
        "Memory Lane: no compute log for ${person.remoteID}, forcing recompute ($triggerPrefix)",
      );
      schedulePersonRecompute(
        person.remoteID,
        force: true,
        trigger: "${triggerPrefix}_no_log",
      );
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
      _logger.fine(
        "Memory Lane: ${person.remoteID} change ignored "
        "(no name/dob/face count deltas)",
      );
      return;
    }

    final timeline = await _cacheService.getTimeline(person.remoteID);
    final Set<String> currentFaceIdSet = faceIds;

    if (_timelineFacesMissing(timeline, currentFaceIdSet)) {
      final trigger = "${triggerPrefix}_face_removed";
      _logger.info(
        "Memory Lane: recompute scheduled for ${person.remoteID} ($trigger)",
      );
      schedulePersonRecompute(person.remoteID, trigger: trigger);
      return;
    }

    if (birthDateChanged) {
      final trigger = "${triggerPrefix}_birthdate_changed";
      _logger.info(
        "Memory Lane: recompute scheduled for ${person.remoteID} ($trigger)",
      );
      schedulePersonRecompute(person.remoteID, trigger: trigger);
      return;
    }

    if (!faceCountChanged) {
      _logger.fine(
        "Memory Lane: ${person.remoteID} change skipped after checks "
        "(nameChanged=$nameChanged, faceCountChanged=$faceCountChanged)",
      );
      return;
    }

    final facesPerYear = await _countEligibleFacesByYear(person, faceIds);
    if (_hasNewYearWithTenFaces(timeline, facesPerYear)) {
      final trigger = "${triggerPrefix}_new_year";
      _logger.info(
        "Memory Lane: recompute scheduled for ${person.remoteID} ($trigger)",
      );
      schedulePersonRecompute(person.remoteID, trigger: trigger);
      return;
    }

    _logger.fine(
      "Memory Lane: ${person.remoteID} change skipped "
      "(nameChanged=$nameChanged, birthDateChanged=$birthDateChanged, "
      "faceCountChanged=$faceCountChanged)",
    );
  }

  void _scheduleStartupBackfill() {
    if (!isFeatureEnabled) return;
    _startupBackfillTimer?.cancel();
    _startupBackfillTimer = Timer(_startupBackfillDelay, () {
      if (!isFeatureEnabled) {
        return;
      }
      unawaited(_runStartupBackfill());
    });
  }

  Future<void> _runStartupBackfill() async {
    if (!isFeatureEnabled) return;
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Memory Lane startup diff skipped: PersonService not initialized",
      );
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
        if (person.data.isIgnored) continue;
        if (alreadyComputed.contains(person.remoteID)) continue;
        missingIds.add(person.remoteID);
        if (missingIds.length >= _startupBackfillBatchSize) {
          break;
        }
      }
      if (missingIds.isEmpty) {
        _logger.fine("Memory Lane startup diff: all persons covered");
        return;
      }
      for (final personId in missingIds) {
        schedulePersonRecompute(personId, force: true, trigger: "startup_diff");
      }
      _logger.info(
        "Memory Lane startup diff queued ${missingIds.length} persons",
      );
    } catch (error, stackTrace) {
      _logger.severe("Memory Lane startup diff failed", error, stackTrace);
    }
  }

  Future<Map<int, int>> _countEligibleFacesByYear(
    PersonEntity person,
    Iterable<String> faceIds,
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
    final minCreationTime = minimumEligibleCreationTimeMicros(
      person.data.birthDate,
    );
    final counts = <int, int>{};
    for (final faceId in faceIds) {
      final fileId = getFileIdFromFaceId<int>(faceId);
      if (hiddenFileIds.contains(fileId)) continue;
      final file = fileMap[fileId];
      final creationTime = file?.creationTime;
      if (creationTime == null || creationTime <= 0) {
        continue;
      }
      if (minCreationTime != null && creationTime < minCreationTime) {
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
    required String trigger,
  }) async {
    if (!isFeatureEnabled) {
      _logger.fine(
        "Memory Lane compute skipped for $personId ($trigger): feature disabled",
      );
      return;
    }
    if (!PersonService.isInitialized) {
      _logger.warning(
        "Memory Lane recompute skipped for $personId: PersonService not initialized",
      );
      return;
    }

    final person = await PersonService.instance.getPerson(personId);
    if (person == null) {
      _logger.info("Memory Lane: person $personId missing, clearing cache");
      await _cacheService.removeTimeline(personId);
      await _refreshReadyPersonIds();
      Bus.instance.fire(
        MemoryLaneChangedEvent(
          personId: personId,
          status: MemoryLaneStatus.ineligible,
        ),
      );
      return;
    }
    if (person.data.isIgnored) {
      _logger.info("Memory Lane: person $personId ignored, clearing cache");
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
        _logger.fine(
          "Memory Lane compute skipped for $personId due to cooldown "
          "(elapsed ${remaining / Duration.microsecondsPerHour} hours, trigger: $trigger)",
        );
        return;
      }
    }
    if (!force && lastForcedMicros != null) {
      final remaining = nowMicros - lastForcedMicros;
      if (remaining < _recomputeCooldown.inMicroseconds) {
        _logger.fine(
          "Memory Lane compute skipped for $personId due to forced cooldown "
          "(elapsed ${remaining / Duration.microsecondsPerHour} hours, trigger: $trigger)",
        );
        return;
      }
    }

    if (force) {
      _lastForcedComputeMicros[personId] = nowMicros;
    }

    try {
      final result = await _computeTimeline(person, nowMicros);
      await _cacheService.upsertTimeline(result.timeline);
      await _cacheService.upsertComputeLogEntry(
        MemoryLaneComputeLogEntry(
          personId: person.remoteID,
          name: person.data.name,
          birthDate: person.data.birthDate,
          faceCount: result.faceCount,
          lastComputedMicros: nowMicros,
          logicVersion: _timelineLogicVersion,
        ),
      );
      if (!result.timeline.isReady) {
        await _refreshReadyPersonIds();
        Bus.instance.fire(
          MemoryLaneChangedEvent(
            personId: person.remoteID,
            status: result.timeline.status,
          ),
        );
        return;
      }
      final cropsReady = await _ensureFaceCrops(
        person,
        result.timeline.entries,
        result.filesById,
      );
      await _refreshReadyPersonIds();
      if (cropsReady) {
        Bus.instance.fire(
          MemoryLaneChangedEvent(
            personId: person.remoteID,
            status: result.timeline.status,
          ),
        );
      } else {
        _logger.warning(
          "Memory Lane crop readiness failed for $personId (trigger: $trigger)",
        );
        _queueTimelineCropReadiness(
          person.remoteID,
          trigger: "recompute_crop_retry",
        );
      }
    } catch (error, stackTrace) {
      _logger.severe(
        "Memory Lane compute failed for $personId (trigger: $trigger)",
        error,
        stackTrace,
      );
    }
  }

  Future<_TimelineComputationResult> _computeTimeline(
    PersonEntity person,
    int nowMicros,
  ) async {
    final personId = person.remoteID;
    final minCreationTimeMicros = minimumEligibleCreationTimeMicros(
      person.data.birthDate,
    );
    final faceIds = await _mlDataDB.getFaceIDsForPerson(personId);
    final totalFaceCount = faceIds.length;
    if (faceIds.isEmpty) {
      _logger.fine(
        "Memory Lane: person $personId has no faces, marking ineligible",
      );
      final timeline = MemoryLanePersonTimeline(
        personId: personId,
        status: MemoryLaneStatus.ineligible,
        updatedAtMicros: nowMicros,
        entries: const [],
      );
      return (
        timeline: timeline,
        filesById: const <int, EnteFile>{},
        faceCount: totalFaceCount,
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
      if (hiddenFileIds.contains(fileId)) continue;
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
      _logger.fine(
        "Memory Lane: person $personId has no usable faces after filtering,"
        " marking ineligible",
      );
      final timeline = MemoryLanePersonTimeline(
        personId: personId,
        status: MemoryLaneStatus.ineligible,
        updatedAtMicros: nowMicros,
        entries: const [],
      );
      return (
        timeline: timeline,
        filesById: fileMap,
        faceCount: totalFaceCount,
      );
    }

    final selectionResult = await Computer.shared().compute(
      selectTimelineEntriesTask,
      param: {
        "faces": faces.map((face) => face.toJson()).toList(),
        "minYears": _minimumYears,
        "minFaces": _minimumFacesPerYear,
        "minCreationTime": ?minCreationTimeMicros,
      },
      taskName: "faces_timeline_select_${person.remoteID}",
    );

    if (selectionResult["status"] != "ready") {
      final eligibleYearCount =
          selectionResult["eligibleYearCount"] as int? ?? 0;
      _logger.info(
        "Memory Lane: person $personId ineligible "
        "(eligibleYears=$eligibleYearCount, faces=${faces.length})",
      );
      final timeline = MemoryLanePersonTimeline(
        personId: personId,
        status: MemoryLaneStatus.ineligible,
        updatedAtMicros: nowMicros,
        entries: const [],
      );
      return (
        timeline: timeline,
        filesById: fileMap,
        faceCount: totalFaceCount,
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

    final timeline = MemoryLanePersonTimeline(
      personId: personId,
      status: MemoryLaneStatus.ready,
      updatedAtMicros: nowMicros,
      entries: entries,
    );

    final years =
        (selectionResult["years"] as List<dynamic>?)?.cast<int>().join(", ") ??
        "unknown";
    _logger.info(
      "Memory Lane ready for $personId "
      "(frames=${entries.length}, years=$years)",
    );

    return (timeline: timeline, filesById: fileMap, faceCount: totalFaceCount);
  }

  Future<bool> _ensureFaceCrops(
    PersonEntity person,
    List<MemoryLaneEntry> entries,
    Map<int, EnteFile> fileMap,
  ) async {
    final personId = person.remoteID;
    if (entries.isEmpty) {
      return false;
    }
    var allCropsReady = true;
    final entriesByFile = <int, List<MemoryLaneEntry>>{};
    for (final entry in entries) {
      entriesByFile.putIfAbsent(entry.fileId, () => []).add(entry);
    }

    for (final entry in entriesByFile.entries) {
      final file = fileMap[entry.key];
      if (file == null) {
        allCropsReady = false;
        _logger.warning(
          "Memory Lane: failed to cache crops for $personId, file ${entry.key} missing",
        );
        continue;
      }
      final faces = await _mlDataDB.getFacesForGivenFileID(entry.key);
      if (faces == null || faces.isEmpty) {
        allCropsReady = false;
        _logger.warning(
          "Memory Lane: failed to cache crops for $personId, no faces for file ${entry.key}",
        );
        continue;
      }
      final selectedFaces = entry.value
          .map(
            (timelineEntry) => faces.firstWhereOrNull(
              (face) => face.faceID == timelineEntry.faceId,
            ),
          )
          .whereType<Face>()
          .toList();
      if (selectedFaces.length != entry.value.length) {
        allCropsReady = false;
        _logger.warning(
          "Memory Lane: failed to cache all crops for $personId file ${entry.key}, some faces missing",
        );
      }
      if (selectedFaces.isEmpty) {
        continue;
      }
      try {
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
        for (final face in selectedFaces) {
          final crop = cropMap[face.faceID];
          if (crop == null || crop.isEmpty) {
            allCropsReady = false;
            _logger.warning(
              "Memory Lane: missing generated crop for $personId file ${entry.key}",
            );
          }
        }
      } catch (error, stackTrace) {
        allCropsReady = false;
        _logger.warning(
          "Memory Lane: failed to cache crops for $personId file ${entry.key}",
          error,
          stackTrace,
        );
      }
    }
    return allCropsReady;
  }

  Future<void> prewarmTimelineFrames(
    String personId, {
    int frameCount = 6,
  }) async {
    if (!isFeatureEnabled) return;
    try {
      final timeline = await _cacheService.getTimeline(personId);
      if (timeline == null || !timeline.isReady || timeline.entries.isEmpty) {
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
      final stopwatch = Stopwatch()..start();
      int warmed = 0;
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
        try {
          await getCachedFaceCrops(
            file,
            [face],
            useFullFile: true,
            useTempCache: false,
          );
          warmed += 1;
        } catch (error, stackTrace) {
          _logger.fine(
            "Memory Lane prewarm failed for $personId file ${entry.fileId}",
            error,
            stackTrace,
          );
        }
      }
      _logger.fine(
        "Memory Lane prewarm person=$personId warmed=$warmed "
        "target=$frameCount elapsed=${stopwatch.elapsedMilliseconds}ms",
      );
    } catch (error, stackTrace) {
      _logger.fine(
        "Memory Lane prewarm error for $personId",
        error,
        stackTrace,
      );
    }
  }

  Future<void> _refreshReadyPersonIds() async {
    final cache = await _cacheService.getCache();
    final current = <String>{};
    for (final timeline in cache.allTimelines) {
      if (!timeline.isReady) {
        continue;
      }
      if (await _areTimelineFaceCropsCached(timeline)) {
        current.add(timeline.personId);
      }
    }
    readyPersonIds.value = current;
  }

  static int completedYearsBetween(DateTime start, DateTime end) {
    final startDate = DateTime(start.year, start.month, start.day);
    final endDate = DateTime(end.year, end.month, end.day);
    if (endDate.isBefore(startDate)) {
      return 0;
    }
    int years = endDate.year - startDate.year;
    if (endDate.isBefore(_safeDateInYear(startDate, endDate.year))) {
      years -= 1;
    }
    return years < 0 ? 0 : years;
  }

  @visibleForTesting
  static int? minimumEligibleCreationTimeMicros(String? birthDateString) {
    if (birthDateString == null || birthDateString.isEmpty) {
      return null;
    }
    final birthDate = DateTime.tryParse(birthDateString);
    if (birthDate == null) {
      return null;
    }
    final cutoff = _safeDateInYear(
      birthDate,
      birthDate.year + _minimumEligibleAgeYears,
    );
    return cutoff.microsecondsSinceEpoch;
  }

  static DateTime _safeDateInYear(DateTime date, int year) {
    final daysInTargetMonth = DateTime(year, date.month + 1, 0).day;
    final targetDay = date.day > daysInTargetMonth
        ? daysInTargetMonth
        : date.day;
    return DateTime(year, date.month, targetDay);
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

  bool get hasHighScore => score >= 0.8;
}

Map<String, dynamic> selectTimelineEntriesTask(Map<String, dynamic> param) {
  final facesJson = (param["faces"] as List<dynamic>)
      .cast<Map<String, dynamic>>();
  final minYears = param["minYears"] as int;
  final minFacesPerYear = param["minFaces"] as int;
  final minCreationTimeMicros = param["minCreationTime"] as int?;

  final faces = facesJson.map(_TimelineFaceData.fromJson).toList();

  if (minCreationTimeMicros != null) {
    faces.removeWhere(
      (face) => face.creationTimeMicros < minCreationTimeMicros,
    );
  }

  if (faces.isEmpty) {
    return {"status": "ineligible", "eligibleYearCount": 0};
  }

  final yearGroups = <int, List<_TimelineFaceData>>{};
  for (final face in faces) {
    yearGroups.putIfAbsent(face.year, () => []).add(face);
  }

  final eligibleEntries =
      yearGroups.entries
          .where((entry) => entry.value.length >= minFacesPerYear)
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));

  if (eligibleEntries.length < minYears) {
    return {
      "status": "ineligible",
      "eligibleYearCount": eligibleEntries.length,
    };
  }

  final selected = <_TimelineFaceData>[];
  final years = <int>[];
  for (final entry in eligibleEntries) {
    entry.value.sort(
      (a, b) => a.creationTimeMicros.compareTo(b.creationTimeMicros),
    );
    years.add(entry.key);
    final picks = _pickFacesForYear(entry.value);
    selected.addAll(picks);
  }

  selected.sort((a, b) => a.creationTimeMicros.compareTo(b.creationTimeMicros));

  return {
    "status": "ready",
    "entries": selected.map((face) => face.toJson()).toList(),
    "years": years,
  };
}

List<_TimelineFaceData> _pickFacesForYear(List<_TimelineFaceData> faces) {
  if (faces.isEmpty) {
    return <_TimelineFaceData>[];
  }

  final sortedByQuality = List<_TimelineFaceData>.from(faces)
    ..sort(_compareFaceQuality);

  final picks = <_TimelineFaceData>[];
  final selectedIds = <String>{};
  final usedDayKeys = <int>{};
  final uniqueDayKeys = sortedByQuality
      .map((face) => _dayKeyForMicros(face.creationTimeMicros))
      .toSet();
  final totalUniqueDays = uniqueDayKeys.length;
  final targetUniqueDayCount = totalUniqueDays >= 4 ? 4 : totalUniqueDays;
  final allowDuplicateDays = totalUniqueDays < 4;

  if (targetUniqueDayCount > 0) {
    for (final face in sortedByQuality) {
      final dayKey = _dayKeyForMicros(face.creationTimeMicros);
      if (usedDayKeys.contains(dayKey)) {
        continue;
      }
      picks.add(face);
      selectedIds.add(face.faceId);
      usedDayKeys.add(dayKey);
      if (picks.length == targetUniqueDayCount) {
        break;
      }
    }
  }

  if (picks.length < 4) {
    for (final face in sortedByQuality) {
      if (selectedIds.contains(face.faceId)) {
        continue;
      }
      final dayKey = _dayKeyForMicros(face.creationTimeMicros);
      if (!allowDuplicateDays && usedDayKeys.contains(dayKey)) {
        continue;
      }
      picks.add(face);
      selectedIds.add(face.faceId);
      usedDayKeys.add(dayKey);
      if (picks.length == 4) {
        break;
      }
    }
  }

  picks.sort((a, b) => a.creationTimeMicros.compareTo(b.creationTimeMicros));
  return picks;
}

int _compareFaceQuality(_TimelineFaceData a, _TimelineFaceData b) {
  final highScoreComparison =
      (b.hasHighScore ? 1 : 0) - (a.hasHighScore ? 1 : 0);
  if (highScoreComparison != 0) {
    return highScoreComparison;
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
}

int _dayKeyForMicros(int micros) {
  final localDate = DateTime.fromMicrosecondsSinceEpoch(micros);
  return localDate.year * 10000 + localDate.month * 100 + localDate.day;
}

class _PendingRecomputeRequest {
  bool force;
  final Set<String> _triggers;

  _PendingRecomputeRequest({required this.force, required String trigger})
    : _triggers = {_normalizeTrigger(trigger)};

  void merge({required bool force, required String trigger}) {
    this.force = this.force || force;
    _triggers.add(_normalizeTrigger(trigger));
  }

  String get trigger => _triggers.join("|");

  static String _normalizeTrigger(String trigger) {
    final trimmed = trigger.trim();
    if (trimmed.isEmpty) return "unspecified";
    return trimmed;
  }
}
