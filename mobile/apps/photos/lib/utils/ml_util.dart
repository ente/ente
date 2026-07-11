import "dart:io" show Directory, File, Platform;
import "dart:math" as math show sqrt, min, max;

import "package:dio/dio.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/services.dart" show PlatformException;
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/filedata.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/dimension.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/ml_typedefs.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/filedata/model/response.dart";
import "package:photos/services/machine_learning/face_ml/face_alignment/alignment_result.dart";
import "package:photos/services/machine_learning/face_ml/face_detection/detection.dart";
import "package:photos/services/machine_learning/face_ml/face_recognition_service.dart";
import "package:photos/services/machine_learning/ml_exceptions.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/src/rust/api/ml_indexing_api.dart" as rust_ml;
import "package:photos/utils/image_ml_util.dart";
import "package:photos/utils/network_util.dart";

final _logger = Logger("MlUtil");
const _kMlStaleCleanupMaxIds = 5;

enum FileDataForML { thumbnailData, fileData }

enum MLMode { enteGallery, localGallery }

class IndexStatus {
  final int indexedItems, pendingItems;
  final bool? hasWifiEnabled;

  IndexStatus(this.indexedItems, this.pendingItems, [this.hasWifiEnabled]);
}

class FileMLInstruction {
  final EnteFile file;
  final MLMode mode;
  final int? localGalleryFileKey;
  bool shouldRunFaces;
  bool shouldRunClip;
  bool shouldRunPets;
  FileDataEntity? existingRemoteFileML;

  FileMLInstruction({
    required this.file,
    required this.mode,
    this.localGalleryFileKey,
    required this.shouldRunFaces,
    required this.shouldRunClip,
    this.shouldRunPets = false,
  });
  bool get pendingML => shouldRunFaces || shouldRunClip || shouldRunPets;
  bool get isLocalGallery => mode == MLMode.localGallery;
  int get fileKey =>
      isLocalGallery ? localGalleryFileKey! : file.uploadedFileID!;
}

class RemoteMLHydrationSummary {
  final int candidateFiles;
  final int hydratedFaces;
  final int hydratedClips;
  final int remainingLocalMl;
  final bool skippedDueToCandidateThreshold;

  const RemoteMLHydrationSummary({
    this.candidateFiles = 0,
    this.hydratedFaces = 0,
    this.hydratedClips = 0,
    this.remainingLocalMl = 0,
    this.skippedDueToCandidateThreshold = false,
  });
}

class _OnlineMLIndexingCandidates {
  final List<FileMLInstruction> matched;
  final List<FileMLInstruction> unmatched;

  const _OnlineMLIndexingCandidates({
    required this.matched,
    required this.unmatched,
  });
}

Future<IndexStatus> getIndexStatus() async {
  try {
    final MLMode mode = isLocalGalleryMode
        ? MLMode.localGallery
        : MLMode.enteGallery;
    final mlDataDB = mode == MLMode.localGallery
        ? MLDataDB.localGalleryInstance
        : MLDataDB.instance;
    final int indexableFiles = await _getIndexableFileCount(mode: mode);
    final int facesIndexedFiles = await mlDataDB.getFaceIndexedFileCount();
    final int clipIndexedFiles = await mlDataDB.getClipIndexedFileCount();
    int indexedFiles = math.min(facesIndexedFiles, clipIndexedFiles);
    if (flagService.petEnabled &&
        localSettings.petRecognitionEnabled &&
        localSettings.isMLLocalIndexingEnabled &&
        (flagService.useRustForML || isLocalGalleryMode)) {
      final int petIndexedFiles = await mlDataDB.getPetIndexedFileCount();
      indexedFiles = math.min(indexedFiles, petIndexedFiles);
    }

    final showIndexedFiles = math.min(indexedFiles, indexableFiles);
    final showPendingFiles = math.max(indexableFiles - indexedFiles, 0);
    final hasWifiEnabled = await canUseHighBandwidth();
    _logger.info(
      "Shown IndexStatus: indexedFiles: $showIndexedFiles, pendingFiles: $showPendingFiles, hasWifiEnabled: $hasWifiEnabled, ifOffline: $isLocalGalleryMode. Real values: indexedFiles: $indexedFiles (faces: $facesIndexedFiles, clip: $clipIndexedFiles), indexableFiles: $indexableFiles",
    );
    return IndexStatus(showIndexedFiles, showPendingFiles, hasWifiEnabled);
  } catch (e, s) {
    _logger.severe('Error getting ML status', e, s);
    rethrow;
  }
}

// _lastFetchTimeForOthersIndexed indicates the last time we tried to
// fetch embeddings for files that are owned by others. This is only used
// when local indexing is disabled.
int _lastFetchTimeForOthersIndexed = 0;

