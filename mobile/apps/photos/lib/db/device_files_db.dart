import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/db/common/conflict_algo.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file_load_result.dart';
import 'package:photos/models/freeable_space_info.dart';
import 'package:photos/models/upload_strategy.dart';
import "package:photos/services/sync/import/model.dart";
import 'package:tuple/tuple.dart';

extension DeviceFiles on FilesDB {
  static final Logger _logger = Logger("DeviceFilesDB");
  static const _sqlBoolTrue = 1;
  static const _sqlBoolFalse = 0;

  Future<void> insertPathIDToLocalIDMapping(
    Map<String, Set<String>> mappingToAdd, {
    SqliteAsyncConflictAlgorithm conflictAlgorithm =
        SqliteAsyncConflictAlgorithm.ignore,
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

  Future<Set<String>> getLocalIDsInDeviceCollection(
    Iterable<String> localIDs,
    String pathID,
  ) async {
    final ids = localIDs.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await sqliteAsyncDB;
    final result = <String>{};
    for (final batch in ids.slices(900)) {
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await db.getAll(
        'SELECT id FROM device_files '
        'WHERE path_id = ? AND id IN ($placeholders)',
        [pathID, ...batch],
      );
      result.addAll(rows.map((row) => row['id'] as String));
    }
    return result;
  }

  Future<Map<String, Set<String>>> getDevicePathIDsForLocalIDs(
    Iterable<String> localIDs,
  ) async {
    final ids = localIDs.toSet().toList(growable: false);
    if (ids.isEmpty) return const {};
    final db = await sqliteAsyncDB;
    final result = <String, Set<String>>{};
    for (final batch in ids.slices(900)) {
      final placeholders = List.filled(batch.length, '?').join(',');
      final rows = await db.getAll(
        'SELECT id, path_id FROM device_files '
        'WHERE id IN ($placeholders)',
        batch,
      );
      for (final row in rows) {
        final localID = row['id'] as String;
        result
            .putIfAbsent(localID, () => <String>{})
            .add(row['path_id'] as String);
      }
    }
    return result;
  }

  Future<Set<String>> getLocalIDsInBackupFolders(
    Set<String> localIDs,
    Set<int> excludedCollectionIDs,
  ) async {
    if (localIDs.isEmpty) return {};

    final db = await sqliteAsyncDB;
    final localIDPlaceholders = List.filled(localIDs.length, '?').join(',');
    final rows = await db.getAll('''
      SELECT DISTINCT df.id, dc.collection_id
      FROM device_files df
      INNER JOIN device_collections dc ON dc.id = df.path_id
      WHERE dc.should_backup = $_sqlBoolTrue
        AND df.id IN ($localIDPlaceholders)
      ''', localIDs.toList(growable: false));
    return rows
        .where((row) => !excludedCollectionIDs.contains(row['collection_id']))
        .map((row) => row['id'] as String)
        .toSet();
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
        final updatedRows = await db.execute(
          '''
            INSERT INTO device_collections (id, name, count, cover_id, modified_at, should_backup)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name = excluded.name,
              count = excluded.count,
              cover_id = excluded.cover_id,
              modified_at = excluded.modified_at
            WHERE device_collections.name IS NOT excluded.name
              OR device_collections.count IS NOT excluded.count
              OR device_collections.cover_id IS NOT excluded.cover_id
              OR device_collections.modified_at IS NOT excluded.modified_at
            RETURNING id;
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
        if (updatedRows.isNotEmpty) {
          _logger.info(
            "Updated ${updatedRows.length} rows for ${pathEntity.name}",
          );
          hasUpdated = true;
        }
      }
      existingPathIds.removeAll(devicePathInfo.map((e) => e.item1.id).toSet());
      if (existingPathIds.isNotEmpty) {
        _logger.info(
          'Deleting non-backed up pathIds from local '
          '$existingPathIds',
        );
        for (String pathID in existingPathIds) {
          // Keep folder backup settings after Free up space deletes their files.
          final deletedRows = await db.execute(
            '''
            DELETE FROM device_collections WHERE id = ? AND should_backup = $_sqlBoolFalse
            RETURNING id;
          ''',
            [pathID],
          );
          hasUpdated |= deletedRows.isNotEmpty;
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
    SqliteAsyncConflictAlgorithm conflictAlgorithm,
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
