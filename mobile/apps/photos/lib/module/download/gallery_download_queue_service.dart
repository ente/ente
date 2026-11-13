import "dart:async";
import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/gallery_downloads_db.dart";
import "package:photos/events/gallery_downloads_events.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import 'package:photos/module/download/decrypt.dart';
import 'package:photos/module/download/gallery.dart';
import "package:photos/module/download/manager.dart";
import "package:photos/module/download/task.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/device_storage_error.dart";

class GalleryDownloadEnqueueResult {
  final int addedCount;
  final int duplicateCount;

  const GalleryDownloadEnqueueResult({
    required this.addedCount,
    required this.duplicateCount,
  });
}

class GalleryDownloadQueueService {
  static const int kMaximumConcurrentDownloads = 5;
  static const Duration kCompletionBannerDuration = Duration(seconds: 5);
  static const Duration kStaleTaskDuration = Duration(days: 7);

  final _logger = Logger("GalleryDownloadQueueService");
  final _db = GalleryDownloadsDB.instance;

  final Map<int, DownloadTask> _tasks = {};
  final Set<int> _activeDownloads = {};
  final Map<int, StreamSubscription<DownloadTask>> _watchSubscriptions = {};
  final Map<int, EnteFile> _queuedFilesByID = {};

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<UserLoggedOutEvent>? _logoutSubscription;
  Timer? _completionCleanupTimer;
  Completer<void>? _initCompleter;

  bool _isInitialized = false;
  bool _isBannerDismissedByUser = false;
  bool _showCompletionBanner = false;

  GalleryDownloadQueueService._privateConstructor();

  static final GalleryDownloadQueueService instance =
      GalleryDownloadQueueService._privateConstructor();

  List<DownloadTask> get orderedTasks {
    final tasks = _tasks.values.toList();
    tasks.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return tasks;
  }

  int get totalCount => _tasks.length;
  int get completedCount => _tasks.values
      .where((task) => task.status == DownloadStatus.completed)
      .length;
  int get unavailableCount => _tasks.values
      .where((task) => task.error == DownloadManager.unavailableError)
      .length;
  int get downloadingCount => _tasks.values
      .where((task) => task.status == DownloadStatus.downloading)
      .length;
  int get pendingCount => _tasks.values
      .where((task) => task.status == DownloadStatus.pending)
      .length;
  int get pausedCount => _tasks.values
      .where((task) => task.status == DownloadStatus.paused)
      .length;

  bool get hasPausedDueToNoConnection => _tasks.values.any(
    (task) =>
        task.status == DownloadStatus.paused &&
        task.error == DownloadManager.noConnectionError,
  );

  bool get hasPausedDueToStorage => _tasks.values.any(
    (task) =>
        task.status == DownloadStatus.paused &&
        task.error == DownloadManager.notEnoughStorageError,
  );

  bool get hasNonUnavailableErrors => _tasks.values.any(
    (task) =>
        task.status == DownloadStatus.error &&
        task.error != DownloadManager.unavailableError,
  );

  bool get isCompletionBannerVisible =>
      _showCompletionBanner &&
      _allTasksAreTerminal &&
      (completedCount > 0 || unavailableCount > 0);

  bool get isBannerVisible {
    if (_tasks.isEmpty) {
      return false;
    }
    if (isCompletionBannerVisible) {
      return true;
    }
    final hasBlockingError = _tasks.values.any(
      (task) =>
          task.status == DownloadStatus.paused ||
          (task.status == DownloadStatus.error &&
              task.error != DownloadManager.unavailableError),
    );
    if (_isBannerDismissedByUser && !hasBlockingError) {
      return false;
    }
    return _tasks.values.any((task) => !_isTerminal(task.status)) ||
        hasBlockingError;
  }