Future<_OnlineMLIndexingCandidates>
_getOnlineFilesForMlIndexingCandidates() async {
  final mlDataDB = MLDataDB.instance;
  final time = DateTime.now();
  // Get indexed fileIDs for each ML service
  final Map<int, int> faceIndexedFileIDs = await mlDataDB.faceIndexedFileIds();
  final Map<int, int> clipIndexedFileIDs = await mlDataDB
      .clipIndexedFileWithVersion();
  final bool petEnabled =
      flagService.petEnabled &&
      localSettings.petRecognitionEnabled &&
      localSettings.isMLLocalIndexingEnabled &&
      (flagService.useRustForML || isLocalGalleryMode);
  final Map<int, int> petIndexedFileIDs = petEnabled
      ? await mlDataDB.petIndexedFileIds()
      : const {};
  final Set<int> queuedFiledIDs = {};

  final Set<int> filesWithFDStatus = await mlDataDB.getFileIDsWithFDData(
    type: DataType.mlData,
  );

  // Get all regular files and all hidden files
  final enteFiles = await SearchService.instance.getAllFilesForSearch();
  final hiddenFiles = await SearchService.instance.getHiddenFiles();

  // Sort out what should be indexed and in what order
  final List<FileMLInstruction> filesWithLocalID = [];
  final List<FileMLInstruction> filesWithoutLocalID = [];
  final List<FileMLInstruction> hiddenFilesToIndex = [];
  for (final EnteFile enteFile in enteFiles) {
    if (enteFile.skipIndex) {
      continue;
    }
    if (enteFile.uploadedFileID == null || enteFile.uploadedFileID == -1) {
      continue;
    }
    if (queuedFiledIDs.contains(enteFile.uploadedFileID)) {
      continue;
    }
    queuedFiledIDs.add(enteFile.uploadedFileID!);

    final shouldRunFaces = _shouldRunIndexing(
      enteFile,
      faceIndexedFileIDs,
      faceMlVersion,
    );
    final shouldRunClip = _shouldRunIndexing(
      enteFile,
      clipIndexedFileIDs,
      clipMlVersion,
    );
    final shouldRunPets =
        petEnabled &&
        _shouldRunIndexing(enteFile, petIndexedFileIDs, petMlVersion);
    if (!shouldRunFaces && !shouldRunClip && !shouldRunPets) {
      continue;
    }
    final instruction = FileMLInstruction(
      file: enteFile,
      mode: MLMode.enteGallery,
      shouldRunFaces: shouldRunFaces,
      shouldRunClip: shouldRunClip,
      shouldRunPets: shouldRunPets,
    );
    if ((enteFile.localID ?? '').isEmpty) {
      filesWithoutLocalID.add(instruction);
    } else {
      filesWithLocalID.add(instruction);
    }
  }
  for (final EnteFile enteFile in hiddenFiles) {
    if (enteFile.skipIndex) {
      continue;
    }
    if (enteFile.uploadedFileID == null || enteFile.uploadedFileID == -1) {
      continue;
    }
    if (queuedFiledIDs.contains(enteFile.uploadedFileID)) {
      continue;
    }
    queuedFiledIDs.add(enteFile.uploadedFileID!);
    final shouldRunFaces = _shouldRunIndexing(
      enteFile,
      faceIndexedFileIDs,
      faceMlVersion,
    );
    final shouldRunClip = _shouldRunIndexing(
      enteFile,
      clipIndexedFileIDs,
      clipMlVersion,
    );
    final shouldRunPets =
        petEnabled &&
        _shouldRunIndexing(enteFile, petIndexedFileIDs, petMlVersion);
    if (!shouldRunFaces && !shouldRunClip && !shouldRunPets) {
      continue;
    }
    hiddenFilesToIndex.add(
      FileMLInstruction(
        file: enteFile,
        mode: MLMode.enteGallery,
        shouldRunFaces: shouldRunFaces,
        shouldRunClip: shouldRunClip,
        shouldRunPets: shouldRunPets,
      ),
    );
  }
  final sortedBylocalID = <FileMLInstruction>[
    ...filesWithLocalID,
    ...filesWithoutLocalID,
    ...hiddenFilesToIndex,
  ];
  final splitResult = sortedBylocalID.splitMatch(
    (i) => filesWithFDStatus.contains(i.file.uploadedFileID!),
  );

  _logger.info(
    "Getting list of  ${sortedBylocalID.length} files to index for ML took ${DateTime.now().difference(time).inMilliseconds} ms",
  );
  return _OnlineMLIndexingCandidates(
    matched: splitResult.matched,
    unmatched: splitResult.unmatched,
  );
}

/// Return a list of file instructions for files that should be indexed for ML
Future<List<FileMLInstruction>> getFilesForMlIndexing() async {
  _logger.info('getFilesForMlIndexing called');
  final candidateSplit = await _getOnlineFilesForMlIndexingCandidates();
  if (!localSettings.isMLLocalIndexingEnabled) {
    final time = DateTime.now().millisecondsSinceEpoch;
    if ((time - _lastFetchTimeForOthersIndexed) > 1000 * 60 * 60 * 24) {
      final filesOwnedByOthers = [];
      for (final instruction in candidateSplit.unmatched) {
        if (instruction.file.isUploaded && !instruction.file.isOwner) {
          filesOwnedByOthers.add(instruction);
        }
      }
      if (filesOwnedByOthers.isNotEmpty) {
        _lastFetchTimeForOthersIndexed = time;
      }
      _logger.info(
        'Checking index for ${filesOwnedByOthers.length} owned by others',
      );
      return [...candidateSplit.matched, ...filesOwnedByOthers];
    }
    return candidateSplit.matched;
  }
  return [...candidateSplit.matched, ...candidateSplit.unmatched];
}

