import "dart:async";
import "dart:convert" show jsonEncode;
import "dart:io" show File, Platform;
import "dart:math" show min;
import "dart:typed_data" show Uint8List;

import "package:flutter/foundation.dart" show kDebugMode;
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/compute_control_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/main.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/module/download/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import "package:photos/services/machine_learning/face_ml/face_detection/detection.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_process_lock.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/process_activity.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/ml_util.dart";
import "package:photos/utils/network_util.dart";
import "package:photos/utils/ram_check_util.dart";

class MLService {
  final _logger = Logger("MLService");

  MLService._privateConstructor();
  static final instance = MLService._privateConstructor();

  bool _isInitialized = false;

  int? _lastRemoteFetch;
  static const int _kRemoteFetchCooldownOnLite = 1000 * 60 * 5;
  static const int _kStartupOwnedRemoteHydrationMissingFileThreshold = 200;
  Future<void>? _ownedRemoteHydrationFuture;
  bool _hasScheduledStartupOwnedRemoteHydration = false;

  late String client;

  bool get showClusteringIsHappening => _clusteringIsHappening;

  bool debugIndexingDisabled = false;
  bool _clusteringIsHappening = false;
  bool _mlControllerStatus = false;
  final Set<MlRunControl> _runControls = {};
  MlRunControl? _activeRunControl;
  Timer? _bgYieldPollTimer;
  Timer? _deniedRunRetryTimer;
  Timer? _predownloadLocalModelsTimer;

  static const _kPredownloadLocalModelsDelay = Duration(seconds: 10);
  static const _kBgYieldPollInterval = Duration(seconds: 3);
  static const _kDeniedRunRetryDelay = Duration(seconds: 15);

  bool get _isRunningML =>
      MlProcessLock.instance.activeOperation == MlOperation.fullRun;

  static const _kForceClusteringFaceCount = 8000;
  static const _kForceClusteringFaceCountLocalGallery = 100;
  int _forceClusteringFaceCountForMode(MLMode mode) {
    return mode == MLMode.localGallery
        ? _kForceClusteringFaceCountLocalGallery
        : _kForceClusteringFaceCount;
  }

  MLDataDB get _mlDataDB =>
      isLocalGalleryMode ? MLDataDB.localGalleryInstance : MLDataDB.instance;

  MLDataDB _dbForMode(MLMode mode) {
    return mode == MLMode.localGallery
        ? MLDataDB.localGalleryInstance
        : MLDataDB.instance;
  }

  Future<void> init() async {
    if (_isInitialized) {
      _schedulePredownloadLocalModels();
      scheduleStartupOwnedRemoteHydration();
      return;
    }
    _logger.info("init called");

    await checkDeviceTotalRAM();

    FaceClusteringService.init(localSettings);

    final packageInfo = ServiceLocator.instance.packageInfo;
    client = "${packageInfo.packageName}/${packageInfo.version}";
    _logger.info("client: $client");

    Bus.instance.on<ComputeControlEvent>().listen((event) {
      if (!hasGrantedMLConsent) {
        if (!isProcessBg && event.shouldRun) {
          VideoPreviewService.instance.queueFiles(duration: Duration.zero);
        }
        return;
      }

      _mlControllerStatus = event.shouldRun;
      if (_mlControllerStatus) {
        _logger.info(
          "MLController allowed running ML, faces indexing starting",
        );
        // Background start is driven manually from _runMinimally to avoid
        // duplicate runAllML invocations in the same cycle.
        if (!isProcessBg) {
          unawaited(runAllML());
        }
      } else {
        _logger.info(
          "MLController stopped running ML, stopping any active ML run",
        );
        stopActiveRun(MlStopReason.controller);
      }
    });
    // Every setAppMode call site fires this event, so a latched stop fully
    // replaces polled mode checks inside the pipeline.
    Bus.instance.on<AppModeChangedEvent>().listen((_) {
      stopActiveRun(MlStopReason.modeChanged);
    });
    _syncMlControllerStatusForBg();

    _isInitialized = true;
    _schedulePredownloadLocalModels();
    scheduleStartupOwnedRemoteHydration();
    _logger.info('init done');
  }

  void _syncMlControllerStatusForBg() {
    if (!isProcessBg || !hasGrantedMLConsent) {
      return;
    }
    _mlControllerStatus = computeController.shouldRunCompute;
    _logger.info(
      "Background init synced MLController status to $_mlControllerStatus",
    );
  }

  Future<void> _maybePredownloadLocalModels() async {
    if (isProcessBg) {
      return;
    }
    if (!hasGrantedMLConsent) {
      return;
    }
    if (!localSettings.isMLLocalIndexingEnabled) {
      _logger.info(
        "Skipping ML model predownload because local indexing is disabled",
      );
      return;
    }
    if (MLModelDownloadService.instance.areModelsDownloaded(
      onlyIndexingModels: false,
    )) {
      return;
    }
    try {
      await MLModelDownloadService.instance.ensureModelsDownloaded(
        onlyIndexingModels: false,
      );
    } catch (e, s) {
      _logger.warning("Failed to predownload local ML models", e, s);
    }
  }

