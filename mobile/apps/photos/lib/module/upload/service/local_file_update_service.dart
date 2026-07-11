import 'dart:async';

import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import 'package:photos/core/errors.dart';
import 'package:photos/db/file_updation_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/file.dart';
import "package:photos/module/upload/upload_data.dart";
import 'package:shared_preferences/shared_preferences.dart';

/// Finds device files whose contents changed after upload and queues updates.
class LocalFileUpdateService {
  static final instance = LocalFileUpdateService._privateConstructor();

  static const _oldMigrationKeys = [
    'fm_badCreationTime',
    'fm_badCreationTimeCompleted',
    'fm_missingLocationV2ImportDone',
    'fm_missingLocationV2MigrationDone',
    'fm_badLocationImportDone',
    'fm_badLocationMigrationDone',
    'fm_ios_live_photo_size',
    'fm_import_ios_live_photo_size',
    'fm_ios_live_photo_check',
    'fm_import_ios_live_photo_check',
    'fm_android_missing_gps_check_done',
  ];

  final FileUpdationDB _fileUpdationDB = FileUpdationDB.instance;
  final Logger _logger = Logger("LocalFileUpdateService");
  late SharedPreferences _prefs;

  Completer<void>? _existingMigration;

  LocalFileUpdateService._privateConstructor();

  void init(SharedPreferences preferences) {
    _prefs = preferences;
  }

  Future<void> markUpdatedFilesForReUpload() async {
    if (_existingMigration != null) {
      _logger.info("migration is already in progress, skipping");
      return _existingMigration!.future;
    }
    _existingMigration = Completer<void>();
    try {
      await _markFilesWhichAreActuallyUpdated();
      _cleanUpOlderMigration().ignore();
    } catch (e, s) {
      _logger.severe('failed to perform migration', e, s);
    } finally {
      _existingMigration?.complete();
      _existingMigration = null;
    }
  }

  Future<void> _cleanUpOlderMigration() async {
    // check if any old_migration_keys are present in shared preferences
    bool hasOldMigrationKey = false;
    for (String key in _oldMigrationKeys) {
      if (_prefs.containsKey(key)) {
        hasOldMigrationKey = true;
        break;
      }
    }
    if (hasOldMigrationKey) {
      await _fileUpdationDB.deleteByReasons([
        'missing_location',
        'badCreationTime',
        'missingLocationV2',
        'badLocationCord',
        'livePhotoSize',
        'livePhotoCheck',
        'androidMissingGPS',
      ]);
      for (var element in _oldMigrationKeys) {
        await _prefs.remove(element);
      }
    }
  }

  // This method analyses all of local files for which the file
  // modification/update time was changed. It checks if the existing fileHash
  // is different from the hash of uploaded file. If fileHash are different,
  // then it marks the file for file update.
  Future<void> _markFilesWhichAreActuallyUpdated() async {
    final sTime = DateTime.now().microsecondsSinceEpoch;
    // singleRunLimit indicates number of files to check during single
    // invocation of this method. The limit act as a crude way to limit the
    // resource consumed by the method
    const int singleRunLimit = 10;
    final localIDsToProcess = await _fileUpdationDB
        .getLocalIDsForPotentialReUpload(
          singleRunLimit,
          FileUpdationDB.modificationTimeUpdated,
        );
    if (localIDsToProcess.isNotEmpty) {
      await _checkAndMarkFilesWithDifferentHashForFileUpdate(localIDsToProcess);
      final eTime = DateTime.now().microsecondsSinceEpoch;
      final d = Duration(microseconds: eTime - sTime);
      _logger.info(
        'Performed hashCheck for ${localIDsToProcess.length} updated files '
        'completed in ${d.inSeconds.toString()} secs',
      );
    }
  }

  Future<void> _checkAndMarkFilesWithDifferentHashForFileUpdate(
    List<String> localIDsToProcess,
  ) async {
    final int userID = Configuration.instance.getUserID()!;
    final List<EnteFile> result = await FilesDB.instance.getLocalFiles(
      localIDsToProcess,
    );
    final List<EnteFile> localFilesForUser = [];
    final Set<String> localIDsWithFile = {};
    for (EnteFile file in result) {
      if (file.ownerID == null || file.ownerID == userID) {
        localFilesForUser.add(file);
        localIDsWithFile.add(file.localID!);
      }
    }

    final Set<String> processedIDs = {};
    // if a file for localID doesn't exist, then mark it as processed
    // otherwise the app will be stuck in retrying same set of ids
    for (String localID in localIDsToProcess) {
      if (!localIDsWithFile.contains(localID)) {
        processedIDs.add(localID);
      }
    }
    _logger.info(
      "files to process ${localIDsToProcess.length} for reupload, "
      "missing localFile cnt ${processedIDs.length}",
    );

    for (EnteFile file in localFilesForUser) {
      if (processedIDs.contains(file.localID)) {
        continue;
      }
      if (!file.isUploaded) {
        _logger.info("File ${file.tag} is not uploaded, skipping hash check");
        processedIDs.add(file.localID!);
        continue;
      }
      try {
        final contentIdentity = await getFileContentIdentity(file);
        if (file.hash != null &&
            (file.hash == contentIdentity.fileHash ||
                file.hash == contentIdentity.zipHash)) {
          _logger.info("Skip file update as hash matched ${file.tag}");
        } else {
          _logger.info(
            "Marking for file update as hash did not match ${file.tag}",
          );
          await clearCache(file);
          await FilesDB.instance.markFilesForReUpload(
            userID,
            file.localID!,
            file.title,
            file.location,
            file.creationTime!,
            file.modificationTime!,
            file.fileType,
          );
        }
        processedIDs.add(file.localID!);
      } on InvalidFileError catch (e) {
        if (e.reason == InvalidReason.livePhotoToImageTypeChanged ||
            e.reason == InvalidReason.imageToLivePhotoTypeChanged) {
          late FileType fileType;
          if (e.reason == InvalidReason.livePhotoToImageTypeChanged) {
            fileType = FileType.image;
          } else if (e.reason == InvalidReason.imageToLivePhotoTypeChanged) {
            fileType = FileType.livePhoto;
          }
          await FilesDB.instance.markFilesForReUpload(
            userID,
            file.localID!,
            file.title,
            file.location,
            file.creationTime!,
            file.modificationTime!,
            fileType,
          );
          _logger.info('fileType changed for ${file.tag} to ${e.reason} for ');
        } else {
          _logger.severe("failed to check hash: invalid file ${file.tag}", e);
        }
        processedIDs.add(file.localID!);
      } catch (e, s) {
        _logger.severe("Failed to check hash", e, s);
      }
    }
    await _fileUpdationDB.deleteByLocalIDs(
      processedIDs.toList(),
      FileUpdationDB.modificationTimeUpdated,
    );
  }
}