Future<List<FileMLInstruction>> getLocalGalleryFilesForMlIndexing() async {
  _logger.info('getLocalGalleryFilesForMlIndexing called');
  final mlDataDB = MLDataDB.localGalleryInstance;
  final Map<int, int> faceIndexedFileIDs = await mlDataDB.faceIndexedFileIds();
  final Map<int, int> clipIndexedFileIDs = await mlDataDB
      .clipIndexedFileWithVersion();
  final bool petEnabled =
      flagService.petEnabled &&
      localSettings.petRecognitionEnabled &&
      (flagService.useRustForML || isLocalGalleryMode);
  final Map<int, int> petIndexedFileIDs = petEnabled
      ? await mlDataDB.petIndexedFileIds()
      : const {};
  final Set<int> queuedFileIDs = {};

  final enteFiles = await SearchService.instance.getAllFilesForSearch();
  final candidateFiles = <EnteFile>[];
  final localIds = <String>[];
  final List<FileMLInstruction> instructions = [];

  for (final EnteFile enteFile in enteFiles) {
    if (enteFile.fileType == FileType.other) {
      continue;
    }
    if ((enteFile.localID ?? '').isEmpty ||
        (enteFile.uploadedFileID != null && enteFile.uploadedFileID != -1)) {
      continue;
    }
    final localID = enteFile.localID!;
    candidateFiles.add(enteFile);
    localIds.add(localID);
  }

  final localIdToIntId = await OfflineFilesDB.instance.ensureLocalIntIds(
    localIds,
  );

  for (final enteFile in candidateFiles) {
    final localID = enteFile.localID!;
    final localIntId = localIdToIntId[localID];
    if (localIntId == null) {
      continue;
    }
    if (queuedFileIDs.contains(localIntId)) {
      continue;
    }
    queuedFileIDs.add(localIntId);
    final shouldRunFaces = _shouldRunIndexingWithFileId(
      localIntId,
      faceIndexedFileIDs,
      faceMlVersion,
    );
    final shouldRunClip = _shouldRunIndexingWithFileId(
      localIntId,
      clipIndexedFileIDs,
      clipMlVersion,
    );
    final shouldRunPets =
        petEnabled &&
        _shouldRunIndexingWithFileId(
          localIntId,
          petIndexedFileIDs,
          petMlVersion,
        );
    if (!shouldRunFaces && !shouldRunClip && !shouldRunPets) {
      continue;
    }
    instructions.add(
      FileMLInstruction(
        file: enteFile,
        mode: MLMode.localGallery,
        localGalleryFileKey: localIntId,
        shouldRunFaces: shouldRunFaces,
        shouldRunClip: shouldRunClip,
        shouldRunPets: shouldRunPets,
      ),
    );
  }
  _logger.info(
    "Getting list of ${instructions.length} files to index for offline ML",
  );
  return instructions;
}

Stream<List<FileMLInstruction>> fetchEmbeddingsAndInstructions(
  int yieldSize, {
  required MLMode mode,
}) async* {
  if (mode == MLMode.localGallery) {
    final List<FileMLInstruction> filesToIndex =
        await getLocalGalleryFilesForMlIndexing();
    final List<List<FileMLInstruction>> chunks = filesToIndex.chunks(yieldSize);
    for (final batch in chunks) {
      yield batch;
    }
    return;
  }
  final mlDataDB = MLDataDB.instance;
  final List<FileMLInstruction> filesToIndex = await getFilesForMlIndexing();
  final List<List<FileMLInstruction>> chunks = filesToIndex.chunks(
    embeddingFetchLimit,
  );
  List<FileMLInstruction> batchToYield = [];

  for (final chunk in chunks) {
    if (!localSettings.remoteFetchEnabled) {
      _logger.warning("remoteFetchEnabled is false, skiping embedding fetch");
      final batches = chunk.chunks(yieldSize);
      for (final batch in batches) {
        yield batch;
      }
      continue;
    }
    final pendingInstructions = await hydrateRemoteMLDataForInstructions(
      chunk,
      mlDataDB: mlDataDB,
    );
    for (final instruction in pendingInstructions) {
      if (instruction.pendingML) {
        batchToYield.add(instruction);
        if (batchToYield.length == yieldSize) {
          _logger.info("queueing indexing for  $yieldSize");
          yield batchToYield;
          batchToYield = [];
        }
      }
    }
  }
  // Yield any remaining instructions
  if (batchToYield.isNotEmpty) {
    _logger.info("queueing indexing for  ${batchToYield.length}");
    yield batchToYield;
  }
}

Future<RemoteMLHydrationSummary> hydrateOwnedRemoteMLData({
  required MLDataDB mlDataDB,
  int? skipHydrationIfCandidateFileCountAtMost,
}) async {
  final candidateSplit = await _getOnlineFilesForMlIndexingCandidates();
  final ownedCandidates = candidateSplit.matched.where((instruction) {
    return instruction.file.isOwner &&
        (instruction.shouldRunFaces || instruction.shouldRunClip);
  }).toList();
  if (ownedCandidates.isEmpty) {
    return const RemoteMLHydrationSummary();
  }
  if (skipHydrationIfCandidateFileCountAtMost != null &&
      ownedCandidates.length <= skipHydrationIfCandidateFileCountAtMost) {
    return RemoteMLHydrationSummary(
      candidateFiles: ownedCandidates.length,
      remainingLocalMl: ownedCandidates.length,
      skippedDueToCandidateThreshold: true,
    );
  }

  int hydratedFaces = 0;
  int hydratedClips = 0;
  int remainingLocalMl = 0;
  for (
    int start = 0;
    start < ownedCandidates.length;
    start += embeddingFetchLimit
  ) {
    final end = math.min(start + embeddingFetchLimit, ownedCandidates.length);
    final chunk = ownedCandidates.sublist(start, end);
    final facePendingBefore = chunk.where((i) => i.shouldRunFaces).length;
    final clipPendingBefore = chunk.where((i) => i.shouldRunClip).length;
    final pendingAfterHydration = await hydrateRemoteMLDataForInstructions(
      chunk,
      mlDataDB: mlDataDB,
    );
    hydratedFaces +=
        facePendingBefore -
        pendingAfterHydration.where((i) => i.shouldRunFaces).length;
    hydratedClips +=
        clipPendingBefore -
        pendingAfterHydration.where((i) => i.shouldRunClip).length;
    remainingLocalMl += pendingAfterHydration.length;
  }

  return RemoteMLHydrationSummary(
    candidateFiles: ownedCandidates.length,
    hydratedFaces: hydratedFaces,
    hydratedClips: hydratedClips,
    remainingLocalMl: remainingLocalMl,
  );
}

