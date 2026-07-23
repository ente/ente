import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/freeable_space_info.dart';
import 'package:photos/models/upload_strategy.dart';
import "package:photos/services/sync/import/model.dart";
import 'package:sqflite/sqlite_api.dart';
import 'package:tuple/tuple.dart';

extension DeviceFiles on FilesDB {
  static final Logger _logger = Logger("DeviceFilesDB");
  static const _sqlBoolTrue = 1;
  static const _sqlBoolFalse = 0;

  Future<void> insertPathIDToLocalIDMapping(
    Map<String, Set<String>> mappingToAdd, {
    ConflictAlgorithm conflictAlgorithm = ConflictAlgorithm.ignore,
  }) async {
    debugPrint("Inserting missing PathIDToLocalIDMapping");
    final parameterSets = <List<Object?>>[];
    int batchCounter = 0;
    for (MapEntry e in mappingToAdd.entries) {
      final String pathID = e.key;
      for (String localID in e.value) {
        parameterSets.add([localID, pathID]);
        batchCounter++;

        if (batchCounter == 400) {
          await _insertBatch(parameterSets, conflictAlgorithm);
          parameterSets.clear();
          batchCounter = 0;
        }
      }
    }
    await _insertBatch(parameterSets, conflictAlgorithm);
    parameterSets.clear();
    batchCounter = 0;
  }

  Future<void> deletePathIDToLocalIDMapping(
    Map<String, Set<String>> mappingsToRemove,
  ) async {
    debugPrint("removing PathIDToLocalIDMapping");
    final parameterSets = <List<Object?>>[];
    int batchCounter = 0;
    for (MapEntry e in mappingsToRemove.entries) {
      final String pathID = e.key;

      for (String localID in e.value) {
        parameterSets.add([localID, pathID]);
        batchCounter++;

        if (batchCounter == 400) {
          await _deleteBatch(parameterSets);
          parameterSets.clear();
          batchCounter = 0;
        }
      }
    }
    await _deleteBatch(parameterSets);
    parameterSets.clear();
    batchCounter = 0;
  }

  Future<Map<String, int>> getDevicePathIDToImportedFileCount() async {
    try {
      final db = await sqliteAsyncDB;
      final rows = await db.getAll('''
      SELECT count(*) as count, path_id
      FROM device_files
      GROUP BY path_id
    ''');
      final result = <String, int>{};
      for (final row in rows) {
        result[row['path_id'] as String] = row["count"] as int;
      }
      return result;
    } catch (e) {
      _logger.severe("failed to getDevicePathIDToImportedFileCount", e);
      rethrow;
    }
  }

  Future<Map<String, Set<String>>> getDevicePathIDToLocalIDMap() async {
    try {
      final db = await sqliteAsyncDB;
      final rows = await db.getAll(
        ''' SELECT id, path_id FROM device_files; ''',
      );
      final result = <String, Set<String>>{};
      for (final row in rows) {
        final String pathID = row['path_id'] as String;
        if (!result.containsKey(pathID)) {
          result[pathID] = <String>{};
        }
        result[pathID]!.add(row['id'] as String);
      }
      return result;
    } catch (e) {
      _logger.severe("failed to getDevicePathIDToLocalIDMap", e);
      rethrow;
    }
  }

  Future<List<String>> getDeviceCollectionNamesForLocalID(
    String localID,
  ) async {
    final db = await sqliteAsyncDB;
    final rows = await db.getAll(
      '''
      SELECT dc.name as name
      FROM device_files df
      INNER JOIN device_collections dc ON dc.id = df.path_id
      WHERE df.id = ?
      ORDER BY dc.name COLLATE NOCASE ASC
      ''',
      [localID],
    );

    final names = <String>{};
    for (final row in rows) {
      final name = (row["name"] as String?)?.trim();
      if (name != null && name.isNotEmpty) {
        names.add(name);
      }
    }

    return names.toList(growable: false);
  }

