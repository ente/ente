import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import "package:photos/core/errors.dart";
import 'package:photos/db/ignored_files_db.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/ignored_file.dart';

class IgnoredFilesService {
  final _logger = Logger("IgnoredFilesService");
  final _db = IgnoredFilesDB.instance;

  IgnoredFilesService._privateConstructor();

  static final IgnoredFilesService instance =
      IgnoredFilesService._privateConstructor();

  Future<Map<String, String>>? _idsToReasonMap;

  Future<Map<String, String>> get idToIgnoreReasonMap async {
    // lazily instantiate the db the first time it is accessed
    _idsToReasonMap ??= _loadIDsToReasonMap();
    return _idsToReasonMap!;
  }

  Future<void> cacheAndInsert(List<IgnoredFile> ignoredFiles) async {
    final existingIDs = await idToIgnoreReasonMap;
    for (IgnoredFile iFile in ignoredFiles) {
      final id = _idForIgnoredFile(iFile);
      if (id != null) {
        existingIDs[id] = iFile.reason;
      }
    }
    return _db.insertMultiple(ignoredFiles);
  }

  // shouldSkipUpload takes IDs to ignore and file for which it will return
  // whether either true or false. This helper method takes ignoredIDs as input
  // to avoid making it async in nature.
  // This syntax is intentional as we want to ensure that ignoredIDs are loaded
  // from the DB before calling this method.
  bool shouldSkipUpload(Map<String, String> idToReasonMap, EnteFile file) {
    final id = _getIgnoreID(file.localID, file.deviceFolder, file.title);
    if (id != null && id.isNotEmpty) {
      return idToReasonMap.containsKey(id);
    }
    return false;
  }

  String? getUploadSkipReason(
    Map<String, String> idToReasonMap,
    EnteFile file,
  ) {
    final id = _getIgnoreID(file.localID, file.deviceFolder, file.title);
    if (id != null && id.isNotEmpty) {
      return idToReasonMap[id];
    }
    return null;
  }

  Future<bool> shouldSkipUploadAsync(EnteFile file) async {
    final ignoredID = await idToIgnoreReasonMap;
    return shouldSkipUpload(ignoredID, file);
  }

  // removeIgnoredMappings is used to remove the ignore mapping for the given
  // set of files so that they can be uploaded.
  Future<void> removeIgnoredMappings(List<EnteFile> files) async {
    final List<IgnoredFile> ignoredFiles = [];
    final Set<String> idsToRemoveFromCache = {};
    final Map<String, String> currentlyIgnoredIDs = await idToIgnoreReasonMap;
    for (final file in files) {
      // check if upload is not skipped for file. If not, no need to remove
      // any mapping
      if (!shouldSkipUpload(currentlyIgnoredIDs, file)) {
        continue;
      }
      // _shouldSkipUpload checks for null ignoreID
      final id = _getIgnoreID(file.localID, file.deviceFolder, file.title)!;
      idsToRemoveFromCache.add(id);
      ignoredFiles.add(
        IgnoredFile(file.localID, file.title, file.deviceFolder, ""),
      );
    }

    if (ignoredFiles.isNotEmpty) {
      await _db.removeIgnoredEntries(ignoredFiles);
      for (final id in idsToRemoveFromCache) {
        currentlyIgnoredIDs.remove(id);
      }
    }
  }

  Future<void> reset() async {
    await _db.clearTable();
    _idsToReasonMap = null;
  }

  Future<Map<String, String>> _loadIDsToReasonMap() async {
    _logger.info('loading existing IDs');
    final dbResult = await _db.getAll();
    final Map<String, String> result = <String, String>{};
    for (IgnoredFile iFile in dbResult) {
      final id = _idForIgnoredFile(iFile);
      if (id != null) {
        if (Platform.isIOS &&
            iFile.reason == InvalidReason.sourceFileMissing.name) {
          // ignoreSourceFileMissing error on iOS as the file fetch from iCloud might have failed,
          // but the file might be available later
          continue;
        }
        result[id] = iFile.reason;
      }
    }
    return result;
  }

  String? _idForIgnoredFile(IgnoredFile ignoredFile) {
    return _getIgnoreID(
      ignoredFile.localID,
      ignoredFile.deviceFolder,
      ignoredFile.title,
    );
  }

  String? getIgnoredIDForFile(EnteFile file) {
    return _getIgnoreID(file.localID, file.deviceFolder, file.title);
  }

  // _getIgnoreID will return null if don't have sufficient information
  // to ignore the file based on the platform. Uploads from web or files shared to
  // end usually don't have local id.
  // For Android: It returns deviceFolder-title as ID for Android.
  // For iOS, it returns localID as localID is uuid and the title or deviceFolder (aka
  // album name) can be missing due to various reasons.
  String? _getIgnoreID(String? localID, String? deviceFolder, String? title) {
    // file was not uploaded from mobile device
    if (localID == null || localID.isEmpty) {
      return null;
    }
    if (Platform.isAndroid) {
      if (deviceFolder == null || title == null) {
        return null;
      }
      return '$localID-$deviceFolder-$title';
    } else {
      return localID;
    }
  }
}