bool _isRecoverableMlFetchForbidden(Object error) =>
    error is DioException &&
    error.type == DioExceptionType.badResponse &&
    error.response?.statusCode == 403;

Future<FileDataResponse> _fetchFilesDataForMlHydrationWithRecovery(
  Map<int, FileMLInstruction> pendingIndex,
) async {
  final batchIds = pendingIndex.keys.toSet();
  try {
    return await fileDataService.getFilesData(batchIds);
  } catch (e) {
    if (!_isRecoverableMlFetchForbidden(e)) rethrow;

    await CollectionsService.instance.sync();
    final suspects = <int>{};
    for (final id in batchIds) {
      final collectionIds = await FilesDB.instance.getAllCollectionIDsOfFile(
        id,
      );
      final hasAccess = collectionIds.any((cid) {
        final c = CollectionsService.instance.getCollectionByID(cid);
        return c != null && !c.isDeleted;
      });
      if (!hasAccess) suspects.add(id);
    }
    _logger.info(
      "ML stale recovery: ${suspects.length}/${batchIds.length} suspects",
    );
    if (suspects.isEmpty) rethrow;
    if (suspects.length > _kMlStaleCleanupMaxIds) {
      _logger.severe(
        "ML stale recovery aborted: ${suspects.length} suspects exceeds cap $_kMlStaleCleanupMaxIds",
      );
      rethrow;
    }

    final confirmed = <int>{};
    for (final id in suspects) {
      try {
        await fileDataService.getFilesData({id});
      } catch (e) {
        if (!_isRecoverableMlFetchForbidden(e)) rethrow;
        confirmed.add(id);
      }
    }
    if (confirmed.isEmpty) rethrow;

    final staleFiles = confirmed
        .map((id) => pendingIndex.remove(id)?.file)
        .whereType<EnteFile>()
        .toList();
    await FilesDB.instance.deleteMultipleUploadedFiles(confirmed.toList());
    Bus.instance.fire(
      LocalPhotosUpdatedEvent(
        staleFiles,
        type: EventType.deletedFromRemote,
        source: "mlStaleFileCleanup",
      ),
    );
    _logger.info(
      "Pruned ${confirmed.length} stale ML IDs, retrying ${pendingIndex.length}",
    );
    if (pendingIndex.isEmpty) return FileDataResponse.empty();
    return fileDataService.getFilesData(pendingIndex.keys.toSet());
  }
}

Future<List<FileMLInstruction>> hydrateRemoteMLDataForInstructions(
  List<FileMLInstruction> instructions, {
  required MLDataDB mlDataDB,
}) async {
  if (instructions.isEmpty) {
    return <FileMLInstruction>[];
  }
  final Set<int> ids = {};
  final Map<int, FileMLInstruction> pendingIndex = {};
  for (final instruction in instructions) {
    if (instruction.isLocalGallery) {
      continue;
    }
    ids.add(instruction.file.uploadedFileID!);
    pendingIndex[instruction.file.uploadedFileID!] = instruction;
  }
  if (ids.isEmpty) {
    return instructions.where((instruction) => instruction.pendingML).toList();
  }
  _logger.info("fetching embeddings for ${ids.length} files");
  final res = flagService.mLHydrationStaleFileRecovery
      ? await _fetchFilesDataForMlHydrationWithRecovery(pendingIndex)
      : await fileDataService.getFilesData(ids);
  _logger.info("embeddingResponse ${res.debugLog()}");
  final List<Face> faces = [];
  final List<ClipEmbedding> clipEmbeddings = [];
  for (final fileMl in res.data.values) {
    final existingInstruction = pendingIndex[fileMl.fileID];
    if (existingInstruction == null) {
      continue;
    }
    final facesFromRemoteEmbedding = _getFacesFromRemoteEmbedding(fileMl);
    // Note: always do null check; an empty value means no face was found.
    if (facesFromRemoteEmbedding != null) {
      faces.addAll(facesFromRemoteEmbedding);
      existingInstruction.shouldRunFaces = false;
    }
    final remoteClipEmbedding = fileMl.getClipEmbeddingIfCompatible(
      clipMlVersion,
    );
    if (remoteClipEmbedding != null) {
      clipEmbeddings.add(
        ClipEmbedding(
          fileID: fileMl.fileID,
          embedding: remoteClipEmbedding.embedding,
          version: remoteClipEmbedding.version,
        ),
      );
      existingInstruction.shouldRunClip = false;
    }
    if (!existingInstruction.pendingML) {
      pendingIndex.remove(fileMl.fileID);
    } else {
      existingInstruction.existingRemoteFileML = fileMl;
      pendingIndex[fileMl.fileID] = existingInstruction;
    }
  }

  await mlDataDB.bulkInsertFaces(faces);
  await mlDataDB.putClip(clipEmbeddings);
  return pendingIndex.values
      .where((instruction) => instruction.pendingML)
      .toList();
}

