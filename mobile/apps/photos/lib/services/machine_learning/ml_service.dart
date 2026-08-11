import "dart:async";
import "dart:convert" show jsonEncode;
import "dart:io" show File, Platform;
import "dart:math" show min;
import "dart:typed_data" show Uint8List;

import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/db/offline_files_db.dart";
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
import "package:photos/services/process_activity_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/ml_util.dart";
import "package:photos/utils/network_util.dart";
import "package:photos/utils/ram_check_util.dart";

enum MlRunDisposition { completed, denied, stopped, failed }

class MLService {
  final _logger = Logger("MLService");

  // Singleton pattern
  MLService._privateConstructor();
  static final instance = MLService._privateConstructor();
  factory MLService() => instance;

  bool _isInitialized = false;

  int? lastRemoteFetch;
  static const int _kRemoteFetchCooldownOnLite = 1000 * 60 * 5;
  static const int _kStartupOwnedRemoteHydrationMissingFileThreshold = 200;
  Future<void>? _ownedRemoteHydrationFuture;
  bool _hasScheduledStartupOwnedRemoteHydration = false;

  late String client;

  bool get showClusteringIsHappening => _clusteringIsHappening;

  bool debugIndexingDisabled = false;
  bool _clusteringIsHappening = false;
  bool _mlControllerStatus = false;
  bool _isIndexingOrClusteringRunning = false;
  bool _isRunningML = false;
  bool _shouldPauseIndexingAndClustering = false;
  Timer? _predownloadLocalModelsTimer;
  Timer? _automaticRetryTimer;
  MlRunControl? _activeRunControl;

  static const _kPredownloadLocalModelsDelay = Duration(seconds: 10);
  static const _kPermitRetryInterval = Duration(seconds: 5);
  static const _kPermitRetryTimeout = Duration(seconds: 30);
  static const _kBackgroundForegroundPollInterval = Duration(seconds: 3);

  bool get isRunningML =>
      _isRunningML || memoriesCacheService.isUpdatingMemories;

  static const _kForceClusteringFaceCount = 8000;
  static const _kForceClusteringFaceCountLocalGallery = 100;
  int _forceClusteringFaceCountForMode(MLMode mode) {
    return mode == MLMode.localGallery
        ? _kForceClusteringFaceCountLocalGallery
        : _kForceClusteringFaceCount;
  }

  MLDataDB _dbForMode(MLMode mode) {
    return mode == MLMode.localGallery
        ? MLDataDB.localGalleryInstance
        : MLDataDB.instance;
  }

  bool _hasModeChanged(MLMode mode) {
    return (isLocalGalleryMode ? MLMode.localGallery : MLMode.enteGallery) !=
        mode;
  }

