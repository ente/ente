import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:photos/services/wrapped/models.dart";
import "package:synchronized/synchronized.dart";

class WrappedCacheService {
  WrappedCacheService._();

  static final WrappedCacheService instance = WrappedCacheService._();

  final Logger _logger = Logger("WrappedCacheService");
  final Lock _lock = Lock();

  Directory? _cacheDirectory;

  Future<Directory> _cacheDirectoryPath() async {
    final Directory baseDir = await getApplicationSupportDirectory();
    return Directory(path.join(baseDir.path, "wrapped_cache"));
  }

  Future<Directory> _ensureCacheDirectory() async {
    if (_cacheDirectory != null) {
      return _cacheDirectory!;
    }
    final Directory directory = await _cacheDirectoryPath();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    _cacheDirectory = directory;
    return directory;
  }

  Future<File> _cacheFileForYear(int year) async {
    final Directory directory = await _ensureCacheDirectory();
    return File(path.join(directory.path, "$year.json"));
  }

  Future<WrappedResult?> read({required int year}) {
    return _lock.synchronized(() async {
      final File file = await _cacheFileForYear(year);
      if (!await file.exists()) {
        _logger.fine("No Wrapped cache found for $year at ${file.path}");
        return null;
      }
      try {
        final String contents = await file.readAsString();
        final WrappedResult? result = WrappedResult.decode(contents);
        if (result == null) {
          _logger.warning(
            "Failed to decode Wrapped cache for $year, deleting stale file",
          );
          await file.delete();
          return null;
        }
        _logger.info(
          "Loaded Wrapped cache for $year with ${result.cards.length} cards",
        );
        return result;
      } catch (error, stackTrace) {
        _logger.severe(
          "Error reading Wrapped cache for $year",
          error,
          stackTrace,
        );
        try {
          await file.delete();
        } catch (_) {}
        return null;
      }
    });
  }

  Future<void> write({required WrappedResult result}) {
    return _lock.synchronized(() async {
      final File file = await _cacheFileForYear(result.year);
      try {
        await file.writeAsString(result.encode(), flush: true);
        _logger.info(
          "Persisted Wrapped cache for ${result.year} at ${file.path}",
        );
      } catch (error, stackTrace) {
        _logger.severe(
          "Failed to persist Wrapped cache for ${result.year}",
          error,
          stackTrace,
        );
      }
    });
  }

  Future<void> clear({required int year}) {
    return _lock.synchronized(() async {
      final File file = await _cacheFileForYear(year);
      if (await file.exists()) {
        try {
          await file.delete();
          _logger.info("Deleted Wrapped cache for $year at ${file.path}");
        } catch (error, stackTrace) {
          _logger.warning(
            "Failed to delete Wrapped cache for $year",
            error,
            stackTrace,
          );
        }
      }
    });
  }

  Future<void> clearAll() {
    return _lock.synchronized(() async {
      final Directory directory = await _cacheDirectoryPath();
      if (!await directory.exists()) {
        _cacheDirectory = null;
        return;
      }
      try {
        await directory.delete(recursive: true);
        _logger.info("Deleted Wrapped cache directory at ${directory.path}");
      } catch (error, stackTrace) {
        _logger.warning(
          "Failed to delete Wrapped cache directory at ${directory.path}",
          error,
          stackTrace,
        );
      } finally {
        _cacheDirectory = null;
      }
    });
  }
}