// Returns a list of faces from the given remote fileML. null if the version is less than the current version
// or if the remote faceEmbedding is null.
List<Face>? _getFacesFromRemoteEmbedding(FileDataEntity fileMl) {
  final RemoteFaceEmbedding? remoteFaceEmbedding = fileMl.faceEmbedding;
  if (_shouldDiscardRemoteEmbedding(fileMl)) {
    return null;
  }
  final List<Face> faces = [];
  if (remoteFaceEmbedding!.faces.isEmpty) {
    faces.add(Face.empty(fileMl.fileID));
  } else {
    for (final f in remoteFaceEmbedding.faces) {
      f.fileInfo = FileInfo(
        imageHeight: remoteFaceEmbedding.height,
        imageWidth: remoteFaceEmbedding.width,
      );
      faces.add(f);
    }
  }
  return faces;
}

bool _shouldDiscardRemoteEmbedding(FileDataEntity fileML) {
  final fileID = fileML.fileID;
  final RemoteFaceEmbedding? faceEmbedding = fileML.faceEmbedding;
  if (faceEmbedding == null || faceEmbedding.version < faceMlVersion) {
    _logger.info(
      "Discarding remote embedding for fileID $fileID "
      "because version is ${faceEmbedding?.version} and we need $faceMlVersion",
    );
    return true;
  }
  // are all landmarks equal?
  bool allLandmarksEqual = true;
  if (faceEmbedding.faces.isEmpty) {
    allLandmarksEqual = false;
  }
  for (final face in faceEmbedding.faces) {
    if (face.detection.landmarks.isEmpty) {
      allLandmarksEqual = false;
      break;
    }
    if (face.detection.landmarks.any((landmark) => landmark.x != landmark.y)) {
      allLandmarksEqual = false;
      break;
    }
  }
  if (allLandmarksEqual) {
    _logger.info(
      "Discarding remote embedding for fileID $fileID "
      "because landmarks are equal",
    );
    _logger.info(
      faceEmbedding.faces
          .map((e) => e.detection.landmarks.toString())
          .toList()
          .toString(),
    );
    return true;
  }

  return false;
}

Future<int> getIndexableFileCount() async {
  return FilesDB.instance.remoteFileCount();
}

Future<int> _getIndexableFileCount({required MLMode mode}) async {
  if (mode == MLMode.localGallery) {
    final files = await SearchService.instance.getAllFilesForSearch();
    return files
        .where(
          (file) =>
              (file.localID ?? '').isNotEmpty &&
              (file.uploadedFileID == null || file.uploadedFileID == -1) &&
              file.fileType != FileType.other,
        )
        .length;
  }
  return getIndexableFileCount();
}

Future<String> getImagePathForML(EnteFile enteFile) async {
  String? imagePath;

  final stopwatch = Stopwatch()..start();
  File? file;
  final bool isVideo = enteFile.fileType == FileType.video;
  if (isVideo) {
    try {
      file = await getThumbnailForUploadedFile(enteFile);
    } on PlatformException catch (e, s) {
      _logger.severe(
        "Could not get thumbnail for $enteFile due to PlatformException",
        e,
        s,
      );
      throw ThumbnailRetrievalException(e.toString(), s);
    }
  } else {
    // Don't process the file if it's too large (more than 100MB)
    if (enteFile.fileSize != null && enteFile.fileSize! > maxFileDownloadSize) {
      throw Exception(
        "FileSizeTooLargeForMobileIndexing: size is ${enteFile.fileSize}",
      );
    }
    try {
      if (Platform.isIOS && enteFile.localID != null) {
        trackOriginFetchForUploadOrML.put(enteFile.localID!, true);
      }
      file = await getFile(enteFile, isOrigin: true);
    } catch (e, s) {
      _logger.severe("Could not get file for $enteFile", e, s);
    }
  }
  imagePath = file?.path;
  stopwatch.stop();
  _logger.info(
    "Getting file data for fileID ${enteFile.uploadedFileID} took ${stopwatch.elapsedMilliseconds} ms",
  );

  if (imagePath == null) {
    _logger.severe(
      "Failed to get any data for enteFile with uploadedFileID ${enteFile.uploadedFileID} and format ${enteFile.displayName.split('.').last} and size ${enteFile.fileSize} since its file path is null (isVideo: $isVideo)",
    );
    throw CouldNotRetrieveAnyFileData();
  }

  return imagePath;
}

bool _shouldRunIndexing(
  EnteFile enteFile,
  Map<int, int> indexedFileIds,
  int newestVersion,
) {
  final id = enteFile.uploadedFileID!;
  return _shouldRunIndexingWithFileId(id, indexedFileIds, newestVersion);
}

bool _shouldRunIndexingWithFileId(
  int fileId,
  Map<int, int> indexedFileIds,
  int newestVersion,
) {
  return !indexedFileIds.containsKey(fileId) ||
      indexedFileIds[fileId]! < newestVersion;
}

