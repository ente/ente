import 'dart:io';

import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _offlineEncryptedDirName = 'offline_documents';
const _openHandoffDirName = 'open_handoff';
final _logger = Logger('OfflineFileStorage');

String _safeExtension(String fileName) {
  final ext = p.extension(p.basename(fileName));
  if (ext.isEmpty) return '';
  final sanitized = ext.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  return sanitized == '.' ? '' : sanitized;
}

String getCachedEncryptedFilePath(EnteFile file) {
  final String cacheDir = Configuration.instance.getCacheDirectory();
  return "$cacheDir${file.uploadedFileID}.encrypted";
}

String getPreferredFileExtension(
  EnteFile? file, {
  String? fallbackPath,
  String? fallbackName,
}) {
  final titleExtension = _safeExtension(file?.title ?? '');
  if (titleExtension.isNotEmpty) {
    return titleExtension;
  }

  final nameExtension = _safeExtension(fallbackName ?? file?.displayName ?? '');
  if (nameExtension.isNotEmpty) {
    return nameExtension;
  }

  final pathExtension = _safeExtension(fallbackPath ?? '');
  if (pathExtension.isNotEmpty) {
    return pathExtension;
  }

  return '';
}

String getCachedDecryptedFilePath(EnteFile file) {
  final String cacheDir = Configuration.instance.getCacheDirectory();
  final String extension = getPreferredFileExtension(file);
  return "$cacheDir${file.uploadedFileID}.decrypted$extension";
}

String getOpenHandoffDirectoryPath() {
  return p.join(
    Configuration.instance.getCacheDirectory(),
    _openHandoffDirName,
  );
}

Future<Directory> _getOfflineEncryptedDirectory() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(
    p.join(supportDirectory.path, _offlineEncryptedDirName),
  );
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  return directory;
}

Future<String> getOfflineEncryptedFilePath(EnteFile file) async {
  final directory = await _getOfflineEncryptedDirectory();
  return p.join(directory.path, '${file.uploadedFileID}.encrypted');
}

Future<File?> getCurrentOfflineEncryptedCopy(EnteFile file) async {
  final finalPath = await getOfflineEncryptedFilePath(file);
  final encryptedFile = File(finalPath);
  if (await encryptedFile.exists()) {
    final encryptedSize = await encryptedFile.length();
    if (encryptedSize > 0) {
      return encryptedFile;
    }
    _logger.warning(
      'Deleting empty offline encrypted copy for ${file.uploadedFileID}',
    );
    await encryptedFile.delete();
  }

  return null;
}

Future<void> removeOfflineFileCopiesFromDisk(
  Iterable<int> fileIds, {
  bool removeWorkingCopies = true,
}) async {
  final ids = fileIds.toSet();
  if (ids.isEmpty) {
    return;
  }

  _logger.fine(
    'Removing offline file copies for ${ids.length} files'
    ' (removeWorkingCopies=$removeWorkingCopies)',
  );

  await _deleteOfflineEncryptedCopies(ids);

  if (!removeWorkingCopies) {
    return;
  }

  await _deleteCachedFileCopies(ids);
  await _deleteOpenHandoffCopies(ids);
}

Future<void> clearAllOfflineFileCopies() async {
  _logger.info('Clearing all offline file copies');
  await _deleteOfflineEncryptedCopies();
  await _deleteCachedFileCopies(null);
  await _deleteOpenHandoffCopies();
}

Future<void> cleanupStaleOfflineFileCopies({
  Duration olderThan = Duration.zero,
}) async {
  _logger.fine('Cleaning stale offline file copies older than $olderThan');
  await _deleteCachedFileCopies(null, olderThan: olderThan);
  await _cleanupStaleOpenHandoffCopies(olderThan: olderThan);
}