  void scheduleStartupOwnedRemoteHydration() {
    if (_hasScheduledStartupOwnedRemoteHydration ||
        isProcessBg ||
        !hasGrantedMLConsent ||
        isLocalGalleryMode ||
        !localSettings.remoteFetchEnabled) {
      return;
    }
    _hasScheduledStartupOwnedRemoteHydration = true;
    unawaited(_runStartupOwnedRemoteHydration());
  }

  Future<void> _runStartupOwnedRemoteHydration() async {
    if (!hasGrantedMLConsent || isLocalGalleryMode) {
      return;
    }
    try {
      await fileDataService.syncFDStatus();
    } catch (e, s) {
      _logger.warning(
        "Skipping startup-owned remote ML hydration because FD status refresh failed",
        e,
        s,
      );
      return;
    }
    try {
      await hydrateRemoteEmbeddingsForOwnedFiles(
        reason: "startup",
        skipHydrationIfCandidateFileCountAtMost:
            _kStartupOwnedRemoteHydrationMissingFileThreshold,
      );
    } catch (e, s) {
      _logger.warning(
        "Skipping startup-owned remote ML hydration because owned hydration failed",
        e,
        s,
      );
    }
  }

  Future<void> hydrateRemoteEmbeddingsForOwnedFiles({
    required String reason,
    int? skipHydrationIfCandidateFileCountAtMost,
  }) async {
    if (isProcessBg ||
        isLocalGalleryMode ||
        !hasGrantedMLConsent ||
        !localSettings.remoteFetchEnabled) {
      return;
    }
    final existing = _ownedRemoteHydrationFuture;
    if (existing != null) {
      _logger.info(
        "Owned remote ML hydration already running, joining existing run ($reason)",
      );
      return existing;
    }
    final control = MlRunControl();
    final attempt = await _runExclusiveWithControl(
      MlOperation.startupRemoteHydration,
      control,
      () async {
        final future = _runOwnedRemoteHydrationSafely(
          reason: reason,
          control: control,
          skipHydrationIfCandidateFileCountAtMost:
              skipHydrationIfCandidateFileCountAtMost,
        );
        _ownedRemoteHydrationFuture = future;
        try {
          await future;
        } finally {
          if (identical(_ownedRemoteHydrationFuture, future)) {
            _ownedRemoteHydrationFuture = null;
          }
        }
      },
    );
    if (attempt != MlLockAttempt.ran) {
      _logger.info(
        "Skipping owned remote ML hydration ($reason): ml process lock "
        "denied (${attempt.name})",
      );
    }
  }

  Future<void> _runOwnedRemoteHydrationSafely({
    required String reason,
    required MlRunControl control,
    int? skipHydrationIfCandidateFileCountAtMost,
  }) async {
    assert(MlProcessLock.instance.isBusy, "ml funnel must be held");
    if (control.stopRequested) {
      _logRunStopped(control, "before owned remote hydration started");
      return;
    }
    try {
      final summary = await hydrateOwnedRemoteMLData(
        mlDataDB: MLDataDB.instance,
        control: control,
        skipHydrationIfCandidateFileCountAtMost:
            skipHydrationIfCandidateFileCountAtMost,
      );
      if (summary.candidateFiles == 0) {
        _logger.info(
          "Skipping owned remote ML hydration ($reason): no owned files need remote hydration",
        );
        return;
      }
      if (summary.skippedDueToCandidateThreshold) {
        _logger.info(
          "Skipping owned remote ML hydration ($reason): only ${summary.candidateFiles} "
          "owned files are missing remote ML data (threshold: > "
          "$skipHydrationIfCandidateFileCountAtMost)",
        );
        return;
      }
      _logger.info(
        "Owned remote ML hydration ($reason) finished for ${summary.candidateFiles} files "
        "(faces hydrated: ${summary.hydratedFaces}, clip hydrated: ${summary.hydratedClips}, "
        "still pending local ML: ${summary.remainingLocalMl})",
      );
    } catch (e, s) {
      _logger.warning("Owned remote ML hydration ($reason) failed", e, s);
    }
  }

  void _schedulePredownloadLocalModels() {
    if (isProcessBg || _predownloadLocalModelsTimer?.isActive == true) {
      return;
    }
    _predownloadLocalModelsTimer = Timer(_kPredownloadLocalModelsDelay, () {
      _predownloadLocalModelsTimer = null;
      unawaited(_maybePredownloadLocalModels());
    });
  }

  bool canFetch() {
    if (localSettings.isMLLocalIndexingEnabled) return true;
    if (_lastRemoteFetch == null) {
      _lastRemoteFetch = DateTime.now().millisecondsSinceEpoch;
      return true;
    }
    final intDiff = DateTime.now().millisecondsSinceEpoch - _lastRemoteFetch!;
    final bool canFetch = intDiff > _kRemoteFetchCooldownOnLite;
    if (canFetch) {
      _lastRemoteFetch = DateTime.now().millisecondsSinceEpoch;
    }
    return canFetch;
  }