  double get overallProgress {
    if (_tasks.isEmpty) {
      return 0;
    }
    int totalBytes = 0;
    int downloadedBytes = 0;
    for (final task in _tasks.values) {
      totalBytes += task.totalBytes;
      downloadedBytes += task.bytesDownloaded.clamp(0, task.totalBytes);
    }
    if (totalBytes <= 0) {
      return 0;
    }
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  Future<void> init() async {
    if (_isInitialized) {
      return;
    }
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }
    _initCompleter = Completer<void>();
    try {
      await _loadTasksFromDB();
      _listenToConnectivity();
      _listenToLogout();
      _isInitialized = true;
      _emitUpdatedEvent();
      _pollQueue();
      _initCompleter!.complete();
    } catch (e, s) {
      _logger.severe("Failed to initialize gallery download queue", e, s);
      _initCompleter!.completeError(e, s);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  Future<GalleryDownloadEnqueueResult> enqueueFiles(
    List<EnteFile> files, {
    bool persistToFilesDB = true,
  }) async {
    await init();
    if (files.isEmpty) {
      return const GalleryDownloadEnqueueResult(
        addedCount: 0,
        duplicateCount: 0,
      );
    }

    int addedCount = 0;
    int duplicateCount = 0;
    int createTimestamp = DateTime.now().microsecondsSinceEpoch;

    for (final file in files) {
      final uploadID = file.uploadedFileID;
      final fileSize = file.fileSize;
      if (uploadID == null || fileSize == null || fileSize <= 0) {
        continue;
      }
      final queuedFile = file.isRemoteOnlyFile
          ? file.copyWith()
          : (file.copyWith()..localID = null);
      _queuedFilesByID[uploadID] = queuedFile;
      final sourceFileJson = _serializeQueuedFile(
        queuedFile,
        persistToFilesDB: persistToFilesDB,
      );
      if (_tasks.containsKey(uploadID)) {
        final existingTask = _tasks[uploadID];
        if (existingTask != null &&
            persistToFilesDB &&
            existingTask.sourceFileJson != sourceFileJson) {
          await _updateTask(
            existingTask.copyWith(sourceFileJson: sourceFileJson),
          );
        }
        duplicateCount++;
        continue;
      }
      final task = DownloadTask(
        id: uploadID,
        filename: file.displayName,
        totalBytes: fileSize,
        status: DownloadStatus.pending,
        createdAt: createTimestamp++,
        updatedAt: createTimestamp,
        sourceFileJson: sourceFileJson,
      );
      _tasks[uploadID] = task;
      await _db.upsertTask(task);
      addedCount++;
    }

    if (addedCount > 0) {
      _completionCleanupTimer?.cancel();
      _showCompletionBanner = false;
      _isBannerDismissedByUser = false;
      _emitUpdatedEvent();
      _pollQueue();
    }

    return GalleryDownloadEnqueueResult(
      addedCount: addedCount,
      duplicateCount: duplicateCount,
    );
  }

  Future<void> cancelTask(int fileID) async {
    await init();
    final task = _tasks[fileID];
    if (task == null) {
      return;
    }
    final removedSubscription = _watchSubscriptions.remove(fileID);
    if (removedSubscription != null) {
      await removedSubscription.cancel();
    }
    if (_activeDownloads.contains(fileID)) {
      await downloadManager.cancel(fileID);
      _activeDownloads.remove(fileID);
    }
    _tasks.remove(fileID);
    _queuedFilesByID.remove(fileID);
    await _db.deleteTask(fileID);
    _emitUpdatedEvent();
    _pollQueue();
  }

  Future<void> cancelAll() async {
    await init();
    final activeIDs = _activeDownloads.toList(growable: false);
    for (final id in activeIDs) {
      await downloadManager.cancel(id);
      final subscription = _watchSubscriptions.remove(id);
      if (subscription != null) {
        await subscription.cancel();
      }
    }
    _activeDownloads.clear();
    _tasks.clear();
    _queuedFilesByID.clear();
    _showCompletionBanner = false;
    _isBannerDismissedByUser = false;
    _completionCleanupTimer?.cancel();
    await _db.clearTable();
    _emitUpdatedEvent();
  }

  void dismissBanner() {
    if (_tasks.isEmpty) {
      return;
    }
    _isBannerDismissedByUser = true;
    _showCompletionBanner = false;
    _emitUpdatedEvent();
  }

  void showBannerAfterAppReopen() {
    if (_tasks.isEmpty) {
      return;
    }
    if (_isBannerDismissedByUser) {
      _isBannerDismissedByUser = false;
      _emitUpdatedEvent();
    }
  }

  Future<void> dismissCompletionBanner() async {
    _completionCleanupTimer?.cancel();
    _showCompletionBanner = false;
    await _clearTerminalTasks();
    _emitUpdatedEvent();
  }

  Future<void> _loadTasksFromDB() async {
    final tasks = await _db.getAllTasks();
    final now = DateTime.now().microsecondsSinceEpoch;
    final staleCutoff = now - kStaleTaskDuration.inMicroseconds;
    final staleIDs = <int>[];

    for (var task in tasks) {
      if (!_isTerminal(task.status) && task.updatedAt < staleCutoff) {
        staleIDs.add(task.id);
        await _deletePartialFiles(task);
        continue;
      }
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.paused) {
        task = task.copyWith(status: DownloadStatus.pending, error: null);
      }
      _tasks[task.id] = task;
      final queuedFile = _deserializeQueuedFile(task.sourceFileJson);
      if (queuedFile != null) {
        _queuedFilesByID[task.id] = queuedFile;
      }
    }

    if (staleIDs.isNotEmpty) {
      await _db.deleteTasks(staleIDs);
    }

    if (_tasks.isNotEmpty) {
      _isBannerDismissedByUser = false;
    }

    if (_tasks.isNotEmpty &&
        _tasks.values.every((task) => _isTerminal(task.status))) {
      await _clearTerminalTasks();
    }
  }

  void _listenToConnectivity() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final hasConnection = results.any(
        (result) => result != ConnectivityResult.none,
      );
      if (!hasConnection) {
        return;
      }
      _resumePausedNetworkTasks().ignore();
    });
  }

  void _listenToLogout() {
    _logoutSubscription?.cancel();
    _logoutSubscription = Bus.instance.on<UserLoggedOutEvent>().listen((_) {
      cancelAll().ignore();
    });
  }

  Future<void> _resumePausedNetworkTasks() async {
    final pausedTasks = orderedTasks
        .where(
          (task) =>
              task.status == DownloadStatus.paused &&
              task.error == DownloadManager.noConnectionError,
        )
        .toList();
    if (pausedTasks.isEmpty) {
      return;
    }
    for (final task in pausedTasks) {
      await _updateTask(
        task.copyWith(status: DownloadStatus.pending, error: null),
      );
    }
    _isBannerDismissedByUser = false;
    _showCompletionBanner = false;
    Bus.instance.fire(GalleryDownloadsResumedEvent());
    _pollQueue();
  }

  void _pollQueue() {
    if (!_isInitialized) {
      return;
    }
    while (_activeDownloads.length < kMaximumConcurrentDownloads) {
      final nextTask = orderedTasks.firstWhereOrNull(
        (task) =>
            task.status == DownloadStatus.pending &&
            !_activeDownloads.contains(task.id),
      );
      if (nextTask == null) {
        break;
      }
      _startTask(nextTask);
    }
    _maybeShowCompletionState();
    _emitUpdatedEvent();
  }

  void _startTask(DownloadTask task) {
    _activeDownloads.add(task.id);
    _updateTask(
      task.copyWith(status: DownloadStatus.downloading, error: null),
    ).ignore();
    _watchSubscriptions[task.id]?.cancel();
    _watchSubscriptions[task.id] = downloadManager
        .watchDownload(task.id)
        .listen((downloadTask) {
          final existing = _tasks[task.id];
          if (existing == null) {
            return;
          }
          final updatedTask = existing.copyWith(
            bytesDownloaded: downloadTask.bytesDownloaded,
            filePath: downloadTask.filePath,
          );
          _updateTask(updatedTask).ignore();
        });
    _runTask(task.id).ignore();
  }

  Future<void> _runTask(int fileID) async {
    try {
      await _downloadAndSaveToGallery(fileID);
      final task = _tasks[fileID];
      if (task != null) {
        await _updateTask(
          task.copyWith(
            status: DownloadStatus.completed,
            bytesDownloaded: task.totalBytes,
            error: null,
          ),
        );
      }
    } on DownloadNoConnectionError {
      await _setPausedState(fileID, DownloadManager.noConnectionError);
    } on DeviceStorageFullException {
      await _setPausedState(fileID, DownloadManager.notEnoughStorageError);
    } on DownloadUnavailableError {
      await _setErrorState(fileID, DownloadManager.unavailableError);
    } on DownloadFailedError catch (e) {
      await _setErrorState(fileID, e.message);
    } catch (e, s) {
      _logger.warning("Gallery download failed for fileID=$fileID", e, s);
      await _setErrorState(fileID, e.toString());
    } finally {
      _activeDownloads.remove(fileID);
      final subscription = _watchSubscriptions.remove(fileID);
      if (subscription != null) {
        await subscription.cancel();
      }
      _pollQueue();
    }
  }

  Future<void> _downloadAndSaveToGallery(int fileID) async {
    EnteFile? file = _queuedFilesByID[fileID];
    String? sourceFileJson;
    if (file == null) {
      final task = _tasks[fileID];
      if (task != null) {
        sourceFileJson = task.sourceFileJson;
        file = _deserializeQueuedFile(task.sourceFileJson);
        if (file != null) {
          _queuedFilesByID[fileID] = file;
        }
      }
    }
    if (file == null) {
      final filesMap = await FilesDB.instance.getFileIDToFileFromIDs([fileID]);
      file = filesMap[fileID];
    }
    if (file == null) {
      throw DownloadUnavailableError();
    }
    file.fileSize ??= _tasks[fileID]?.totalBytes;
    final fileToDownload = file.isRemoteOnlyFile
        ? file.copyWith()
        : (file.copyWith()..localID = null);
    await downloadToGallery(
      fileToDownload,
      forceResumableDownload: true,
      persistToFilesDB: _deserializePersistToFilesDB(
        sourceFileJson ?? _tasks[fileID]?.sourceFileJson,
      ),
    );
  }

  Future<void> _setPausedState(int fileID, String reason) async {
    final task = _tasks[fileID];
    if (task == null) {
      return;
    }
    await _updateTask(
      task.copyWith(status: DownloadStatus.paused, error: reason),
    );
    _isBannerDismissedByUser = false;
    _showCompletionBanner = false;
  }

  Future<void> _setErrorState(int fileID, String reason) async {
    final task = _tasks[fileID];
    if (task == null) {
      return;
    }
    await _updateTask(
      task.copyWith(status: DownloadStatus.error, error: reason),
    );
    _isBannerDismissedByUser = false;
    _showCompletionBanner = false;
  }

  Future<void> _updateTask(DownloadTask task) async {
    _tasks[task.id] = task;
    await _db.upsertTask(task);
    _emitUpdatedEvent();
  }

  void _maybeShowCompletionState() {
    if (!_allTasksAreTerminal) {
      _completionCleanupTimer?.cancel();
      _showCompletionBanner = false;
      return;
    }
    if (_isBannerDismissedByUser) {
      _showCompletionBanner = false;
      _clearTerminalTasks().ignore();
      return;
    }
    if (completedCount == 0 && unavailableCount == 0) {
      _showCompletionBanner = false;
      _clearTerminalTasks().ignore();
      return;
    }
    if (_showCompletionBanner) {
      return;
    }
    _showCompletionBanner = true;
    _completionCleanupTimer?.cancel();
    _completionCleanupTimer = Timer(
      kCompletionBannerDuration,
      () => dismissCompletionBanner().ignore(),
    );
  }

  bool get _allTasksAreTerminal =>
      _tasks.isNotEmpty &&
      _tasks.values.every((task) => _isTerminal(task.status));

  bool _isTerminal(DownloadStatus status) =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.error ||
      status == DownloadStatus.cancelled;

  Future<void> _clearTerminalTasks() async {
    final terminalIDs = _tasks.values
        .where((task) => _isTerminal(task.status))
        .map((task) => task.id)
        .toList(growable: false);
    if (terminalIDs.isEmpty) {
      return;
    }
    for (final id in terminalIDs) {
      _tasks.remove(id);
      _queuedFilesByID.remove(id);
    }
    await _db.deleteTasks(terminalIDs);
    _emitUpdatedEvent();
  }

  Future<void> _deletePartialFiles(DownloadTask task) async {
    try {
      final directory = Configuration.instance.getTempDirectory();
      final basePath = "$directory${task.id}.encrypted";
      final file = File(basePath);
      if (await file.exists()) {
        await file.delete();
      }
      final totalChunks = (task.totalBytes / DownloadManager.downloadChunkSize)
          .ceil();
      for (int i = 1; i <= totalChunks; i++) {
        final chunk = File("$basePath.${i}_part");
        if (await chunk.exists()) {
          await chunk.delete();
        }
      }
    } catch (e) {
      _logger.warning("Failed to clean stale partial files for ${task.id}", e);
    }
  }

  void _emitUpdatedEvent() {
    Bus.instance.fire(GalleryDownloadsUpdatedEvent());
  }

  String _serializeQueuedFile(EnteFile file, {required bool persistToFilesDB}) {
    return jsonEncode({
      "uploadedFileID": file.uploadedFileID,
      "ownerID": file.ownerID,
      "collectionID": file.collectionID,
      "title": file.title,
      "fileType": file.fileType.index,
      "encryptedKey": file.encryptedKey,
      "keyDecryptionNonce": file.keyDecryptionNonce,
      "fileDecryptionHeader": file.fileDecryptionHeader,
      "thumbnailDecryptionHeader": file.thumbnailDecryptionHeader,
      "metadataDecryptionHeader": file.metadataDecryptionHeader,
      "fileSize": file.fileSize,
      "pubMmdEncodedJson": file.pubMmdEncodedJson,
      "pubMmdVersion": file.pubMmdVersion,
      "persistToFilesDB": persistToFilesDB,
    });
  }

  bool _deserializePersistToFilesDB(String? sourceFileJson) {
    if (sourceFileJson == null || sourceFileJson.isEmpty) {
      return true;
    }
    try {
      final Map<String, dynamic> map =
          jsonDecode(sourceFileJson) as Map<String, dynamic>;
      return map["persistToFilesDB"] as bool? ?? true;
    } catch (e, s) {
      _logger.warning("Failed to deserialize gallery download metadata", e, s);
      return true;
    }
  }

  EnteFile? _deserializeQueuedFile(String? sourceFileJson) {
    if (sourceFileJson == null || sourceFileJson.isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> map =
          jsonDecode(sourceFileJson) as Map<String, dynamic>;
      final fileTypeIndex = map["fileType"];
      if (fileTypeIndex is! int) {
        return null;
      }
      final file = EnteFile()
        ..uploadedFileID = map["uploadedFileID"] as int?
        ..ownerID = map["ownerID"] as int?
        ..collectionID = map["collectionID"] as int?
        ..title = map["title"] as String?
        ..fileType = getFileType(fileTypeIndex)
        ..encryptedKey = map["encryptedKey"] as String?
        ..keyDecryptionNonce = map["keyDecryptionNonce"] as String?
        ..fileDecryptionHeader = map["fileDecryptionHeader"] as String?
        ..thumbnailDecryptionHeader =
            map["thumbnailDecryptionHeader"] as String?
        ..metadataDecryptionHeader = map["metadataDecryptionHeader"] as String?
        ..fileSize = map["fileSize"] as int?
        ..pubMmdEncodedJson = map["pubMmdEncodedJson"] as String?
        ..pubMmdVersion = map["pubMmdVersion"] as int? ?? 0;
      if (file.uploadedFileID == null ||
          file.collectionID == null ||
          file.fileSize == null ||
          file.fileDecryptionHeader == null ||
          file.encryptedKey == null ||
          file.keyDecryptionNonce == null) {
        return null;
      }
      return file;
    } catch (e, s) {
      _logger.warning("Failed to deserialize queued source file", e, s);
      return null;
    }
  }
}