  /// Only call this function once at app startup, after that you can directly call [runAllML]
  Future<void> init() async {
    if (_isInitialized) {
      _schedulePredownloadLocalModels();
      scheduleStartupOwnedRemoteHydration();
      return;
    }
    _logger.info("init called");

    // Check if the device has enough RAM to run local indexing
    await checkDeviceTotalRAM();

    FaceClusteringService.init(localSettings);

    // Get client name
    final packageInfo = ServiceLocator.instance.packageInfo;
    client = "${packageInfo.packageName}/${packageInfo.version}";
    _logger.info("client: $client");

    // Listen on ComputeController
    Bus.instance.on<ComputeControlEvent>().listen((event) {
      if (!hasGrantedMLConsent) {
        if (!isProcessBg && event.shouldRun) {
          VideoPreviewService.instance.queueFiles(duration: Duration.zero);
        }
        return;
      }

      _mlControllerStatus = event.shouldRun;
      if (_mlControllerStatus) {
        if (_shouldPauseIndexingAndClustering) {
          _cancelPauseIndexingAndClustering();
          _logger.info(
            "MLController allowed running ML, faces indexing undoing previous pause",
          );
        } else {
          _logger.info(
            "MLController allowed running ML, faces indexing starting",
          );
        }
        // Background start is driven manually from _runMinimally to avoid
        // duplicate runAllML invocations in the same cycle.
        if (!isProcessBg) {
          unawaited(runAllML());
        }
      } else {
        _logger.info(
          "MLController stopped running ML, faces indexing will be paused (unless it's fetching embeddings)",
        );
        pauseIndexingAndClustering();
      }
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
    final future = _runOwnedRemoteHydrationSafely(
      reason: reason,
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
  }

  Future<void> _runOwnedRemoteHydrationSafely({
    required String reason,
    int? skipHydrationIfCandidateFileCountAtMost,
  }) async {
    MlProcessPermit? permit;
    try {
      final attempt = await MlProcessLock.instance.tryAcquire(
        origin: MlProcessLockOrigin.foreground,
        operation: MlProcessOperation.startupRemoteHydration,
      );
      permit = attempt.permit;
      if (permit == null) {
        _logger.info(
          "Skipping owned remote ML hydration ($reason): another ML operation is active",
        );
        return;
      }
      await permit.run(
        () => _hydrateRemoteEmbeddingsForOwnedFilesInternal(
          reason: reason,
          skipHydrationIfCandidateFileCountAtMost:
              skipHydrationIfCandidateFileCountAtMost,
        ),
      );
    } catch (e, s) {
      _logger.warning("Owned remote ML hydration ($reason) failed", e, s);
    } finally {
      try {
        await permit?.release();
      } catch (e, s) {
        _logger.severe(
          "Failed to release owned remote ML hydration permit",
          e,
          s,
        );
      }
    }
  }

  Future<void> _hydrateRemoteEmbeddingsForOwnedFilesInternal({
    required String reason,
    int? skipHydrationIfCandidateFileCountAtMost,
  }) async {
    final summary = await hydrateOwnedRemoteMLData(
      mlDataDB: MLDataDB.instance,
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
    if (lastRemoteFetch == null) {
      lastRemoteFetch = DateTime.now().millisecondsSinceEpoch;
      return true;
    }
    final intDiff = DateTime.now().millisecondsSinceEpoch - lastRemoteFetch!;
    final bool canFetch = intDiff > _kRemoteFetchCooldownOnLite;
    if (canFetch) {
      lastRemoteFetch = DateTime.now().millisecondsSinceEpoch;
    }
    return canFetch;
  }

  Future<void> sync() async {
    await fileDataService.syncFDStatus();
    await personFeedbackService.syncPersonFeedback();
  }

  Future<MlRunDisposition> runAllML({
    bool force = false,
    MlRunControl? runControl,
  }) {
    return _runAllML(
      force: force,
      runControl: runControl,
      scheduleAutomaticRetry: !force,
    );
  }

  Future<MlRunDisposition> _runAllML({
    required bool force,
    required MlRunControl? runControl,
    required bool scheduleAutomaticRetry,
  }) async {
    if (_isRunningML) {
      _logger.info("runAllML called while already running, skipping");
      return MlRunDisposition.denied;
    }
    final control = runControl ?? MlRunControl();
    if (control.stopRequested) {
      _logger.info(
        "runAllML stopped before starting: ${control.stopReason?.name}",
      );
      return MlRunDisposition.stopped;
    }

    final MLMode mode = isLocalGalleryMode
        ? MLMode.localGallery
        : MLMode.enteGallery;
    bool computeAcquired = false;
    MlProcessPermit? permit;
    void Function()? removeStopListener;
    Timer? foregroundPollTimer;
    bool foregroundPollRunning = false;
    try {
      if (!hasGrantedMLConsent) {
        _logger.info("runAllML called without ML consent, skipping");
        return MlRunDisposition.denied;
      }
      final mlDataDB = _dbForMode(mode);
      if (force) {
        _mlControllerStatus = true;
      }
      if (!_canRunMLFunction(function: "AllML") && !force) {
        return MlRunDisposition.denied;
      }
      if (!force) {
        computeAcquired = computeController.requestCompute(ml: true);
        if (!computeAcquired) return MlRunDisposition.denied;
      }
      final permitResult = await _acquireProcessPermit(
        operation: MlProcessOperation.fullRun,
        waitForExplicitAction: force && !isProcessBg,
        mode: mode,
      );
      permit = permitResult.permit;
      if (permit == null) {
        if (!permitResult.failed &&
            !isProcessBg &&
            scheduleAutomaticRetry &&
            !force) {
          _scheduleAutomaticRetry(mode);
        }
        return permitResult.failed
            ? MlRunDisposition.failed
            : MlRunDisposition.denied;
      }

      return await permit.run(() async {
        _isRunningML = true;
        _activeRunControl = control;
        removeStopListener = control.addStopListener(_onRunStopRequested);
        if (isProcessBg) {
          foregroundPollTimer = Timer.periodic(
            _kBackgroundForegroundPollInterval,
            (_) async {
              if (foregroundPollRunning || control.stopRequested) return;
              foregroundPollRunning = true;
              try {
                if (await ProcessActivityService.instance
                    .isForegroundRecentlyActive()) {
                  control.requestStop(MlStopReason.foregroundActive);
                }
              } catch (e, s) {
                _logger.warning("Failed to poll foreground activity", e, s);
              } finally {
                foregroundPollRunning = false;
              }
            },
          );
        }
        if (control.stopRequested) return MlRunDisposition.stopped;

        await sync();
        if (control.stopRequested) return MlRunDisposition.stopped;
        if (_hasModeChanged(mode)) {
          _logger.info("App mode changed during ML run, stopping");
          control.requestStop(MlStopReason.manual);
          return MlRunDisposition.stopped;
        }

        final int unclusteredFacesCount = await mlDataDB
            .getUnclusteredFaceCount();
        if (!control.stopRequested &&
            unclusteredFacesCount > _forceClusteringFaceCountForMode(mode)) {
          _logger.info(
            "There are $unclusteredFacesCount unclustered faces, doing clustering first",
          );
          await _clusterAllImages(runControl: control, mode: mode);
        }
        if (control.stopRequested) return MlRunDisposition.stopped;
        if (_mlControllerStatus == true) {
          if (_hasModeChanged(mode)) {
            _logger.info("App mode changed during ML run, stopping");
            control.requestStop(MlStopReason.manual);
            return MlRunDisposition.stopped;
          }
          // Refresh discover/memories caches before indexing using the same
          // path in foreground and background runs.
          magicCacheService.updateCache(forced: force).ignore();
          memoriesCacheService.updateCache(forced: force).ignore();
        }
        if (!control.stopRequested && canFetch()) {
          await _fetchAndIndexAllImages(mode: mode, runControl: control);
        }
        if (control.stopRequested) return MlRunDisposition.stopped;
        if (_hasModeChanged(mode)) {
          _logger.info("App mode changed during ML run, stopping");
          control.requestStop(MlStopReason.manual);
          return MlRunDisposition.stopped;
        }
        if ((await mlDataDB.getUnclusteredFaceCount()) > 0) {
          await _clusterAllImages(runControl: control, mode: mode);
        }
        if (control.stopRequested) return MlRunDisposition.stopped;
        if (_mlControllerStatus == true) {
          if (_hasModeChanged(mode)) {
            _logger.info("App mode changed during ML run, stopping");
            control.requestStop(MlStopReason.manual);
            return MlRunDisposition.stopped;
          }
          // Persist refreshed caches after ML so foreground can pick them up
          // on the next resume, even when the work ran headlessly in background.
          magicCacheService.updateCache().ignore();
          memoriesCacheService.updateCache(forced: force).ignore();
        }
        return MlRunDisposition.completed;
      });
    } catch (e, s) {
      _logger.severe("runAllML failed", e, s);
      return MlRunDisposition.failed;
    } finally {
      foregroundPollTimer?.cancel();
      removeStopListener?.call();
      _isRunningML = false;
      if (identical(_activeRunControl, control)) {
        _activeRunControl = null;
        _cancelPauseIndexingAndClustering();
      }
      if (control.stopReason != null) {
        _logger.info(
          "ML drain completed after ${control.stopReason!.name} stop",
        );
      }
      if (permit != null) {
        try {
          await permit.release();
        } catch (e, s) {
          _logger.severe("Failed to release ML process permit", e, s);
        }
      }
      if (computeAcquired) computeController.releaseCompute(ml: true);
      _logger.info("ML finished running");
      if (!isProcessBg &&
          control.stopReason == MlStopReason.controller &&
          _mlControllerStatus &&
          hasGrantedMLConsent) {
        _scheduleAutomaticRetry(mode);
      }
      if (!isProcessBg) {
        VideoPreviewService.instance.queueFiles();
      }
    }
  }

  void triggerML() {
    if (_mlControllerStatus &&
        !_isIndexingOrClusteringRunning &&
        !_isRunningML) {
      unawaited(runAllML());
    }
  }

  Future<({MlProcessPermit? permit, bool failed})> _acquireProcessPermit({
    required MlProcessOperation operation,
    required bool waitForExplicitAction,
    required MLMode mode,
  }) async {
    final token = MlProcessLock.instance.newOperationToken();
    final deadline = DateTime.now().add(_kPermitRetryTimeout);
    while (true) {
      try {
        final attempt = await MlProcessLock.instance.tryAcquire(
          origin: isProcessBg
              ? MlProcessLockOrigin.background
              : MlProcessLockOrigin.foreground,
          operation: operation,
          token: token,
        );
        if (attempt.permit != null) {
          return (permit: attempt.permit, failed: false);
        }
      } catch (_) {
        return (permit: null, failed: true);
      }
      if (!waitForExplicitAction ||
          DateTime.now().add(_kPermitRetryInterval).isAfter(deadline)) {
        if (waitForExplicitAction) {
          _logger.warning(
            "Timed out waiting for ${operation.name} ML process permit",
          );
        }
        return (permit: null, failed: false);
      }
      await Future<void>.delayed(_kPermitRetryInterval);
      if (!hasGrantedMLConsent || _hasModeChanged(mode)) {
        return (permit: null, failed: false);
      }
    }
  }

  void _scheduleAutomaticRetry(MLMode mode) {
    if (_automaticRetryTimer?.isActive == true) return;
    _logger.info("Scheduling one automatic ML retry");
    _automaticRetryTimer = Timer(_kPermitRetryInterval, () {
      _automaticRetryTimer = null;
      if (!hasGrantedMLConsent || isProcessBg || _hasModeChanged(mode)) return;
      unawaited(
        _runAllML(
          force: false,
          runControl: null,
          scheduleAutomaticRetry: false,
        ),
      );
    });
  }

  void _onRunStopRequested(MlStopReason reason) {
    _logger.info("Stopping active ML run and draining: ${reason.name}");
    _shouldPauseIndexingAndClustering = true;
    MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = true;
  }

  void pauseIndexingAndClustering() {
    final activeRunControl = _activeRunControl;
    if (activeRunControl != null) {
      activeRunControl.requestStop(MlStopReason.controller);
    } else if (_isIndexingOrClusteringRunning) {
      _shouldPauseIndexingAndClustering = true;
      MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = true;
    }
  }

  void _cancelPauseIndexingAndClustering() {
    if (_activeRunControl?.stopRequested == true) return;
    _shouldPauseIndexingAndClustering = false;
    MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = false;
  }

  Future<MlRunDisposition> _runDirectOperation({
    required MlProcessOperation operation,
    required MLMode mode,
    required MlRunControl runControl,
    required Future<void> Function() body,
  }) async {
    final permitResult = await _acquireProcessPermit(
      operation: operation,
      waitForExplicitAction: !isProcessBg,
      mode: mode,
    );
    final permit = permitResult.permit;
    if (permit == null) {
      return permitResult.failed
          ? MlRunDisposition.failed
          : MlRunDisposition.denied;
    }

    void Function()? removeStopListener;
    try {
      _activeRunControl = runControl;
      removeStopListener = runControl.addStopListener(_onRunStopRequested);
      if (runControl.stopRequested) return MlRunDisposition.stopped;
      await permit.run(body);
      return runControl.stopRequested
          ? MlRunDisposition.stopped
          : MlRunDisposition.completed;
    } finally {
      removeStopListener?.call();
      if (identical(_activeRunControl, runControl)) {
        _activeRunControl = null;
        _cancelPauseIndexingAndClustering();
      }
      if (runControl.stopReason != null) {
        _logger.info(
          "Direct ML drain completed after ${runControl.stopReason!.name} stop",
        );
      }
      try {
        await permit.release();
      } catch (e, s) {
        _logger.severe("Failed to release direct ML process permit", e, s);
      }
    }
  }

  /// Analyzes all the images in the user library with the latest ml version and stores the results in the database.
  ///
  /// This function first fetches from remote and checks if the image has already been analyzed
  /// with the lastest faceMlVersion and stored on remote or local database. If so, it skips the image.
  Future<MlRunDisposition> fetchAndIndexAllImages({
    required MLMode mode,
  }) async {
    if (!_canRunMLFunction(function: "Indexing")) {
      return MlRunDisposition.denied;
    }
    final control = MlRunControl();
    return _runDirectOperation(
      operation: MlProcessOperation.indexing,
      mode: mode,
      runControl: control,
      body: () => _fetchAndIndexAllImages(mode: mode, runControl: control),
    );
  }

  Future<void> _fetchAndIndexAllImages({
    required MLMode mode,
    required MlRunControl runControl,
  }) async {
    bool rustRuntimePrepared = false;
    try {
      _isIndexingOrClusteringRunning = true;
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

      stream:
      await for (final chunk in instructionStream) {
        if (runControl.stopRequested) {
          _logger.info("Image indexing stopped before starting another chunk");
          break stream;
        }
        if ((isLocalGalleryMode ? MLMode.localGallery : MLMode.enteGallery) !=
            mode) {
          _logger.info(
            "App mode changed during indexing, stopping current ML run",
          );
          break stream;
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
          break stream;
        } else {
          await MLModelDownloadService.instance.ensureModelsDownloaded(
            onlyIndexingModels: true,
          );
          if (!rustRuntimePrepared) {
            await MLIndexingIsolate.instance.prepareRustRuntime();
            rustRuntimePrepared = true;
          }
        }
        if (runControl.stopRequested) {
          _logger.info("Image indexing stopped after preparing the next chunk");
          break stream;
        }
        final futures = <Future<bool>>[];
        bool stopAfterChunk = false;
        for (final instruction in chunk) {
          if ((isLocalGalleryMode ? MLMode.localGallery : MLMode.enteGallery) !=
              mode) {
            _logger.info(
              "App mode changed during indexing, stopping current ML run",
            );
            stopAfterChunk = true;
            break;
          }
          if (runControl.stopRequested || _shouldPauseIndexingAndClustering) {
            _logger.info("indexAllImages() was paused, stopping");
            stopAfterChunk = true;
            break;
          }
          futures.add(processImage(instruction));
        }
        final awaitedFutures = await Future.wait(futures);
        final sumFutures = awaitedFutures.fold<int>(
          0,
          (previousValue, element) => previousValue + (element ? 1 : 0),
        );
        fileAnalyzedCount += sumFutures;
        if (stopAfterChunk || runControl.stopRequested) {
          break stream;
        }
      }
      if (fileAnalyzedCount > 0) {
        magicCacheService.queueUpdate('fileIndexed');
      }
      _logger.info(
        "`indexAllImages()` finished. Analyzed $fileAnalyzedCount images, in ${stopwatch.elapsed.inSeconds} seconds",
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
      _isIndexingOrClusteringRunning = false;
    }
  }

  Future<MlRunDisposition> clusterAllImages({
    bool clusterInBuckets = true,
    bool force = false,
  }) async {
    if (!_canRunMLFunction(function: "Clustering") && !force) {
      return MlRunDisposition.denied;
    }
    final mode = isLocalGalleryMode ? MLMode.localGallery : MLMode.enteGallery;
    final control = MlRunControl();
    return _runDirectOperation(
      operation: MlProcessOperation.clustering,
      mode: mode,
      runControl: control,
      body: () => _clusterAllImages(
        runControl: control,
        mode: mode,
        clusterInBuckets: clusterInBuckets,
      ),
    );
  }

  Future<void> _clusterAllImages({
    required MlRunControl runControl,
    required MLMode mode,
    bool clusterInBuckets = true,
  }) async {
    if (_clusteringIsHappening) {
      _logger.info("clusterAllImages() is already running, returning");
      return;
    }

    _logger.info("`clusterAllImages()` called");
    _isIndexingOrClusteringRunning = true;
    _clusteringIsHappening = true;
    final clusterAllImagesTime = DateTime.now();
    final mlDataDB = _dbForMode(mode);

    try {
      if (runControl.stopRequested || _hasModeChanged(mode)) return;
      final faceIdNotToCluster = <String, List<String>>{};
      if (mode == MLMode.enteGallery) {
        _logger.info('Pulling remote feedback before actually clustering');
        await PersonService.instance.fetchRemoteClusterFeedback();
        if (runControl.stopRequested || _hasModeChanged(mode)) return;
        final persons = await PersonService.instance.getPersons();
        for (final person in persons) {
          if (person.data.rejectedFaceIDs.isNotEmpty) {
            final personClusters = person.data.assigned
                .map((e) => e.id)
                .toList();
            for (final faceID in person.data.rejectedFaceIDs) {
              faceIdNotToCluster[faceID] = personClusters;
            }
          }
        }
      } else {
        _logger.info("Skipping person metadata in local gallery mode");
      }
      // Get a sense of the total number of faces in the database
      final int totalFaces = await mlDataDB.getTotalFaceCount();
      if (runControl.stopRequested || _hasModeChanged(mode)) return;
      final fileIDToCreationTime = mode == MLMode.localGallery
          ? await _getLocalGalleryFileIdToCreationTime()
          : await FilesDB.instance.getFileIDToCreationTime();
      final startEmbeddingFetch = DateTime.now();
      // read all embeddings
      final result = await mlDataDB.getFaceInfoForClustering(
        maxFaces: totalFaces,
      );
      if (runControl.stopRequested || _hasModeChanged(mode)) return;
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
      // sort the embeddings based on file creation time, newest first
      allFaceInfoForClustering.sort((b, a) {
        return fileIDToCreationTime[a.fileID]!.compareTo(
          fileIDToCreationTime[b.fileID]!,
        );
      });
      _logger.info(
        'Getting and sorting embeddings took ${DateTime.now().difference(startEmbeddingFetch).inMilliseconds} ms for ${allFaceInfoForClustering.length} embeddings'
        'and ${missingFileIDs.length} missing fileIDs',
      );

      // Get the current cluster statistics
      final Map<String, (Uint8List, int)> oldClusterSummaries = await mlDataDB
          .getAllClusterSummary();
      if (runControl.stopRequested || _hasModeChanged(mode)) return;

      if (clusterInBuckets) {
        const int bucketSize = 10000;
        const int offsetIncrement = 7500;
        int offset = 0;
        int bucket = 1;

        while (true) {
          if (runControl.stopRequested ||
              _shouldPauseIndexingAndClustering ||
              _hasModeChanged(mode)) {
            _logger.info(
              "MLController does not allow running ML, stopping before clustering bucket $bucket",
            );
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
          if (runControl.stopRequested || _hasModeChanged(mode)) {
            _logger.info(
              "Discarding clustering bucket $bucket because the run stopped",
            );
            break;
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
        // Cluster the embeddings using the linear clustering algorithm, returning a map from faceID to clusterID
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
        if (runControl.stopRequested || _hasModeChanged(mode)) {
          _logger.info("Discarding clustering result because the run stopped");
          return;
        }
        final clusterDoneTime = DateTime.now();
        _logger.info(
          'done with clustering ${allFaceInfoForClustering.length} in ${clusterDoneTime.difference(clusterStartTime).inSeconds} seconds ',
        );

        // Store the updated clusterIDs in the database
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
      _isIndexingOrClusteringRunning = false;
    }
  }

  Future<bool> processImage(FileMLInstruction instruction) async {
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
      // Check if there's no result simply because MLController paused indexing
      if (result == null) {
        if (!_shouldPauseIndexingAndClustering &&
            !MLIndexingIsolate.instance.shouldPauseIndexingAndClustering) {
          _logger.severe(
            "Failed to analyze image with fileID: ${instruction.fileKey}",
          );
        }
        return actuallyRanML;
      }
      // Check anything actually ran
      actuallyRanML = result.ranML;
      if (!actuallyRanML) return actuallyRanML;
      final bool isLocalGallery = instruction.isLocalGallery;
      // Prepare storing data on remote (online mode only)
      final FileDataEntity? dataEntity = isLocalGallery
          ? null
          : (instruction.existingRemoteFileML ??
                FileDataEntity.empty(
                  instruction.file.uploadedFileID!,
                  DataType.mlData,
                ));
      // Faces results
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
      // Clip results
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
        // Storing results on remote
        await fileDataService.putFileData(instruction.file, dataEntity!);
      }
      // Storing results locally
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

      // Pet results locally — delete stale rows before writing so
      // re-indexing with fewer detections doesn't leave old data behind.
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
        pauseIndexingAndClustering();
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
    if (kDebugMode && Platform.isIOS && !_isIndexingOrClusteringRunning) {
      return true;
    }
    if (_isIndexingOrClusteringRunning) {
      _logger.info(
        "Cannot run $function because indexing or clustering is already running",
      );
      _logStatus();
      return false;
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
    if (_shouldPauseIndexingAndClustering) {
      // This should ideally not be triggered, because one of the above should be triggered instead.
      _logger.warning(
        "Cannot run $function because indexing and clustering is being paused",
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
    isIndexingOrClusteringRunning: $_isIndexingOrClusteringRunning
    shouldPauseIndexingAndClustering: $_shouldPauseIndexingAndClustering
    debugIndexingDisabled: $debugIndexingDisabled
    ''';
    _logger.info(status);
  }
}