  Future<Set<String>> getDevicePathIDs() async {
    final db = await sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT id FROM device_collections
      ''');
    final Set<String> result = <String>{};
    for (final row in rows) {
      result.add(row['id'] as String);
    }
    return result;
  }

  Future<void> insertLocalAssets(
    List<LocalPathAsset> localPathAssets, {
    bool shouldAutoBackup = false,
  }) async {
    final db = await sqliteAsyncDB;
    final Map<String, Set<String>> pathIDToLocalIDsMap = {};
    try {
      final Set<String> existingPathIds = await getDevicePathIDs();
      final parameterSetsForUpdate = <List<Object?>>[];
      final parameterSetsForInsert = <List<Object?>>[];
      for (LocalPathAsset localPathAsset in localPathAssets) {
        if (localPathAsset.localIDs.isNotEmpty) {
          pathIDToLocalIDsMap[localPathAsset.pathID] = localPathAsset.localIDs;
        }
        if (existingPathIds.contains(localPathAsset.pathID)) {
          parameterSetsForUpdate.add([
            localPathAsset.pathName,
            localPathAsset.pathID,
          ]);
        } else if (localPathAsset.localIDs.isNotEmpty) {
          parameterSetsForInsert.add([
            localPathAsset.pathID,
            localPathAsset.pathName,
            shouldAutoBackup ? _sqlBoolTrue : _sqlBoolFalse,
          ]);
        }
      }

      await db.executeBatch('''
        INSERT OR IGNORE INTO device_collections (id, name, should_backup) VALUES (?, ?, ?);
      ''', parameterSetsForInsert);

      await db.executeBatch('''
        UPDATE device_collections SET name = ? WHERE id = ?;
      ''', parameterSetsForUpdate);

      // add the mappings for localIDs
      if (pathIDToLocalIDsMap.isNotEmpty) {
        await insertPathIDToLocalIDMapping(pathIDToLocalIDsMap);
      }
    } catch (e) {
      _logger.severe("failed to save path names", e);
      rethrow;
    }
  }

  Future<bool> updateDeviceCoverWithCount(
    List<Tuple2<AssetPathEntity, String>> devicePathInfo, {
    bool shouldBackup = false,
  }) async {
    bool hasUpdated = false;
    try {
      final db = await sqliteAsyncDB;
      final Set<String> existingPathIds = await getDevicePathIDs();
      for (Tuple2<AssetPathEntity, String> tup in devicePathInfo) {
        final AssetPathEntity pathEntity = tup.item1;
        final assetCount = await pathEntity.assetCountAsync;
        final String localID = tup.item2;
        final int modifiedAt =
            pathEntity.lastModified?.microsecondsSinceEpoch ?? 0;
        final bool shouldUpdate = existingPathIds.contains(pathEntity.id);
        if (shouldUpdate) {
          final rowUpdated = await db.writeTransaction((tx) async {
            await tx.execute(
              "UPDATE device_collections SET name = ?, cover_id = ?, count"
              " = ?, modified_at = ? where id = ? AND (name != ? OR "
              "cover_id != ? OR count != ? OR modified_at != ?)",
              [
                pathEntity.name,
                localID,
                assetCount,
                modifiedAt,
                pathEntity.id,
                pathEntity.name,
                localID,
                assetCount,
                modifiedAt,
              ],
            );
            final result = await tx.get("SELECT changes();");
            return result["changes()"] as int;
          });

          if (rowUpdated > 0) {
            _logger.info("Updated $rowUpdated rows for ${pathEntity.name}");
            hasUpdated = true;
          }
        } else {
          hasUpdated = true;
          await db.execute(
            '''
            INSERT INTO device_collections (id, name, count, cover_id, modified_at, should_backup)
            VALUES (?, ?, ?, ?, ?, ?);
          ''',
            [
              pathEntity.id,
              pathEntity.name,
              assetCount,
              localID,
              modifiedAt,
              shouldBackup ? _sqlBoolTrue : _sqlBoolFalse,
            ],
          );
        }
      }
      // delete existing pathIDs which are missing on device
      existingPathIds.removeAll(devicePathInfo.map((e) => e.item1.id).toSet());
      if (existingPathIds.isNotEmpty) {
        hasUpdated = true;
        _logger.info(
          'Deleting non-backed up pathIds from local '
          '$existingPathIds',
        );
        for (String pathID in existingPathIds) {
          // do not delete device collection entries for paths which are
          // marked for backup. This is to handle "Free up space"
          // feature, where we delete files which are backed up. Deleting such
          // entries here result in us losing out on the information that
          // those folders were marked for automatic backup.
          await db.execute(
            '''
            DELETE FROM device_collections WHERE id = ? AND should_backup = $_sqlBoolFalse;
          ''',
            [pathID],
          );
          await db.execute(
            '''
            DELETE FROM device_files WHERE path_id = ?;
          ''',
            [pathID],
          );
        }
      }
      return hasUpdated;
    } catch (e) {
      _logger.severe("failed to save path names", e);
      rethrow;
    }
  }

  // getDeviceSyncCollectionIDs returns the collectionIDs for the
  // deviceCollections which are marked for auto-backup
  Future<Set<int>> getDeviceSyncCollectionIDs() async {
    final db = await sqliteAsyncDB;
    final rows = await db.getAll('''
      SELECT collection_id FROM device_collections where should_backup =
      $_sqlBoolTrue
      and collection_id != -1;
      ''');
    final Set<int> result = <int>{};
    for (final row in rows) {
      result.add(row['collection_id'] as int);
    }
    return result;
  }

  Future<void> updateDevicePathSyncStatus(Map<String, bool> syncStatus) async {
    final db = await sqliteAsyncDB;
    int batchCounter = 0;
    final parameterSets = <List<Object?>>[];
    for (MapEntry e in syncStatus.entries) {
      final String pathID = e.key;
      parameterSets.add([e.value ? _sqlBoolTrue : _sqlBoolFalse, pathID]);
      batchCounter++;

      if (batchCounter == 400) {
        await db.executeBatch('''
          UPDATE device_collections SET should_backup = ? WHERE id = ?;
        ''', parameterSets);
        parameterSets.clear();
        batchCounter = 0;
      }
    }

    await db.executeBatch('''
          UPDATE device_collections SET should_backup = ? WHERE id = ?;
        ''', parameterSets);
  }

  Future<void> updateDeviceCollection(String pathID, int collectionID) async {
    final db = await sqliteAsyncDB;
    await db.execute(
      '''
      UPDATE device_collections SET collection_id = ? WHERE id = ?;
    ''',
      [collectionID, pathID],
    );
    return;
  }

  Future<FileLoadResult> getFilesInDeviceCollection(
    DeviceCollection deviceCollection,
    int? ownerID,
    int startTime,
    int endTime, {
    int? limit,
    bool? asc,
  }) async {
    final db = await sqliteAsyncDB;
    final order = (asc ?? false ? 'ASC' : 'DESC');
    final String rawQuery =
        '''
    SELECT *
          FROM ${FilesDB.filesTable}
          WHERE ${FilesDB.columnLocalID} IS NOT NULL AND
          ${FilesDB.columnCreationTime} >= $startTime AND
          ${FilesDB.columnCreationTime} <= $endTime AND
          (${FilesDB.columnOwnerID} IS NULL OR ${FilesDB.columnOwnerID} =
          $ownerID ) AND
          ${FilesDB.columnLocalID} IN
          (SELECT id FROM device_files where path_id = '${deviceCollection.id}' )
          ORDER BY ${FilesDB.columnCreationTime} $order , ${FilesDB.columnModificationTime} $order
         ''' +
        (limit != null ? ' limit $limit;' : ';');
    final results = await db.getAll(rawQuery);
    final files = convertToFiles(results);
    final dedupe = deduplicateByLocalID(files);
    return FileLoadResult(dedupe, files.length == limit);
  }

  Future<FreeableFileIDs> getFreeableFileIDsForDeviceCollection(
    String pathID,
    int ownerID, {
    Set<String> excludeLocalIDs = const {},
  }) async {
    final db = await sqliteAsyncDB;
    const String rawQuery =
        '''
    SELECT ${FilesDB.columnLocalID}, ${FilesDB.columnUploadedFileID},
    ${FilesDB.columnFileSize}
    FROM ${FilesDB.filesTable}
          WHERE ${FilesDB.columnLocalID} IS NOT NULL AND
          (${FilesDB.columnOwnerID} IS NULL OR ${FilesDB.columnOwnerID} = ?)
          AND (${FilesDB.columnUploadedFileID} IS NOT NULL AND ${FilesDB.columnUploadedFileID} IS NOT -1)
          AND ${FilesDB.columnUpdationTime} IS NOT NULL
          AND
          ${FilesDB.columnLocalID} IN
          (SELECT id FROM device_files where path_id = ?)
          ''';
    final results = await db.getAll(rawQuery, [ownerID, pathID]);
    final localIDs = <String>{};
    final uploadedIDs = <int>{};
    int localSize = 0;
    for (final result in results) {
      final String localID = result[FilesDB.columnLocalID] as String;
      if (excludeLocalIDs.contains(localID)) continue;
      final int? fileSize = result[FilesDB.columnFileSize] as int?;
      if (!localIDs.contains(localID) && fileSize != null) {
        localSize += fileSize;
      }
      localIDs.add(localID);
      uploadedIDs.add(result[FilesDB.columnUploadedFileID] as int);
    }
    return FreeableFileIDs(localIDs.toList(), uploadedIDs.toList(), localSize);
  }

  Future<List<DeviceCollection>> getDeviceCollections({
    bool includeCoverThumbnail = false,
  }) async {
    debugPrint(
      "Fetching DeviceCollections From DB with thumbnail = "
      "$includeCoverThumbnail",
    );
    try {
      final db = await sqliteAsyncDB;
      final coverFiles = <EnteFile>[];
      if (includeCoverThumbnail) {
        final fileRows = await db.getAll(
          '''SELECT * FROM FILES where local_id in (select cover_id from device_collections) group by local_id;
          ''',
        );
        final files = convertToFiles(fileRows);
        coverFiles.addAll(files);
      }
      final deviceCollectionRows = await db.getAll(
        '''SELECT * from device_collections''',
      );
      final List<DeviceCollection> deviceCollections = [];
      for (var row in deviceCollectionRows) {
        final DeviceCollection deviceCollection = DeviceCollection(
          row["id"] as String,
          (row['name'] ?? '') as String,
          count: row['count'] as int,
          collectionID: (row["collection_id"] ?? -1) as int,
          coverId: row["cover_id"] as String?,
          modifiedAt: (row["modified_at"] ?? 0) as int,
          shouldBackup: (row["should_backup"] ?? _sqlBoolFalse) == _sqlBoolTrue,
          uploadStrategy: getUploadType((row["upload_strategy"] ?? 0) as int),
        );
        if (includeCoverThumbnail) {
          deviceCollection.thumbnail = coverFiles.firstWhereOrNull(
            (element) => element.localID == deviceCollection.coverId,
          );
          if (deviceCollection.thumbnail == null) {
            final EnteFile? result = await getDeviceCollectionThumbnail(
              deviceCollection.id,
            );
            if (result == null) {
              _logger.info('Failed to find coverThumbnail for deviceFolder');
              continue;
            } else {
              deviceCollection.thumbnail = result;
            }
          }
        }
        deviceCollections.add(deviceCollection);
      }
      if (includeCoverThumbnail) {
        deviceCollections.sort(
          (a, b) =>
              b.thumbnail!.creationTime!.compareTo(a.thumbnail!.creationTime!),
        );
      }
      return deviceCollections;
    } catch (e) {
      _logger.severe('Failed to getDeviceCollections', e);
      rethrow;
    }
  }

  Future<EnteFile?> getDeviceCollectionThumbnail(String pathID) async {
    debugPrint("Call fallback method to get potential thumbnail");
    final db = await sqliteAsyncDB;
    final fileRows = await db.getAll(
      '''SELECT * FROM FILES  f JOIN device_files df on f.local_id = df.id
      and df.path_id= ? order by f.creation_time DESC limit 1;
          ''',
      [pathID],
    );
    final files = convertToFiles(fileRows);
    if (files.isNotEmpty) {
      return files.first;
    } else {
      return null;
    }
  }

  Future<void> _insertBatch(
    List<List<Object?>> parameterSets,
    ConflictAlgorithm conflictAlgorithm,
  ) async {
    final db = await sqliteAsyncDB;
    await db.executeBatch('''
        INSERT OR ${conflictAlgorithm.name.toUpperCase()}
        INTO device_files (id, path_id) VALUES (?, ?);
      ''', parameterSets);
  }

  Future<void> _deleteBatch(List<List<Object?>> parameterSets) async {
    final db = await sqliteAsyncDB;
    await db.executeBatch('''
        DELETE FROM device_files WHERE id = ? AND path_id = ?;
      ''', parameterSets);
  }
}