void normalizeEmbedding(List<double> embedding) {
  double normalization = 0;
  for (int i = 0; i < embedding.length; i++) {
    normalization += embedding[i] * embedding[i];
  }
  final double sqrtNormalization = math.sqrt(normalization);
  for (int i = 0; i < embedding.length; i++) {
    embedding[i] = embedding[i] / sqrtNormalization;
  }
}

Future<MLResult> analyzeImageStatic(Map args) async {
  try {
    final int enteFileID = args["enteFileID"] as int;
    final String imagePath = args["filePath"] as String;
    final bool runFaces = args["runFaces"] as bool;
    final bool runClip = args["runClip"] as bool;
    final int faceDetectionAddress = args["faceDetectionAddress"] as int;
    final int faceEmbeddingAddress = args["faceEmbeddingAddress"] as int;
    final int clipImageAddress = args["clipImageAddress"] as int;

    _logger.info(
      "Start analyzeImageStatic for fileID $enteFileID (runFaces: $runFaces, runClip: $runClip)",
    );
    final startTime = DateTime.now();

    // Decode the image once to use for both face detection and alignment
    final decodedImage = await decodeImageFromPath(
      imagePath,
      includeRgbaBytes: true,
      includeDartUiImage: false,
    );
    final rawRgbaBytes = decodedImage.rawRgbaBytes!;
    final imageDimensions = decodedImage.dimensions;
    final result = MLResult.fromEnteFileID(enteFileID);
    result.decodedImageSize = imageDimensions;
    if (!runFaces) result.faces = null;
    final decodeTime = DateTime.now();
    final decodeMs = decodeTime.difference(startTime).inMilliseconds;

    String faceMsString = "", clipMsString = "";
    final pipelines = await Future.wait([
      runFaces
          ? FaceRecognitionService.runFacesPipeline(
              enteFileID,
              imageDimensions,
              rawRgbaBytes,
              faceDetectionAddress,
              faceEmbeddingAddress,
            ).then((result) {
              faceMsString =
                  ", faces: ${DateTime.now().difference(decodeTime).inMilliseconds} ms";
              return result;
            })
          : Future.value(null),
      runClip
          ? SemanticSearchService.runClipImage(
              enteFileID,
              imageDimensions,
              rawRgbaBytes,
              clipImageAddress,
            ).then((result) {
              clipMsString =
                  ", clip: ${DateTime.now().difference(decodeTime).inMilliseconds} ms";
              return result;
            })
          : Future.value(null),
    ]);

    if (pipelines[0] != null) result.faces = pipelines[0] as List<FaceResult>;
    if (pipelines[1] != null) result.clip = pipelines[1] as ClipResult;

    final totalMs = DateTime.now().difference(startTime).inMilliseconds;

    _logger.info(
      'Finished analyzeImageStatic for fileID $enteFileID, in $totalMs ms (decode: $decodeMs ms$faceMsString$clipMsString)',
    );

    return result;
  } catch (e, s) {
    _logger.severe("Could not analyze image", e, s);
    rethrow;
  }
}