  Future<void> _sync() async {
    await fileDataService.syncFDStatus();
    await PersonService.instance.sync();
  }

  Future<MlRunDisposition> runAllML({
    bool force = false,
    MlRunControl? control,
  }) async {
    final runControl = control ?? MlRunControl();
    // A latched stop always wins, force included.
    if (runControl.stopRequested) {
      _logger.info(
        "runAllML skipped, stop already requested "
        "(${runControl.stopReason?.name})",
      );
      return MlRunDisposition.stopped;
    }
    if (_isRunningML) {
      _logger.info("runAllML called while already running, skipping");
      _scheduleDeniedRunRetry();
      return MlRunDisposition.denied;
    }
    if (!hasGrantedMLConsent) {
      _logger.info("runAllML called without ML consent, skipping");
      return MlRunDisposition.denied;
    }
    final MLMode mode = isLocalGalleryMode
        ? MLMode.localGallery
        : MLMode.enteGallery;
    if (force) {
      _mlControllerStatus = true;
    }
    if (!_canRunMLFunction(function: "AllML") && !force) {
      return MlRunDisposition.denied;
    }
    if (!force && !computeController.requestCompute(ml: true)) {
      return MlRunDisposition.denied;
    }
    var disposition = MlRunDisposition.completed;
    try {
      final attempt = await _runExclusiveWithControl(
        MlOperation.fullRun,
        runControl,
        () async {
          disposition = await _runAllMLProtected(
            mode: mode,
            force: force,
            control: runControl,
          );
        },
      );
      if (attempt != MlLockAttempt.ran) {
        _logger.info("runAllML denied the ml process lock (${attempt.name})");
        disposition = MlRunDisposition.denied;
        _scheduleDeniedRunRetry();
      }
    } catch (e, s) {
      _logger.severe("runAllML failed", e, s);
      disposition = MlRunDisposition.failed;
    } finally {
      computeController.releaseCompute(ml: true);
    }
    return disposition;
  }

  // FG-only: one coalesced retry after a lock denial, because the natural
  // ComputeControlEvent re-trigger only fires on an interaction or health
  // transition — without this, an untouched device would stall until the
  // next user interaction. Preconditions are re-validated when it fires.
  void _scheduleDeniedRunRetry() {
    if (isProcessBg) return;
    if (_deniedRunRetryTimer != null) return;
    _deniedRunRetryTimer = Timer(_kDeniedRunRetryDelay, () {
      _deniedRunRetryTimer = null;
      if (!hasGrantedMLConsent) return;
      if (MlProcessLock.instance.isBusy) {
        _scheduleDeniedRunRetry();
        return;
      }
      triggerML();
    });
  }

  Future<MlRunDisposition> _runAllMLProtected({
    required MLMode mode,
    required bool force,
    required MlRunControl control,
  }) async {
    assert(MlProcessLock.instance.isBusy, "ml funnel must be held");
    if (control.stopRequested) {
      _logRunStopped(control, "before sync");
      return MlRunDisposition.stopped;
    }
    final mlDataDB = _dbForMode(mode);
    try {
      await _sync();
      if (control.stopRequested) {
        _logRunStopped(control, "after sync");
        return MlRunDisposition.stopped;
      }

      final int unclusteredFacesCount = await mlDataDB
          .getUnclusteredFaceCount();
      if (unclusteredFacesCount > _forceClusteringFaceCountForMode(mode)) {
        _logger.info(
          "There are $unclusteredFacesCount unclustered faces, doing clustering first",
        );
        await _clusterAllImages(control: control);
      }
      if (control.stopRequested) {
        _logRunStopped(control, "after initial clustering");
        return MlRunDisposition.stopped;
      }
      if (_mlControllerStatus == true) {
        // Cache refreshes only read ML stores, so they may safely outlive
        // this run and the process lock.
        magicCacheService.updateCache(forced: force).ignore();
        memoriesCacheService.updateCache(forced: force).ignore();
      }
      if (control.stopRequested) {
        _logRunStopped(control, "before indexing");
        return MlRunDisposition.stopped;
      }
      if (canFetch()) {
        await _fetchAndIndexAllImages(mode: mode, control: control);
      }
      if (control.stopRequested) {
        _logRunStopped(control, "before final clustering");
        return MlRunDisposition.stopped;
      }
      if ((await mlDataDB.getUnclusteredFaceCount()) > 0) {
        await _clusterAllImages(control: control);
      }
      if (control.stopRequested) {
        _logRunStopped(control, "before post-run cache scheduling");
        return MlRunDisposition.stopped;
      }
      if (_mlControllerStatus == true) {
        // Persist refreshed caches after ML so foreground can pick them up
        // on the next resume, even when the work ran headlessly in background.
        magicCacheService.updateCache().ignore();
        memoriesCacheService.updateCache(forced: force).ignore();
      }
      return MlRunDisposition.completed;
    } finally {
      _logger.info("ML finished running");
      if (!isProcessBg) {
        VideoPreviewService.instance.queueFiles();
      }
    }
  }

