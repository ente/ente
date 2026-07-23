import "dart:async";
import "dart:collection";

import "package:logging/logging.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/module/download/file.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/video_preview_service.dart";
import "package:photos/utils/network_util.dart";

const int kMemoryVideoLookaheadCap = 20;
const int kMemoryVideoMaxConcurrentPrefetches = 1;

const int kMemoryVideoPreviewMaxBytes = 50 * 1024 * 1024;
const int kMemoryVideoOriginalMaxBytes = 50 * 1024 * 1024;
const int kMemoryVideoOriginalMaxDurationSeconds = 30;
const int kMemoryVideoSessionBudgetBytes = 200 * 1024 * 1024;

enum _OriginalPrefetchResult { warmed, ineligible, failed }

class MemoryVideoPrefetcher {
  final _logger = Logger("MemoryVideoPrefetcher");
  final Queue<({EnteFile file, bool Function()? stillActive})> _queue =
      Queue<({EnteFile file, bool Function()? stillActive})>();
  final Set<int> _queuedIDs = <int>{};
  final Set<int> _attemptedIDs = <int>{};
  final Map<int, int> _reservedDownloadBytesByID = <int, int>{};

  int _activeCount = 0;
  int _reservedDownloadBytes = 0;
  bool _disposed = false;

  void prefetchFiles(
    Iterable<EnteFile> files, {
    bool Function()? stillActive,
    bool replacePending = false,
  }) {
    if (_disposed || isLocalGalleryMode) return;
    if (replacePending) {
      clearPending();
    }
    for (final file in files) {
      if (stillActive != null && !stillActive()) return;
      _enqueue(file, stillActive);
    }
    _pump();
  }

  void clearPending() {
    _queue.clear();
    _queuedIDs.clear();
  }

  void dispose() {
    _disposed = true;
    clearPending();
  }

  void _enqueue(EnteFile file, bool Function()? stillActive) {
    if (file.fileType != FileType.video || !file.isRemoteOnlyFile) return;
    final uploadedFileID = file.uploadedFileID;
    if (uploadedFileID == null) return;
    if (_attemptedIDs.contains(uploadedFileID) ||
        _queuedIDs.contains(uploadedFileID)) {
      return;
    }
    _queue.add((file: file, stillActive: stillActive));
    _queuedIDs.add(uploadedFileID);
  }

  void _pump() {
    if (_disposed || isLocalGalleryMode) return;
    while (_activeCount < kMemoryVideoMaxConcurrentPrefetches &&
        _queue.isNotEmpty) {
      final entry = _queue.removeFirst();
      final file = entry.file;
      final uploadedFileID = file.uploadedFileID;
      if (uploadedFileID == null) continue;
      _queuedIDs.remove(uploadedFileID);
      if (_attemptedIDs.contains(uploadedFileID)) continue;
      if (!_isActive(entry.stillActive)) continue;

      _activeCount++;
      unawaited(
        _prefetch(file, uploadedFileID, entry.stillActive).whenComplete(() {
          _activeCount--;
          _pump();
        }),
      );
    }
  }

  bool _isActive(bool Function()? stillActive) {
    return !_disposed &&
        !isLocalGalleryMode &&
        (stillActive == null || stillActive());
  }

  bool _tryReserveDownloadBytes(int uploadedFileID, int bytes) {
    final existingReservation = _reservedDownloadBytesByID[uploadedFileID];
    final additionalBytes = existingReservation == null
        ? bytes
        : bytes - existingReservation;
    if (additionalBytes <= 0) {
      return true;
    }
    if (_reservedDownloadBytes + additionalBytes >
        kMemoryVideoSessionBudgetBytes) {
      return false;
    }
    _reservedDownloadBytes += additionalBytes;
    _reservedDownloadBytesByID[uploadedFileID] = bytes;
    return true;
  }

  Future<void> _prefetch(
    EnteFile file,
    int uploadedFileID,
    bool Function()? stillActive,
  ) async {
    try {
      if (!_isActive(stillActive)) return;
      if (!await canUseHighBandwidth()) return;
      if (!_isActive(stillActive)) return;

      final didWarmPreview = await VideoPreviewService.instance
          .prefetchExistingPreview(
            file,
            maxPreviewSizeBytes: kMemoryVideoPreviewMaxBytes,
            tryReserveBytes: (bytes) {
              return _isActive(stillActive) &&
                  _tryReserveDownloadBytes(uploadedFileID, bytes);
            },
          );
      if (!_isActive(stillActive)) return;
      if (!didWarmPreview) {
        final originalResult = await _prefetchSmallOriginal(
          file,
          uploadedFileID: uploadedFileID,
          stillActive: stillActive,
        );
        if (originalResult == _OriginalPrefetchResult.failed) {
          return;
        }
      }
      if (!_isActive(stillActive)) return;
      _attemptedIDs.add(uploadedFileID);
    } catch (e, s) {
      _logger.warning(
        "Failed to prefetch memory video for fileID $uploadedFileID",
        e,
        s,
      );
      // Transient prefetch failures should be retryable on a later warm pass.
    }
  }

  Future<_OriginalPrefetchResult> _prefetchSmallOriginal(
    EnteFile file, {
    required int uploadedFileID,
    bool Function()? stillActive,
  }) async {
    final fileSize = file.fileSize;
    final duration = file.duration;
    if (fileSize == null ||
        fileSize <= 0 ||
        fileSize > kMemoryVideoOriginalMaxBytes ||
        duration == null ||
        duration <= 0 ||
        duration > kMemoryVideoOriginalMaxDurationSeconds) {
      return _OriginalPrefetchResult.ineligible;
    }
    if (await isFileCached(file)) {
      return _OriginalPrefetchResult.warmed;
    }
    if (!_isActive(stillActive)) {
      return _OriginalPrefetchResult.failed;
    }
    if (!_tryReserveDownloadBytes(uploadedFileID, fileSize)) {
      return _OriginalPrefetchResult.ineligible;
    }
    final prefetchedFile = await getFileFromServer(file);
    if (prefetchedFile != null) {
      return _OriginalPrefetchResult.warmed;
    }
    _logger.info(
      "Memory video original prefetch returned no file for fileID "
      "$uploadedFileID",
    );
    return _OriginalPrefetchResult.failed;
  }
}