Future<MLResult> analyzeImageRust(Map args) async {
  try {
    final int enteFileID = args["enteFileID"] as int;
    final String imagePath = args["filePath"] as String;
    final bool runFaces = args["runFaces"] as bool;
    final bool runClip = args["runClip"] as bool;
    final bool runPets = args["runPets"] as bool? ?? false;
    final String? faceDetectionModelPath =
        args["faceDetectionModelPath"] as String?;
    final String? faceEmbeddingModelPath =
        args["faceEmbeddingModelPath"] as String?;
    final String? clipImageModelPath = args["clipImageModelPath"] as String?;
    final String? petFaceDetectionModelPath =
        args["petFaceDetectionModelPath"] as String?;
    final String? petFaceEmbeddingDogModelPath =
        args["petFaceEmbeddingDogModelPath"] as String?;
    final String? petFaceEmbeddingCatModelPath =
        args["petFaceEmbeddingCatModelPath"] as String?;
    final String? petBodyDetectionModelPath =
        args["petBodyDetectionModelPath"] as String?;
    final String? petBodyEmbeddingDogModelPath =
        args["petBodyEmbeddingDogModelPath"] as String?;
    final String? petBodyEmbeddingCatModelPath =
        args["petBodyEmbeddingCatModelPath"] as String?;
    final bool preferCoreml = args["preferCoreml"] as bool? ?? true;
    final bool preferNnapi = args["preferNnapi"] as bool? ?? true;
    final bool preferXnnpack = args["preferXnnpack"] as bool? ?? false;
    final bool allowCpuFallback = args["allowCpuFallback"] as bool? ?? true;

    bool isMissingModelPath(String? path) =>
        path == null || path.trim().isEmpty;
    final missingModelPaths = <String>[];
    if (runFaces) {
      if (isMissingModelPath(faceDetectionModelPath)) {
        missingModelPaths.add("faceDetectionModelPath");
      }
      if (isMissingModelPath(faceEmbeddingModelPath)) {
        missingModelPaths.add("faceEmbeddingModelPath");
      }
    }
    if (runClip && isMissingModelPath(clipImageModelPath)) {
      missingModelPaths.add("clipImageModelPath");
    }
    if (runPets) {
      if (isMissingModelPath(petFaceDetectionModelPath)) {
        missingModelPaths.add("petFaceDetectionModelPath");
      }
      if (isMissingModelPath(petFaceEmbeddingDogModelPath)) {
        missingModelPaths.add("petFaceEmbeddingDogModelPath");
      }
      if (isMissingModelPath(petFaceEmbeddingCatModelPath)) {
        missingModelPaths.add("petFaceEmbeddingCatModelPath");
      }
      if (isMissingModelPath(petBodyDetectionModelPath)) {
        missingModelPaths.add("petBodyDetectionModelPath");
      }
      if (isMissingModelPath(petBodyEmbeddingDogModelPath)) {
        missingModelPaths.add("petBodyEmbeddingDogModelPath");
      }
      if (isMissingModelPath(petBodyEmbeddingCatModelPath)) {
        missingModelPaths.add("petBodyEmbeddingCatModelPath");
      }
    }
    if (missingModelPaths.isNotEmpty) {
      throw Exception(
        "RustMLMissingModelPath: Missing required model paths: ${missingModelPaths.join(', ')}",
      );
    }

    final modelPaths = rust_ml.RustModelPaths(
      faceDetection: faceDetectionModelPath ?? "",
      faceEmbedding: faceEmbeddingModelPath ?? "",
      clipImage: clipImageModelPath ?? "",
      clipText: "",
      petFaceDetection: petFaceDetectionModelPath ?? "",
      petFaceEmbeddingDog: petFaceEmbeddingDogModelPath ?? "",
      petFaceEmbeddingCat: petFaceEmbeddingCatModelPath ?? "",
      petBodyDetection: petBodyDetectionModelPath ?? "",
      petBodyEmbeddingDog: petBodyEmbeddingDogModelPath ?? "",
      petBodyEmbeddingCat: petBodyEmbeddingCatModelPath ?? "",
    );
    final providerPolicy = rust_ml.RustExecutionProviderPolicy(
      preferCoreml: preferCoreml,
      preferNnapi: preferNnapi,
      preferXnnpack: preferXnnpack,
      allowCpuFallback: allowCpuFallback,
    );

    Future<rust_ml.AnalyzeImageResult> runRustAnalyzeForPath(
      String analyzePath,
    ) {
      return rust_ml.analyzeImageRust(
        req: rust_ml.AnalyzeImageRequest(
          fileId: enteFileID,
          imagePath: analyzePath,
          runFaces: runFaces,
          runClip: runClip,
          runPets: runPets,
          modelPaths: modelPaths,
          providerPolicy: providerPolicy,
        ),
      );
    }

    final fileFormat = getExtension(imagePath);
    rust_ml.AnalyzeImageResult rustResult;
    try {
      rustResult = await runRustAnalyzeForPath(imagePath);
    } catch (e, s) {
      if (!_isRustDecodeIssue(e)) {
        if (_isRustCorruptModelIssue(e)) {
          rethrow;
        }
        _logger.severe(
          "Rust pipeline failed (non-decode) for fileID $enteFileID (format: $fileFormat)",
          e,
          s,
        );
        rethrow;
      }

      _logger.warning(
        "Rust decode failed for fileID $enteFileID (format: $fileFormat), retrying with JPEG fallback",
      );
      final _DecodeFallbackFile? fallback;
      try {
        fallback = await _createJpegDecodeFallbackFile(imagePath: imagePath);
      } catch (fallbackError, fallbackStack) {
        _logger.severe(
          "JPEG fallback conversion threw for fileID $enteFileID (format: $fileFormat)",
          fallbackError,
          fallbackStack,
        );
        rethrow;
      }
      if (fallback == null) {
        _logger.warning(
          "JPEG fallback conversion returned null/empty bytes for fileID $enteFileID (format: $fileFormat); storing empty result instead",
        );
        throw _asInvalidImageFormatExceptionForRustDecodeFailure(
          enteFileID: enteFileID,
          fileFormat: fileFormat,
          primaryError: e,
        );
      }

      try {
        rustResult = await runRustAnalyzeForPath(fallback.file.path);
        _logger.info(
          "Rust decode fallback succeeded for fileID $enteFileID (original format: $fileFormat)",
        );
      } catch (retryError, retryStack) {
        _logger.severe(
          "Rust decode fallback retry failed for fileID $enteFileID (original format: $fileFormat)",
          retryError,
          retryStack,
        );
        rethrow;
      } finally {
        await _cleanupDecodeFallback(fallback);
      }
    }

    final result = MLResult.fromEnteFileID(enteFileID);
    result.decodedImageSize = Dimensions(
      width: rustResult.decodedImageSize.width,
      height: rustResult.decodedImageSize.height,
    );

    // Nullify faces/clip when their pipelines were not requested so that
    // facesRan/clipRan correctly report false and processImage does not
    // overwrite existing remote embeddings with empty payloads.
    if (!runFaces) result.faces = null;

    if (runFaces) {
      final rustFaces = rustResult.faces ?? const <rust_ml.RustFaceResult>[];
      result.faces = rustFaces
          .map((face) {
            final detection = FaceDetectionRelative(
              score: face.detection.score,
              box: face.detection.boxXyxy.toList(growable: false),
              allKeypoints: face.detection.allKeypoints
                  .map((point) => point.toList(growable: false))
                  .toList(growable: false),
            );
            final alignment = AlignmentResult(
              affineMatrix: face.alignment.affineMatrix
                  .map((row) => row.toList(growable: false))
                  .toList(growable: false),
              center: face.alignment.center.toList(growable: false),
              size: face.alignment.size,
              rotation: face.alignment.rotation,
            );
            return FaceResult(
              fileId: enteFileID,
              faceId: face.faceId,
              detection: detection,
              blurValue: face.blurValue,
              alignment: alignment,
              embedding: face.embedding,
            );
          })
          .toList(growable: false);
    }

    if (runClip) {
      final rustClip = rustResult.clip;
      if (rustClip == null) {
        throw Exception("RustMLMissingClipOutput: clip output was null");
      }
      result.clip = ClipResult(
        fileID: enteFileID,
        embedding: rustClip.embedding,
      );
    }

    if (runPets) {
      if (rustResult.petFaces != null) {
        result.petFaces = rustResult.petFaces!
            .map((face) {
              final detection = FaceDetectionRelative(
                score: face.detection.score,
                box: face.detection.boxXyxy.toList(growable: false),
                allKeypoints: face.detection.keypoints
                    .map((point) => point.toList(growable: false))
                    .toList(growable: false),
              );
              final alignment = AlignmentResult(
                // Pet alignment is done in Rust; no Dart-side affine matrix needed.
                affineMatrix: const [],
                center: face.alignment.center.toList(growable: false),
                size: face.alignment.cropSize,
                rotation: face.alignment.angle,
              );
              return PetFaceResult(
                fileId: enteFileID,
                petFaceId: face.petFaceId,
                detection: detection,
                alignment: alignment,
                species: face.species,
                embedding: Embedding.from(face.faceEmbedding),
              );
            })
            .toList(growable: false);
      }

      if (rustResult.petBodies != null) {
        result.petBodies = rustResult.petBodies!
            .map((body) {
              return PetBodyResult(
                boxXyxy: body.boxXyxy.toList(growable: false),
                score: body.score,
                cocoClass: body.cocoClass,
                petBodyId: body.petBodyId,
                embedding: Embedding.from(body.bodyEmbedding),
              );
            })
            .toList(growable: false);
      }
    }

    return result;
  } catch (e, s) {
    if (isExpectedMlSkipError(e)) {
      rethrow;
    }
    _logger.severe("Could not analyze image with Rust pipeline", e, s);
    rethrow;
  }
}