  void _logRunStopped(MlRunControl control, String where) {
    _logger.info("ML run stopped $where (${control.stopReason?.name})");
  }

  Future<MlLockAttempt> _runExclusiveWithControl(
    MlOperation operation,
    MlRunControl control,
    Future<void> Function() body,
  ) async {
    _runControls.add(control);
    try {
      return await MlProcessLock.instance.tryRunExclusive(operation, () async {
        _installRunControl(control);
        try {
          await body();
        } finally {
          _clearRunControl(control);
        }
      }, background: isProcessBg);
    } finally {
      _runControls.remove(control);
    }
  }

  void _installRunControl(MlRunControl control) {
    _activeRunControl = control;
    control.attachOnStop(() {
      MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = true;
    });
    // BG always yields to FG: while a BG run holds the lock, watch for the
    // foreground engine's heartbeat and wind down as soon as it appears.
    if (isProcessBg) {
      _bgYieldPollTimer = Timer.periodic(_kBgYieldPollInterval, (_) async {
        if (control.stopRequested) return;
        if (await isForegroundEngineActive()) {
          control.requestStop(MlStopReason.foregroundActive);
        }
      });
    }
  }

  // The isolate stop flag is cleared here, from the outer run cleanup, and
  // nowhere else: a durable stop must survive stage-level finally blocks.
  void _clearRunControl(MlRunControl control) {
    _bgYieldPollTimer?.cancel();
    _bgYieldPollTimer = null;
    control.detachOnStop();
    if (identical(_activeRunControl, control)) {
      _activeRunControl = null;
    }
    MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = false;
  }

  void triggerML() {
    if (_mlControllerStatus && !MlProcessLock.instance.isBusy) {
      unawaited(runAllML());
    }
  }

  void stopActiveRun(MlStopReason reason) {
    for (final control in _runControls.toList(growable: false)) {
      control.requestStop(reason);
    }
  }

  Future<MlLockAttempt> fetchAndIndexAllImages({required MLMode mode}) async {
    final control = MlRunControl();
    final attempt = await _runExclusiveWithControl(
      MlOperation.indexing,
      control,
      () => _fetchAndIndexAllImages(mode: mode, control: control),
    );
    if (attempt != MlLockAttempt.ran) {
      _logger.info(
        "fetchAndIndexAllImages denied the ml process lock (${attempt.name})",
      );
    }
    return attempt;
  }

  Future<void> _fetchAndIndexAllImages({
    required MLMode mode,
    required MlRunControl control,
  }) async {
    assert(MlProcessLock.instance.isBusy, "ml funnel must be held");
    if (control.stopRequested) {
      _logRunStopped(control, "before indexing started");
      return;
    }
    if (!_canRunMLFunction(function: "Indexing")) return;

    bool rustRuntimePrepared = false;
    try {
      _logger.info('starting image indexing');
      if (localSettings.isMLLocalIndexingEnabled) {
        await MLModelDownloadService.instance.ensureModelsDownloaded(
          onlyIndexingModels: true,
        );
      }
      final Stream<List<FileMLInstruction>> instructionStream =
          fetchEmbeddingsAndInstructions(fileDownloadMlLimit, mode: mode);

      int fileAnalyzedCount = 0;
      final Stopwatch stopwatch = Stopwatch()..start();

      bool stopRun = false;
      await for (final chunk in instructionStream) {
        if (control.stopRequested) {
          _logRunStopped(control, "between indexing chunks");
          break;
        }
        if (!localSettings.isMLLocalIndexingEnabled) {
          if (rustRuntimePrepared) {
            await MLIndexingIsolate.instance.releaseRustRuntime();
            rustRuntimePrepared = false;
          }
          await MLIndexingIsolate.instance.cleanupLocalIndexingModels();
          continue;
        } else if (!(isLocalGalleryMode || await canUseHighBandwidth())) {
          _logger.info(
            'stopping indexing because user is not connected to wifi and in online mode',
          );
          break;
        } else {
          await MLModelDownloadService.instance.ensureModelsDownloaded(
            onlyIndexingModels: true,
          );
          if (!rustRuntimePrepared) {
            await MLIndexingIsolate.instance.prepareRustRuntime();
            rustRuntimePrepared = true;
          }
        }
        final futures = <Future<bool>>[];
        for (final instruction in chunk) {
          if (control.stopRequested) {
            _logRunStopped(control, "between indexing instructions");
            stopRun = true;
            break;
          }
          futures.add(_processImage(instruction));
        }
        // Drain: work that was already started must complete (and commit)
        // before this run can exit and release the process lock.
        final awaitedFutures = await Future.wait(futures);
        final sumFutures = awaitedFutures.fold<int>(
          0,
          (previousValue, element) => previousValue + (element ? 1 : 0),
        );
        fileAnalyzedCount += sumFutures;
        if (stopRun) {
          break;
        }
      }
      if (fileAnalyzedCount > 0) {
        magicCacheService.queueUpdate('fileIndexed');
      }
      _logger.info(
        "`indexAllImages()` finished. Analyzed $fileAnalyzedCount images, in ${stopwatch.elapsed.inSeconds} seconds (avg of ${stopwatch.elapsed.inSeconds / fileAnalyzedCount} seconds per image)",
      );
      _logStatus();
    } on RustCorruptModelException catch (e) {
      _logger.severe(
        "Stopping image indexing because Rust ML reported a corrupt model at ${e.modelPath}",
      );
    } catch (e, s) {
      _logger.severe("indexAllImages failed", e, s);
    } finally {
      await MLIndexingIsolate.instance.releaseRustRuntime();
      MLModelDownloadService.instance.invalidateModelDownloadCache();
    }
  }