int? _parseEncryptedFileId(String baseName) {
  final match = RegExp(r'^(\d+)\.encrypted$').firstMatch(baseName);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

int? _parseCachedDecryptedFileId(String baseName) {
  final match = RegExp(r'^(\d+)\.decrypted(?:\.[^.]+)?$').firstMatch(baseName);
  if (match == null) {
    return null;
  }
  return int.tryParse(match.group(1)!);
}

int? _parseCachedFileId(String baseName) {
  return _parseEncryptedFileId(baseName) ??
      _parseCachedDecryptedFileId(baseName);
}

Future<void> _deleteOfflineEncryptedCopies([Set<int>? ids]) async {
  final directory = await _getOfflineEncryptedDirectory();
  await _deleteMatchingFiles(
    directory,
    shouldDelete: (baseName) {
      if (ids == null) {
        return true;
      }

      final fileId = _parseEncryptedFileId(baseName);
      return fileId != null && ids.contains(fileId);
    },
  );
}

Future<void> _deleteCachedFileCopies(
  Set<int>? ids, {
  Duration olderThan = Duration.zero,
}) async {
  // The cache directory is shared; only Locker's ID-keyed working files belong here.
  final cacheDirectory = Directory(Configuration.instance.getCacheDirectory());
  await _deleteMatchingFiles(
    cacheDirectory,
    shouldDelete: (baseName) {
      final fileId = _parseCachedFileId(baseName);
      return fileId != null && (ids == null || ids.contains(fileId));
    },
    olderThan: olderThan,
  );
}

Future<void> _deleteOpenHandoffCopies([Set<int>? ids]) async {
  final handoffDirectory = Directory(getOpenHandoffDirectoryPath());
  if (!await handoffDirectory.exists()) {
    return;
  }

  if (ids == null) {
    await _deleteImmediateChildren(handoffDirectory, shouldDelete: (_) => true);
    return;
  }

  await _deleteImmediateChildren(
    handoffDirectory,
    shouldDelete: (entity) {
      if (entity is! Directory) {
        return false;
      }
      final fileId = int.tryParse(p.basename(entity.path));
      return fileId != null && ids.contains(fileId);
    },
  );
}

Future<void> _cleanupStaleOpenHandoffCopies({
  Duration olderThan = Duration.zero,
}) async {
  final handoffDirectory = Directory(getOpenHandoffDirectoryPath());
  if (!await handoffDirectory.exists()) {
    return;
  }

  final now = DateTime.now();
  await for (final fileIdEntity in handoffDirectory.list(followLinks: false)) {
    // Handoffs are open_handoff/<fileId>/<timestamp>/<display-name>.
    // Age the timestamp entries, not the long-lived fileId parent.
    if (fileIdEntity is! Directory) {
      await _deleteIfEligible(fileIdEntity, now: now, olderThan: olderThan);
      continue;
    }

    await for (final handoffEntity in fileIdEntity.list(followLinks: false)) {
      await _deleteIfEligible(handoffEntity, now: now, olderThan: olderThan);
    }

    if (await _isDirectoryEmpty(fileIdEntity)) {
      await _deleteEntity(fileIdEntity);
    }
  }
}

Future<void> _deleteMatchingFiles(
  Directory directory, {
  required bool Function(String baseName) shouldDelete,
  Duration olderThan = Duration.zero,
}) async {
  if (!await directory.exists()) {
    return;
  }

  final now = DateTime.now();
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }

    final baseName = p.basename(entity.path);
    if (!shouldDelete(baseName)) {
      continue;
    }

    await _deleteIfEligible(entity, now: now, olderThan: olderThan);
  }
}

Future<void> _deleteImmediateChildren(
  Directory directory, {
  required bool Function(FileSystemEntity entity) shouldDelete,
  Duration olderThan = Duration.zero,
}) async {
  if (!await directory.exists()) {
    return;
  }

  final now = DateTime.now();
  await for (final entity in directory.list(followLinks: false)) {
    if (!shouldDelete(entity)) {
      continue;
    }

    await _deleteIfEligible(entity, now: now, olderThan: olderThan);
  }
}

Future<bool> _isDirectoryEmpty(Directory directory) async {
  try {
    await for (final _ in directory.list(followLinks: false)) {
      return false;
    }
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _isEligibleForDeletion(
  FileSystemEntity entity, {
  required DateTime now,
  required Duration olderThan,
}) async {
  if (olderThan <= Duration.zero) {
    return true;
  }

  try {
    final stat = await entity.stat();
    return now.difference(stat.modified) >= olderThan;
  } catch (_) {
    return false;
  }
}

Future<void> _deleteIfEligible(
  FileSystemEntity entity, {
  required DateTime now,
  required Duration olderThan,
}) async {
  if (await _isEligibleForDeletion(entity, now: now, olderThan: olderThan)) {
    await _deleteEntity(entity);
  }
}

Future<void> _deleteEntity(FileSystemEntity entity) async {
  try {
    await entity.delete(recursive: entity is Directory);
  } catch (e, s) {
    _logger.warning('Failed to delete file copy ${entity.path}', e, s);
  }
}