bool isExpectedMlSkipError(Object error) {
  final message = _normalizedErrorMessage(error);
  const acceptedIssueMarkers = <String>[
    "thumbnailretrievalexception",
    "invalidimageformatexception",
    "unhandledexiforientation",
    "filesizetoolargeformobileindexing",
  ];
  return acceptedIssueMarkers.any(message.contains);
}

String formatExpectedMlSkipReasonForLogs(Object error) {
  final normalized = _normalizedErrorMessage(error);
  if (normalized.contains("invalidimageformatexception")) {
    return "image decode failed";
  }
  if (normalized.contains("thumbnailretrievalexception")) {
    return "thumbnail retrieval failed";
  }
  if (normalized.contains("unhandledexiforientation")) {
    return "unsupported EXIF orientation";
  }
  if (normalized.contains("filesizetoolargeformobileindexing")) {
    return "file is too large for mobile indexing";
  }
  final firstLine = error.toString().split('\n').first.trim();
  return firstLine.isEmpty ? "unknown ML skip reason" : firstLine;
}

bool _isRustDecodeIssue(Object error) {
  return error is rust_ml.RustMlError_Decode;
}

bool _isRustCorruptModelIssue(Object error) {
  return error is rust_ml.RustMlError_CorruptModel;
}

String _normalizedErrorMessage(Object error) {
  if (error is PlatformException) {
    return <String>[
      error.code,
      error.message ?? "",
      "${error.details ?? ""}",
      error.toString(),
    ].join(" ").toLowerCase();
  }
  return error.toString().toLowerCase();
}

Exception _asInvalidImageFormatExceptionForRustDecodeFailure({
  required int enteFileID,
  required String fileFormat,
  required Object primaryError,
  Object? fallbackError,
}) {
  final details = <String>[
    "InvalidImageFormatException: Rust decode failed for fileID $enteFileID (format: $fileFormat)",
    "primary_error: $primaryError",
    if (fallbackError != null) "fallback_error: $fallbackError",
  ];
  return Exception(details.join("; "));
}

class _DecodeFallbackFile {
  final File file;
  final Directory directory;

  const _DecodeFallbackFile({required this.file, required this.directory});
}

Future<_DecodeFallbackFile?> _createJpegDecodeFallbackFile({
  required String imagePath,
}) async {
  final convertedData = await createSafeJpegDecodeFallbackBytes(
    imagePath: imagePath,
  );
  if (convertedData == null || convertedData.isEmpty) {
    return null;
  }

  final tempDirectory = await Directory.systemTemp.createTemp(
    "ente_ml_decode_fallback_",
  );
  final fallbackFile = File("${tempDirectory.path}/ml_decode_retry.jpg");
  await fallbackFile.writeAsBytes(convertedData, flush: true);
  return _DecodeFallbackFile(file: fallbackFile, directory: tempDirectory);
}

Future<void> _cleanupDecodeFallback(_DecodeFallbackFile fallback) async {
  try {
    if (await fallback.file.exists()) {
      await fallback.file.delete();
    }
    if (await fallback.directory.exists()) {
      await fallback.directory.delete(recursive: true);
    }
  } catch (e, s) {
    _logger.warning("Could not cleanup decode fallback file", e, s);
  }
}