  Future<MlLockAttempt> clusterAllImages({
    bool clusterInBuckets = true,
    bool force = false,
  }) async {
    final control = MlRunControl();
    final attempt = await _runExclusiveWithControl(
      MlOperation.clustering,
      control,
      () => _clusterAllImages(
        clusterInBuckets: clusterInBuckets,
        force: force,
        control: control,
      ),
    );
    if (attempt != MlLockAttempt.ran) {
      _logger.info(
        "clusterAllImages denied the ml process lock (${attempt.name})",
      );
    }
    return attempt;
  }

  Future<void> _clusterAllImages({
    required MlRunControl control,
    bool clusterInBuckets = true,
    bool force = false,
  }) async {
    assert(MlProcessLock.instance.isBusy, "ml funnel must be held");
    if (control.stopRequested) {
      _logRunStopped(control, "before clustering started");
      return;
    }
    if (!_canRunMLFunction(function: "Clustering") && !force) return;
    final mlDataDB = _mlDataDB;
    _logger.info("`clusterAllImages()` called");
    _clusteringIsHappening = true;
    final clusterAllImagesTime = DateTime.now();

    final faceIdNotToCluster = <String, List<String>>{};
    if (!isLocalGalleryMode) {
      _logger.info('Pulling remote feedback before actually clustering');
      await PersonService.instance.sync();
      final persons = await PersonService.instance.getPersons();
      for (final person in persons) {
        if (person.data.rejectedFaceIDs.isNotEmpty) {
          final personClusters = person.data.assigned.map((e) => e.id).toList();
          for (final faceID in person.data.rejectedFaceIDs) {
            faceIdNotToCluster[faceID] = personClusters;
          }
        }
      }
    } else {
      _logger.info("Skipping person metadata in local gallery mode");
    }

    try {
      final int totalFaces = await mlDataDB.getTotalFaceCount();
      final fileIDToCreationTime = isLocalGalleryMode
          ? await _getLocalGalleryFileIdToCreationTime()
          : await FilesDB.instance.getFileIDToCreationTime();
      final startEmbeddingFetch = DateTime.now();
      final result = await mlDataDB.getFaceInfoForClustering(
        maxFaces: totalFaces,
      );
      final Set<int> missingFileIDs = {};
      final allFaceInfoForClustering = <FaceDbInfoForClustering>[];
      for (final faceInfo in result) {
        if (!fileIDToCreationTime.containsKey(faceInfo.fileID)) {
          missingFileIDs.add(faceInfo.fileID);
        } else {
          if (faceIdNotToCluster.containsKey(faceInfo.faceID)) {
            faceInfo.rejectedClusterIds = faceIdNotToCluster[faceInfo.faceID];
          }
          allFaceInfoForClustering.add(faceInfo);
        }
      }
      allFaceInfoForClustering.sort((b, a) {
        return fileIDToCreationTime[a.fileID]!.compareTo(
          fileIDToCreationTime[b.fileID]!,
        );
      });
      _logger.info(
        'Getting and sorting embeddings took ${DateTime.now().difference(startEmbeddingFetch).inMilliseconds} ms for ${allFaceInfoForClustering.length} embeddings'
        'and ${missingFileIDs.length} missing fileIDs',
      );

      final Map<String, (Uint8List, int)> oldClusterSummaries = await mlDataDB
          .getAllClusterSummary();

      if (clusterInBuckets) {
        const int bucketSize = 10000;
        const int offsetIncrement = 7500;
        int offset = 0;
        int bucket = 1;

        while (true) {
          if (control.stopRequested) {
            _logRunStopped(control, "before clustering bucket $bucket");
            break;
          }
          if (offset > allFaceInfoForClustering.length - 1) {
            _logger.warning(
              'faceIdToEmbeddingBucket is empty, this should ideally not happen as it should have stopped earlier. offset: $offset, totalFaces: $totalFaces',
            );
            break;
          }
          if (offset > totalFaces) {
            _logger.warning(
              'offset > totalFaces, this should ideally not happen. offset: $offset, totalFaces: $totalFaces',
            );
            break;
          }

          final bucketStartTime = DateTime.now();
          final faceInfoForClustering = allFaceInfoForClustering.sublist(
            offset,
            min(offset + bucketSize, allFaceInfoForClustering.length),
          );

          if (faceInfoForClustering.every((face) => face.clusterId != null)) {
            _logger.info('Everything in bucket $bucket is already clustered');
            if (offset + bucketSize >= totalFaces) {
              _logger.info('All faces clustered');
              break;
            } else {
              _logger.info('Skipping to next bucket');
              offset += offsetIncrement;
              bucket++;
              continue;
            }
          }

          final clusteringResult = await FaceClusteringService.instance
              .predictLinearIsolate(
                faceInfoForClustering.toSet(),
                fileIDToCreationTime: fileIDToCreationTime,
                offset: offset,
                oldClusterSummaries: oldClusterSummaries,
              );
          if (clusteringResult == null) {
            _logger.warning("faceIdToCluster is null");
            return;
          }

          await mlDataDB.updateFaceIdToClusterId(
            clusteringResult.newFaceIdToCluster,
          );
          await mlDataDB.clusterSummaryUpdate(
            clusteringResult.newClusterSummaries,
          );
          Bus.instance.fire(PeopleChangedEvent());
          for (final faceInfo in faceInfoForClustering) {
            faceInfo.clusterId ??=
                clusteringResult.newFaceIdToCluster[faceInfo.faceID];
          }
          for (final clusterUpdate
              in clusteringResult.newClusterSummaries.entries) {
            oldClusterSummaries[clusterUpdate.key] = clusterUpdate.value;
          }
          _logger.info(
            'Done with clustering ${offset + faceInfoForClustering.length} embeddings (${(100 * (offset + faceInfoForClustering.length) / totalFaces).toStringAsFixed(0)}%) in bucket $bucket, offset: $offset, in ${DateTime.now().difference(bucketStartTime).inSeconds} seconds',
          );
          if (offset + bucketSize >= totalFaces) {
            _logger.info('All faces clustered');
            break;
          }
          offset += offsetIncrement;
          bucket++;
        }
      } else {
        final clusterStartTime = DateTime.now();
        final clusteringResult = await FaceClusteringService.instance
            .predictLinearIsolate(
              allFaceInfoForClustering.toSet(),
              fileIDToCreationTime: fileIDToCreationTime,
              oldClusterSummaries: oldClusterSummaries,
            );
        if (clusteringResult == null) {
          _logger.warning("faceIdToCluster is null");
          return;
        }
        final clusterDoneTime = DateTime.now();
        _logger.info(
          'done with clustering ${allFaceInfoForClustering.length} in ${clusterDoneTime.difference(clusterStartTime).inSeconds} seconds ',
        );

        _logger.info(
          'Updating ${clusteringResult.newFaceIdToCluster.length} FaceIDs with clusterIDs in the DB',
        );
        await mlDataDB.updateFaceIdToClusterId(
          clusteringResult.newFaceIdToCluster,
        );
        await mlDataDB.clusterSummaryUpdate(
          clusteringResult.newClusterSummaries,
        );
        Bus.instance.fire(PeopleChangedEvent());
        _logger.info(
          'Done updating FaceIDs with clusterIDs in the DB, in '
          '${DateTime.now().difference(clusterDoneTime).inSeconds} seconds',
        );
      }
      _logger.info(
        'clusterAllImages() finished, in '
        '${DateTime.now().difference(clusterAllImagesTime).inSeconds} seconds',
      );
    } catch (e, s) {
      _logger.severe("`clusterAllImages` failed", e, s);
    } finally {
      _clusteringIsHappening = false;
    }
  }

