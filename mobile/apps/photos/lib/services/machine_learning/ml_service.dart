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
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:photos/utils/ml_util.dart";
import "package:photos/utils/network_util.dart";
import "package:photos/utils/ram_check_util.dart";

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

  static const _kPredownloadLocalModelsDelay = Duration(seconds: 10);

  bool get isRunningML =>
      _isRunningML || memoriesCacheService.isUpdatingMemories;

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
    try {
      await _hydrateRemoteEmbeddingsForOwnedFilesInternal(
        reason: reason,
        skipHydrationIfCandidateFileCountAtMost:
            skipHydrationIfCandidateFileCountAtMost,
      );
    } catch (e, s) {
      _logger.warning("Owned remote ML hydration ($reason) failed", e, s);
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

  Future<void> _waitForOwnedRemoteHydrationIfRunning() async {
    final existing = _ownedRemoteHydrationFuture;
    if (existing == null) {
      return;
    }
    _logger.info(
      "Waiting for owned remote ML hydration to finish before indexing",
    );
    try {
      await existing;
    } catch (e, s) {
      _logger.warning(
        "Owned remote ML hydration failed while indexing was waiting, continuing",
        e,
        s,
      );
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

  Future<void> runAllML({bool force = false}) async {
    if (_isRunningML) {
      _logger.info("runAllML called while already running, skipping");
      return;
    }
    try {
      final MLMode mode = isLocalGalleryMode
          ? MLMode.localGallery
          : MLMode.enteGallery;
      final mlDataDB = _dbForMode(mode);
      if (force) {
        _mlControllerStatus = true;
      }
      if (!_canRunMLFunction(function: "AllML") && !force) return;
      if (!force && !computeController.requestCompute(ml: true)) return;
      _isRunningML = true;
      await sync();
      if (_hasModeChanged(mode)) {
        _logger.info("App mode changed during ML run, stopping");
        return;
      }

      final int unclusteredFacesCount = await mlDataDB
          .getUnclusteredFaceCount();
      if (unclusteredFacesCount > _forceClusteringFaceCountForMode(mode)) {
        _logger.info(
          "There are $unclusteredFacesCount unclustered faces, doing clustering first",
        );
        await clusterAllImages();
      }
      if (_mlControllerStatus == true) {
        if (_hasModeChanged(mode)) {
          _logger.info("App mode changed during ML run, stopping");
          return;
        }
        // Refresh discover/memories caches before indexing using the same
        // path in foreground and background runs.
        magicCacheService.updateCache(forced: force).ignore();
        memoriesCacheService.updateCache(forced: force).ignore();
      }
      if (canFetch()) {
        await fetchAndIndexAllImages(mode: mode);
      }
      if (_hasModeChanged(mode)) {
        _logger.info("App mode changed during ML run, stopping");
        return;
      }
      if ((await mlDataDB.getUnclusteredFaceCount()) > 0) {
        await clusterAllImages();
      }
      if (_mlControllerStatus == true) {
        if (_hasModeChanged(mode)) {
          _logger.info("App mode changed during ML run, stopping");
          return;
        }
        // Persist refreshed caches after ML so foreground can pick them up
        // on the next resume, even when the work ran headlessly in background.
        magicCacheService.updateCache().ignore();
        memoriesCacheService.updateCache(forced: force).ignore();
      }
    } catch (e, s) {
      _logger.severe("runAllML failed", e, s);
      rethrow;
    } finally {
      _logger.info("ML finished running");
      _isRunningML = false;
      computeController.releaseCompute(ml: true);
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

  void pauseIndexingAndClustering() {
    if (_isIndexingOrClusteringRunning) {
      _shouldPauseIndexingAndClustering = true;
      MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = true;
    }
  }

  void _cancelPauseIndexingAndClustering() {
    _shouldPauseIndexingAndClustering = false;
    MLIndexingIsolate.instance.shouldPauseIndexingAndClustering = false;
  }

  /// Analyzes all the images in the user library with the latest ml version and stores the results in the database.
  ///
  /// This function first fetches from remote and checks if the image has already been analyzed
  /// with the lastest faceMlVersion and stored on remote or local database. If so, it skips the image.
  Future<void> fetchAndIndexAllImages({required MLMode mode}) async {
    if (!_canRunMLFunction(function: "Indexing")) return;
    if (mode == MLMode.enteGallery && !isLocalGalleryMode) {
      await _waitForOwnedRemoteHydrationIfRunning();
    }
    if (!_canRunMLFunction(function: "Indexing")) return;

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
        final futures = <Future<bool>>[];
        for (final instruction in chunk) {
          if ((isLocalGalleryMode ? MLMode.localGallery : MLMode.enteGallery) !=
              mode) {
            _logger.info(
              "App mode changed during indexing, stopping current ML run",
            );
            break stream;
          }
          if (_shouldPauseIndexingAndClustering) {
            _logger.info("indexAllImages() was paused, stopping");
            break stream;
          }
          futures.add(processImage(instruction));
        }
        final awaitedFutures = await Future.wait(futures);
        final sumFutures = awaitedFutures.fold<int>(
          0,
          (previousValue, element) => previousValue + (element ? 1 : 0),
        );
        fileAnalyzedCount += sumFutures;
      }
      if (fileAnalyzedCount > 0) {
        magicCacheService.queueUpdate('fileIndexed');
      }
      _logger.info(
        "`indexAllImages()` finished. Analyzed $fileAnalyzedCount images, in ${stopwatch.elapsed.inSeconds} seconds (avg of ${stopwatch.elapsed.inSeconds / fileAnalyzedCount} seconds per image)",
      );
      _logStatus();
    } on RustCorruptModelCacheDeletedException catch (e) {
      _logger.warning(
        "Stopping image indexing because corrupt Rust ONNX model cache was deleted at ${e.modelPath}",
      );
    } catch (e, s) {
      _logger.severe("indexAllImages failed", e, s);
    } finally {
      await MLIndexingIsolate.instance.releaseRustRuntime();
      MLModelDownloadService.instance.invalidateModelDownloadCache();
      _isIndexingOrClusteringRunning = false;
      _cancelPauseIndexingAndClustering();
    }
  }

  Future<void> clusterAllImages({
    bool clusterInBuckets = true,
    bool force = false,
  }) async {
    if (!_canRunMLFunction(function: "Clustering") && !force) return;
    if (_clusteringIsHappening) {
      _logger.info("clusterAllImages() is already running, returning");
      return;
    }

    _logger.info("`clusterAllImages()` called");
    _isIndexingOrClusteringRunning = true;
    _clusteringIsHappening = true;
    final clusterAllImagesTime = DateTime.now();

    final faceIdNotToCluster = <String, List<String>>{};
    if (!isLocalGalleryMode) {
      _logger.info('Pulling remote feedback before actually clustering');
      await PersonService.instance.fetchRemoteClusterFeedback();
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
      // Get a sense of the total number of faces in the database
      final int totalFaces = await _mlDataDB.getTotalFaceCount();
      final fileIDToCreationTime = isLocalGalleryMode
          ? await _getLocalGalleryFileIdToCreationTime()
          : await FilesDB.instance.getFileIDToCreationTime();
      final startEmbeddingFetch = DateTime.now();
      // read all embeddings
      final result = await _mlDataDB.getFaceInfoForClustering(
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
      final Map<String, (Uint8List, int)> oldClusterSummaries = await _mlDataDB
          .getAllClusterSummary();

      if (clusterInBuckets) {
        const int bucketSize = 10000;
        const int offsetIncrement = 7500;
        int offset = 0;
        int bucket = 1;

        while (true) {
          if (_shouldPauseIndexingAndClustering) {
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

          await _mlDataDB.updateFaceIdToClusterId(
            clusteringResult.newFaceIdToCluster,
          );
          await _mlDataDB.clusterSummaryUpdate(
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
        final clusterDoneTime = DateTime.now();
        _logger.info(
          'done with clustering ${allFaceInfoForClustering.length} in ${clusterDoneTime.difference(clusterStartTime).inSeconds} seconds ',
        );

        // Store the updated clusterIDs in the database
        _logger.info(
          'Updating ${clusteringResult.newFaceIdToCluster.length} FaceIDs with clusterIDs in the DB',
        );
        await _mlDataDB.updateFaceIdToClusterId(
          clusteringResult.newFaceIdToCluster,
        );
        await _mlDataDB.clusterSummaryUpdate(
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
      _cancelPauseIndexingAndClustering();
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
      if (e is RustCorruptModelCacheDeletedException) {
        pauseIndexingAndClustering();
        _logger.warning(
          "Stopping ML indexing for fileID ${instruction.fileKey} "
          "(format $format, type $fileType, size $size) because corrupt Rust "
          "ONNX model cache was deleted at ${e.modelPath}",
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
