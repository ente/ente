import "dart:async";

import "package:logging/logging.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/services/wrapped/models.dart";

/// Preloads the media referenced by Wrapped cards so the viewer can render
/// without waiting on database and thumbnail fetches.
class WrappedMediaPreloader {
  WrappedMediaPreloader._()
    : _logger = Logger("WrappedMediaPreloader"),
      _cache = <int, EnteFile>{},
      _inFlight = <int, Future<EnteFile?>>{};

  static final WrappedMediaPreloader instance = WrappedMediaPreloader._();

  final Logger _logger;
  final Map<int, EnteFile> _cache;
  final Map<int, Future<EnteFile?>> _inFlight;

  /// Loads and caches the media for the supplied Wrapped result.
  Future<void> prime(WrappedResult result) async {
    final Set<int> targetIDs = _extractMediaIDs(result.cards);
    _pruneTo(targetIDs);

    if (targetIDs.isEmpty) {
      return;
    }

    final List<Future<EnteFile?>> pending = <Future<EnteFile?>>[
      for (final int id in targetIDs) ensureFile(id),
    ];
    await Future.wait(pending, eagerError: false);
  }

  /// Clears all cached entries and cancels outstanding loads.
  void reset() {
    _cache.clear();
    _inFlight.clear();
  }

  /// Returns the cached file for [uploadedID] if available.
  EnteFile? getCachedFile(int uploadedID) {
    if (uploadedID <= 0) {
      return null;
    }
    return _cache[uploadedID];
  }

  /// Ensures the [EnteFile] for [uploadedID] is cached and returns it.
  Future<EnteFile?> ensureFile(int uploadedID) {
    if (uploadedID <= 0) {
      return Future<EnteFile?>.value(null);
    }
    final EnteFile? cached = _cache[uploadedID];
    if (cached != null) {
      return Future<EnteFile?>.value(cached);
    }
    final Future<EnteFile?>? inFlight = _inFlight[uploadedID];
    if (inFlight != null) {
      return inFlight;
    }
    final Future<EnteFile?> loader = _loadAndCache(uploadedID);
    _inFlight[uploadedID] = loader;
    return loader;
  }

  Future<EnteFile?> _loadAndCache(int uploadedID) async {
    try {
      final EnteFile? file = await FilesDB.instance.getAnyUploadedFile(
        uploadedID,
      );
      if (file != null) {
        _cache[uploadedID] = file;
        _warmThumbnail(file);
      }
      return file;
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to preload Wrapped media for uploaded ID $uploadedID",
        error,
        stackTrace,
      );
      return null;
    } finally {
      // ignore: unawaited_futures
      _inFlight.remove(uploadedID);
    }
  }

  void _warmThumbnail(EnteFile file) {
    // Thumbnail preloading returns a future internally; fire-and-forget.
    try {
      // ignore: unawaited_futures
      preloadThumbnail(file);
    } catch (error, stackTrace) {
      _logger.fine(
        "Thumbnail warmup failed for ${file.uploadedFileID}",
        error,
        stackTrace,
      );
    }
  }

  void _pruneTo(Set<int> targetIDs) {
    if (targetIDs.isEmpty) {
      _cache.clear();
      _inFlight.clear();
      return;
    }
    _cache.removeWhere((int key, _) => !targetIDs.contains(key));
    _inFlight.removeWhere((int key, _) => !targetIDs.contains(key));
  }

  static Set<int> _extractMediaIDs(List<WrappedCard> cards) {
    final Set<int> ids = <int>{};
    for (final WrappedCard card in cards) {
      for (final MediaRef ref in card.media) {
        if (ref.uploadedFileID > 0) {
          ids.add(ref.uploadedFileID);
        }
      }
      final Object? rawCandidates = card.meta["candidateUploadedIDs"];
      if (rawCandidates is Iterable) {
        for (final Object? entry in rawCandidates) {
          final int? id = entry is num ? entry.toInt() : int.tryParse("$entry");
          if (id != null && id > 0) {
            ids.add(id);
          }
        }
      }
    }
    return ids;
  }
}