  Future<bool> _processImage(FileMLInstruction instruction) async {
    bool actuallyRanML = false;

    final mlDataDB = _dbForMode(instruction.mode);
    String? pathToDeleteAfterMLProcessing;
    // True once result or skip-marker rows are stored, meaning the file
    // won't be retried and its cached download/export can be dropped.
    bool indexedOrSkipped = false;
    try {
      final String filePath = await getImagePathForML(instruction.file);
      if (_shouldDeleteAfterMLProcessing(instruction.file)) {
        pathToDeleteAfterMLProcessing = filePath;
      }

      final MLResult? result = await MLIndexingIsolate.instance.analyzeImage(
        instruction,
        filePath,
      );
      if (result == null) {
        if (!(_activeRunControl?.stopRequested ?? false) &&
            !MLIndexingIsolate.instance.shouldPauseIndexingAndClustering) {
          _logger.severe(
            "Failed to analyze image with fileID: ${instruction.fileKey}",
          );
        }
        return actuallyRanML;
      }
      actuallyRanML = result.ranML;
      if (!actuallyRanML) return actuallyRanML;
      final bool isLocalGallery = instruction.isLocalGallery;
      final FileDataEntity? dataEntity = isLocalGallery
          ? null
          : (instruction.existingRemoteFileML ??
                FileDataEntity.empty(
                  instruction.file.uploadedFileID!,
                  DataType.mlData,
                ));
      final List<Face> faces = [];
      if (result.facesRan) {
        if (result.faces!.isEmpty) {
          faces.add(Face.empty(result.fileId));
        }
        if (result.faces!.isNotEmpty) {
          for (int i = 0; i < result.faces!.length; ++i) {
            faces.add(
              Face.fromFaceResult(
                result.faces![i],
                result.fileId,
                result.decodedImageSize,
              ),
            );
          }
        }
        if (!isLocalGallery) {
          dataEntity!.putFace(
            RemoteFaceEmbedding(
              faces,
              faceMlVersion,
              client: client,
              height: result.decodedImageSize.height,
              width: result.decodedImageSize.width,
              flags: result.remoteFlags,
            ),
          );
        }
      }
      if (result.clipRan) {
        if (!isLocalGallery) {
          dataEntity!.putClip(
            RemoteClipEmbedding(
              result.clip!.embedding,
              version: clipMlVersion,
              client: client,
              flags: result.remoteFlags,
            ),
          );
        }
      }
      if (!isLocalGallery && (result.facesRan || result.clipRan)) {
        await fileDataService.putFileData(instruction.file, dataEntity!);
      }
      if (result.facesRan) await mlDataDB.bulkInsertFaces(faces);
      if (result.clipRan) {
        if (isLocalGallery) {
          await mlDataDB.putClip([
            ClipEmbedding(
              fileID: result.fileId,
              embedding: result.clip!.embedding,
              version: clipMlVersion,
            ),
          ]);
        } else {
          await SemanticSearchService.instance.storeClipImageResult(
            result.clip!,
          );
        }
      }

      // Delete stale pet rows first so re-indexing with fewer detections does
      // not leave old data behind.
      final rustPets = result.petFaces != null || result.petBodies != null;
      if (rustPets) {
        await mlDataDB.deletePetDataForFiles([result.fileId]);
        if (result.petFaces != null && result.petFaces!.isNotEmpty) {
          final dbPetFaces = result.petFaces!.map((pf) {
            return DBPetFace(
              fileId: result.fileId,
              petFaceId: pf.petFaceId,
              detection: jsonEncode(pf.detection.toJson()),
              faceVectorId: null,
              species: pf.species,
              faceScore: pf.detection.score,
              imageHeight: result.decodedImageSize.height,
              imageWidth: result.decodedImageSize.width,
              mlVersion: petMlVersion,
            );
          }).toList();
          await mlDataDB.bulkInsertPetFaces(dbPetFaces);
          await mlDataDB.storePetFaceEmbeddings(dbPetFaces, result.petFaces!);
        } else if (instruction.shouldRunPets) {
          // No pet faces detected; insert empty marker so the file is
          // considered pet-indexed (mirrors Face.empty for human faces).
          await mlDataDB.bulkInsertPetFaces([DBPetFace.empty(result.fileId)]);
        }

        if (result.petBodies != null && result.petBodies!.isNotEmpty) {
          final dbPetBodies = result.petBodies!.map((obj) {
            final detectionObj = FaceDetectionRelative(
              score: obj.score,
              box: [
                obj.boxXyxy[0],
                obj.boxXyxy[1],
                obj.boxXyxy[2],
                obj.boxXyxy[3],
              ],
              allKeypoints: const [],
            );
            return DBPetBody(
              fileId: result.fileId,
              petBodyId: obj.petBodyId,
              detection: jsonEncode(detectionObj.toJson()),
              bodyVectorId: null,
              species: obj.cocoClass == 15 ? 1 : 0,
              score: obj.score,
              imageHeight: result.decodedImageSize.height,
              imageWidth: result.decodedImageSize.width,
              mlVersion: petMlVersion,
            );
          }).toList();
          await mlDataDB.bulkInsertPetBodies(dbPetBodies);
          await mlDataDB.storePetBodyEmbeddings(dbPetBodies, result.petBodies!);
        }
      }
      _logger.info("ML result for fileID ${result.fileId} stored remote+local");
      indexedOrSkipped = true;
      return actuallyRanML;
    } catch (e, s) {
      final String format = instruction.file.displayName.split('.').last;
      final int? size = instruction.file.fileSize;
      final fileType = instruction.file.fileType;
      if (e is RustCorruptModelException) {
        stopActiveRun(MlStopReason.corruptModel);
        _logger.severe(
          "Stopping ML indexing for fileID ${instruction.fileKey} "
          "(format $format, type $fileType, size $size) because Rust ML "
          "reported a corrupt model at ${e.modelPath}",
        );
        rethrow;
      }
      final bool acceptedIssue = isExpectedMlSkipError(e);
      if (acceptedIssue) {
        _logger.warning(
          "Skipping ML indexing for fileID ${instruction.fileKey} (format $format, type $fileType, size $size): ${formatExpectedMlSkipReasonForLogs(e)}",
        );
        final storedMarkers = <String>[];
        if (instruction.shouldRunFaces) {
          await mlDataDB.bulkInsertFaces([
            Face.empty(instruction.fileKey, error: true),
          ]);
          storedMarkers.add("faces");
        }
        if (instruction.shouldRunClip) {
          if (instruction.isLocalGallery) {
            await mlDataDB.putClip([ClipEmbedding.empty(instruction.fileKey)]);
          } else {
            await SemanticSearchService.instance.storeEmptyClipImageResult(
              instruction.file,
            );
          }
          storedMarkers.add("clip");
        }
        if (instruction.shouldRunPets) {
          await mlDataDB.deletePetDataForFiles([instruction.fileKey]);
          await mlDataDB.bulkInsertPetFaces([
            DBPetFace.empty(instruction.fileKey, error: true),
          ]);
          storedMarkers.add("pets");
        }
        _logger.info(
          "Stored empty ML result markers for fileID ${instruction.fileKey}: ${storedMarkers.join(', ')}",
        );
        indexedOrSkipped = true;
        return true;
      }
      _logger.severe(
        "Failed to index file for fileID ${instruction.fileKey} (format $format, type $fileType, size $size). Cleaning up partial results so the file will be automatically retried later.",
        e,
        s,
      );
      // Clean up any pet rows that were already committed before the
      // failure so the file is not treated as fully indexed.
      if (instruction.shouldRunPets) {
        await mlDataDB.deletePetDataForFiles([instruction.fileKey]);
      }
      return false;
    } finally {
      if (indexedOrSkipped) {
        if (pathToDeleteAfterMLProcessing != null) {
          try {
            await File(pathToDeleteAfterMLProcessing).delete();
          } catch (e, s) {
            _logger.warning(
              "Failed to delete origin file exported for ML at $pathToDeleteAfterMLProcessing",
              e,
              s,
            );
          }
        }
        await _evictRemoteCacheAfterMLProcessing(instruction.file);
      }
    }
  }

