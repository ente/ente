import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/db/upload_locks_db.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/upload/upload_artifact.dart';
import 'package:synchronized/synchronized.dart';

class UploadArtifactLifecycle {
  UploadArtifactLifecycle(this._uploadLocks, this._filesDB);

  final UploadLocksDB _uploadLocks;
  final FilesDB _filesDB;
  final _logger = Logger('UploadArtifactLifecycle');
  final _cleanupLock = Lock();
  int _activeForceUploads = 0;

  Future<T> runForceUpload<T>(Future<T> Function() upload) async {
    await _cleanupLock.synchronized(() => _activeForceUploads++);
    try {
      return await upload();
    } finally {
      await _cleanupLock.synchronized(() => _activeForceUploads--);
    }
  }

  Future<void> removeStaleFiles() {
    return _cleanupLock.synchronized(() async {
      if (_activeForceUploads > 0) {
        _logger.info('Force upload is active, skipping stale file cleanup');
        return;
      }
      try {
        await _removeStaleUploadFiles();
        if (Platform.isAndroid) {
          await _removeStaleSharedMediaFiles();
        }
      } catch (e, s) {
        _logger.severe('Failed to remove stale files', e, s);
      }
    });
  }

  Future<void> _removeStaleUploadFiles() async {
    final tempDirectory = Configuration.instance.getTempDirectory();
    final files = await Directory(tempDirectory).list().toList();
    final filesToDelete = files
        .whereType<File>()
        .where((file) => isUploadTempArtifactPath(file.path))
        .toList();
    if (filesToDelete.isEmpty) {
      return;
    }

    _logger.info('Deleting ${filesToDelete.length} stale upload files');
    final fileNameToLastAttempt = await _uploadLocks
        .getFileNameToLastAttemptedAtMap();
    final now = DateTime.now();
    for (final file in filesToDelete) {
      final fileName = p.basename(file.path);
      final lastAttemptedAt = fileNameToLastAttempt[fileName];
      final lastAttemptTime = lastAttemptedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastAttemptedAt);
      if (lastAttemptTime == null ||
          now.difference(lastAttemptTime).inDays > 1) {
        await _deleteIfPresent(file);
      } else {
        _logger.info(
          'Skipping file $fileName as it was attempted recently on '
          '$lastAttemptTime',
        );
      }
    }
  }

  Future<void> _removeStaleSharedMediaFiles() async {
    final sharedMediaDirectory =
        '${Configuration.instance.getSharedMediaDirectory()}/';
    final sharedFiles = await Directory(sharedMediaDirectory).list().toList();
    if (sharedFiles.isEmpty) {
      return;
    }

    _logger.info('Shared media directory cleanup ${sharedFiles.length}');
    final ownerID = Configuration.instance.getUserID()!;
    final existingLocalFileIDs = await _filesDB.getExistingLocalFileIDs(
      ownerID,
    );
    final trackedSharedFilePaths = <String>{};
    for (final localID in existingLocalFileIDs) {
      if (localID.contains(sharedMediaIdentifier)) {
        trackedSharedFilePaths.add(getSharedMediaPathFromLocalID(localID));
      }
    }
    for (final file in sharedFiles) {
      if (!trackedSharedFilePaths.contains(file.path)) {
        _logger.info('Deleting stale shared media file ${file.path}');
        await _deleteIfPresent(file);
      }
    }
  }

  Future<void> _deleteIfPresent(FileSystemEntity file) async {
    final deleted = await deleteFileSystemEntityIfPresent(file);
    if (!deleted) {
      _logger.info('Stale file already missing during cleanup: ${file.path}');
    }
  }
}