  bool _shouldDeleteAfterMLProcessing(EnteFile file) {
    return Platform.isIOS &&
        file.fileType != FileType.video &&
        !file.isRemoteOnlyFile;
  }

  bool _shouldEvictRemoteCacheAfterMLProcessing(EnteFile file) {
    return file.isRemoteOnlyFile && file.fileType != FileType.video;
  }

  Future<void> _evictRemoteCacheAfterMLProcessing(EnteFile file) async {
    if (!_shouldEvictRemoteCacheAfterMLProcessing(file)) {
      return;
    }
    try {
      await removeFromDownloadCache(file);
    } catch (e, s) {
      _logger.warning(
        "Failed to evict remote file cached for ML for fileID ${file.uploadedFileID}",
        e,
        s,
      );
    }
  }

  bool _canRunMLFunction({required String function}) {
    if (kDebugMode && Platform.isIOS) {
      return true;
    }
    if (_mlControllerStatus == false) {
      _logger.info(
        "Cannot run $function because MLController does not allow it",
      );
      _logStatus();
      return false;
    }
    if (debugIndexingDisabled) {
      _logger.info(
        "Cannot run $function because debugIndexingDisabled is true",
      );
      _logStatus();
      return false;
    }
    return true;
  }

  Future<Map<int, int>> _getLocalGalleryFileIdToCreationTime() async {
    final files = await SearchService.instance.getAllFilesForSearch();
    final localIdToCreation = <String, int>{};
    for (final file in files) {
      final localId = file.localID;
      final creationTime = file.creationTime;
      if (localId != null && localId.isNotEmpty && creationTime != null) {
        localIdToCreation[localId] = creationTime;
      }
    }
    if (localIdToCreation.isEmpty) return {};
    final localIdToIntId = await OfflineFilesDB.instance
        .getLocalIntIdsForLocalIds(localIdToCreation.keys);
    final map = <int, int>{};
    localIdToIntId.forEach((localId, localIntId) {
      final creationTime = localIdToCreation[localId];
      if (creationTime != null) {
        map[localIntId] = creationTime;
      }
    });
    return map;
  }

  void _logStatus() {
    final String status =
        '''
    isInternalUser: ${flagService.internalUser}
    Local indexing: ${localSettings.isMLLocalIndexingEnabled}
    canRunMLController: $_mlControllerStatus
    activeOperation: ${MlProcessLock.instance.activeOperation?.name}
    stopRequested: ${_activeRunControl?.stopRequested} (reason: ${_activeRunControl?.stopReason?.name})
    debugIndexingDisabled: $debugIndexingDisabled
    ''';
    _logger.info(status);
  }
}
