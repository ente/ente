import "dart:math";

import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import "package:photos/db/common/base.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/db_model_mappers.dart";
import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/db/ml/ml_data_db_orchestration.dart";
import 'package:photos/db/ml/schema.dart';
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import 'package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart';
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/utils/ml_util.dart";
import 'package:sqlite_async/sqlite_async.dart';

class DartMLDataDB
    with SqlDbBase, MLDataDBOrchestration
    implements IMLDataDB<int> {
  static final Logger _logger = Logger("MLDataDB");
  static const int _maxSqlBindParamsPerQuery = 10000;

  final String _databaseName;
  final ClipVectorDB _clipVectorDB;
  final ClusterCentroidVectorDB _clusterCentroidVectorDB;
  final bool _isLocalGallery;
  final List<String> _migrationScripts;

  DartMLDataDB._privateConstructor({
    String databaseName = "ente.ml.db",
    ClipVectorDB? clipVectorDB,
    ClusterCentroidVectorDB? clusterCentroidVectorDB,
    bool isLocalGallery = false,
    List<String>? migrationScripts,
  }) : _databaseName = databaseName,
       _clipVectorDB = clipVectorDB ?? ClipVectorDB.instance,
       _clusterCentroidVectorDB =
           clusterCentroidVectorDB ?? ClusterCentroidVectorDB.instance,
       _isLocalGallery = isLocalGallery,
       _migrationScripts = migrationScripts ?? _defaultMigrationScripts;

  static final DartMLDataDB instance = DartMLDataDB._privateConstructor();
  static final DartMLDataDB localGalleryInstance =
      DartMLDataDB._privateConstructor(
        databaseName: "ente.ml.offline.db",
        clipVectorDB: ClipVectorDB.localGalleryInstance,
        clusterCentroidVectorDB: ClusterCentroidVectorDB.localGalleryInstance,
        isLocalGallery: true,
        migrationScripts: _localGalleryMigrationScripts,
      );

  static const List<String> _defaultMigrationScripts = [
    createFacesTable,
    createFaceClustersTable,
    createClusterPersonTable,
    createClusterSummaryTable,
    createNotPersonFeedbackTable,
    fcClusterIDIndex,
    createClipEmbeddingsTable,
    createFileDataTable,
    createFaceCacheTable,
    createTextEmbeddingsCacheTable,
    createClusterCentroidVectorIdMappingTable,
    createPetFacesTable,
    createPetBodiesTable,
    createPetFaceVectorIdMappingTable,
    createPetBodyVectorIdMappingTable,
  ];
  static const List<String> _localGalleryMigrationScripts = [
    ..._defaultMigrationScripts,
  ];

  @override
  ClipVectorDB get clipVectorDB => _clipVectorDB;

  @override
  ClusterCentroidVectorDB get clusterCentroidVectorDB =>
      _clusterCentroidVectorDB;

  @override
  bool get isLocalGallery => _isLocalGallery;

  @override
  Logger get logger => _logger;

  Future<SqliteDatabase> get asyncDB =>
      getOrOpenDatabase(_initSqliteAsyncDatabase);

  Future<SqliteDatabase> _initSqliteAsyncDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String databaseDirectory = join(
      documentsDirectory.path,
      _databaseName,
    );
    _logger.info("Opening sqlite_async access: DB path " + databaseDirectory);
    final asyncDBConnection = SqliteDatabase(
      path: databaseDirectory,
      maxReaders: 2,
    );
    try {
      final stopwatch = Stopwatch()..start();
      _logger.info("MLDataDB: Starting migration");
      await migrate(asyncDBConnection, _migrationScripts);
      _logger.info(
        "MLDataDB Migration took ${stopwatch.elapsedMilliseconds} ms",
      );
      stopwatch.stop();

      return asyncDBConnection;
    } catch (_) {
      await asyncDBConnection.close();
      rethrow;
    }
  }

  Iterable<List<T>> _chunkList<T>(List<T> values, int chunkSize) sync* {
    for (int i = 0; i < values.length; i += chunkSize) {
      final end = min(i + chunkSize, values.length);
      yield values.sublist(i, end);
    }
  }

  // Batch to stay below SQLite's bind-variable limit.
  @override
  Future<void> bulkInsertFaces(List<Face> faces) async {
    final db = await asyncDB;
    const batchSize = 500;
    final numBatches = (faces.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, faces.length);
      final batch = faces.sublist(start, end);

      const String sql =
          '''
        INSERT INTO $facesTable (
          $fileIDColumn, $faceIDColumn, $faceDetectionColumn, $embeddingColumn, $faceScore, $faceBlur, $isSideways, $imageHeight, $imageWidth, $mlVersionColumn
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT($fileIDColumn, $faceIDColumn) DO UPDATE SET $faceIDColumn = excluded.$faceIDColumn, $faceDetectionColumn = excluded.$faceDetectionColumn, $embeddingColumn = excluded.$embeddingColumn, $faceScore = excluded.$faceScore, $faceBlur = excluded.$faceBlur, $isSideways = excluded.$isSideways, $imageHeight = excluded.$imageHeight, $imageWidth = excluded.$imageWidth, $mlVersionColumn = excluded.$mlVersionColumn
      ''';
      final parameterSets = batch.map((face) {
        final map = mapRemoteToFaceDB(face);
        return [
          map[fileIDColumn],
          map[faceIDColumn],
          map[faceDetectionColumn],
          map[embeddingColumn],
          map[faceScore],
          map[faceBlur],
          map[isSideways],
          map[imageHeight],
          map[imageWidth],
          map[mlVersionColumn],
        ];
      }).toList();

      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<void> bulkInsertPetFaces(List<DBPetFace> petFaces) async {
    final db = await asyncDB;
    const batchSize = 500;
    final numBatches = (petFaces.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, petFaces.length);
      final batch = petFaces.sublist(start, end);

      const String sql =
          '''
        INSERT INTO $petFacesTable (
          $fileIDColumn, $petFaceIDColumn, $faceDetectionColumn, $faceVectorIdColumn, $speciesColumn, $faceScore, $imageHeight, $imageWidth, $mlVersionColumn
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT($fileIDColumn, $petFaceIDColumn) DO UPDATE SET $faceDetectionColumn = excluded.$faceDetectionColumn, $faceVectorIdColumn = excluded.$faceVectorIdColumn, $speciesColumn = excluded.$speciesColumn, $faceScore = excluded.$faceScore, $imageHeight = excluded.$imageHeight, $imageWidth = excluded.$imageWidth, $mlVersionColumn = excluded.$mlVersionColumn
      ''';
      final parameterSets = batch.map((petFace) {
        final map = petFace.toMap();
        return [
          map[fileIDColumn],
          map[petFaceIDColumn],
          map[faceDetectionColumn],
          map[faceVectorIdColumn],
          map[speciesColumn],
          map[faceScore],
          map[imageHeight],
          map[imageWidth],
          map[mlVersionColumn],
        ];
      }).toList();

      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<void> bulkInsertPetBodies(List<DBPetBody> petBodies) async {
    final db = await asyncDB;
    const batchSize = 500;
    final numBatches = (petBodies.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, petBodies.length);
      final batch = petBodies.sublist(start, end);

      const String sql =
          '''
        INSERT INTO $petBodiesTable (
          $fileIDColumn, $petBodyIDColumn, $detectionColumn, $bodyVectorIdColumn, $speciesColumn, $bodyScore, $imageHeight, $imageWidth, $mlVersionColumn
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT($fileIDColumn, $petBodyIDColumn) DO UPDATE SET $detectionColumn = excluded.$detectionColumn, $bodyVectorIdColumn = excluded.$bodyVectorIdColumn, $speciesColumn = excluded.$speciesColumn, $bodyScore = excluded.$bodyScore, $imageHeight = excluded.$imageHeight, $imageWidth = excluded.$imageWidth, $mlVersionColumn = excluded.$mlVersionColumn
      ''';
      final parameterSets = batch.map((obj) {
        final map = obj.toMap();
        return [
          map[fileIDColumn],
          map[petBodyIDColumn],
          map[detectionColumn],
          map[bodyVectorIdColumn],
          map[speciesColumn],
          map[bodyScore],
          map[imageHeight],
          map[imageWidth],
          map[mlVersionColumn],
        ];
      }).toList();

      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<void> updatePetFaceVectorIds(
    Map<String, int> petFaceIdToVectorId,
  ) async {
    if (petFaceIdToVectorId.isEmpty) return;
    final db = await asyncDB;
    const batchSize = 500;
    final entries = petFaceIdToVectorId.entries.toList();
    final numBatches = (entries.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, entries.length);
      final batch = entries.sublist(start, end);

      const String sql =
          '''
        UPDATE $petFacesTable
        SET $faceVectorIdColumn = ?
        WHERE $petFaceIDColumn = ?
      ''';
      final parameterSets = batch.map((e) => [e.value, e.key]).toList();
      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<void> updatePetBodyVectorIds(
    Map<String, int> petBodyIdToVectorId,
  ) async {
    if (petBodyIdToVectorId.isEmpty) return;
    final db = await asyncDB;
    const batchSize = 500;
    final entries = petBodyIdToVectorId.entries.toList();
    final numBatches = (entries.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, entries.length);
      final batch = entries.sublist(start, end);

      const String sql =
          '''
        UPDATE $petBodiesTable
        SET $bodyVectorIdColumn = ?
        WHERE $petBodyIDColumn = ?
      ''';
      final parameterSets = batch.map((e) => [e.value, e.key]).toList();
      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<Map<String, int>> getPetFaceVectorIdMap(
    Iterable<String> petFaceIds, {
    bool createIfMissing = false,
  }) async {
    final uniqueIds = petFaceIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) return {};

    final db = await asyncDB;
    if (createIfMissing) {
      const insertSql =
          '''
        INSERT OR IGNORE INTO $petFaceVectorIdMappingTable ($petFaceIDColumn)
        VALUES (?)
      ''';
      final insertParams = <List<Object?>>[];
      for (final id in uniqueIds) {
        insertParams.add([id]);
      }
      await db.executeBatch(insertSql, insertParams);
    }

    final result = <String, int>{};
    const chunkSize = 800;
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final chunk = uniqueIds.sublist(i, min(i + chunkSize, uniqueIds.length));
      final rows = await db.getAll('''
          SELECT $petFaceIDColumn, $petFaceVectorIdColumn
          FROM $petFaceVectorIdMappingTable
          WHERE $petFaceIDColumn IN (${List.filled(chunk.length, '?').join(',')})
        ''', chunk);
      for (final row in rows) {
        result[row[petFaceIDColumn] as String] =
            row[petFaceVectorIdColumn] as int;
      }
    }
    return result;
  }

  @override
  Future<Map<String, int>> getPetBodyVectorIdMap(
    Iterable<String> petBodyIds, {
    bool createIfMissing = false,
  }) async {
    final uniqueIds = petBodyIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) return {};

    final db = await asyncDB;
    if (createIfMissing) {
      const insertSql =
          '''
        INSERT OR IGNORE INTO $petBodyVectorIdMappingTable ($petBodyIDColumn)
        VALUES (?)
      ''';
      final insertParams = <List<Object?>>[];
      for (final id in uniqueIds) {
        insertParams.add([id]);
      }
      await db.executeBatch(insertSql, insertParams);
    }

    final result = <String, int>{};
    const chunkSize = 800;
    for (int i = 0; i < uniqueIds.length; i += chunkSize) {
      final chunk = uniqueIds.sublist(i, min(i + chunkSize, uniqueIds.length));
      final rows = await db.getAll('''
          SELECT $petBodyIDColumn, $petBodyVectorIdColumn
          FROM $petBodyVectorIdMappingTable
          WHERE $petBodyIDColumn IN (${List.filled(chunk.length, '?').join(',')})
        ''', chunk);
      for (final row in rows) {
        result[row[petBodyIDColumn] as String] =
            row[petBodyVectorIdColumn] as int;
      }
    }
    return result;
  }

  @override
  Future<void> updateFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async {
    final db = await asyncDB;
    const batchSize = 500;
    final numBatches = (faceIDToClusterID.length / batchSize).ceil();
    for (int i = 0; i < numBatches; i++) {
      final start = i * batchSize;
      final end = min((i + 1) * batchSize, faceIDToClusterID.length);
      final batch = faceIDToClusterID.entries.toList().sublist(start, end);

      const String sql =
          '''
        INSERT INTO $faceClustersTable ($faceIDColumn, $clusterIDColumn)
        VALUES (?, ?)
        ON CONFLICT($faceIDColumn) DO UPDATE SET $clusterIDColumn = excluded.$clusterIDColumn
      ''';
      final parameterSets = batch.map((e) => [e.key, e.value]).toList();

      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<Map<int, int>> faceIndexedFileIds({
    int minimumMlVersion = faceMlVersion,
  }) async {
    final db = await asyncDB;
    final String query =
        '''
        SELECT $fileIDColumn, $mlVersionColumn
        FROM $facesTable
        WHERE $mlVersionColumn >= $minimumMlVersion
      ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query);
    final Map<int, int> result = {};
    for (final map in maps) {
      result[map[fileIDColumn] as int] = map[mlVersionColumn] as int;
    }
    return result;
  }

  @override
  Future<int> getFaceIndexedFileCount({
    int minimumMlVersion = faceMlVersion,
  }) async {
    final db = await asyncDB;
    final String query =
        'SELECT COUNT(DISTINCT $fileIDColumn) as count FROM $facesTable WHERE $mlVersionColumn >= $minimumMlVersion';
    final List<Map<String, dynamic>> maps = await db.getAll(query);
    return maps.first['count'] as int;
  }

  @override
  Future<Map<String, int>> clusterIdToFaceCount() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn, COUNT(*) as count FROM $faceClustersTable where $clusterIDColumn IS NOT NULL GROUP BY $clusterIDColumn ',
    );
    final Map<String, int> result = {};
    for (final map in maps) {
      result[map[clusterIDColumn] as String] = map['count'] as int;
    }
    return result;
  }

  @override
  Future<Set<String>> getBadFaceSingletonClusterIDs() async {
    final db = await asyncDB;
    final rows = await db.getAll('''
      SELECT fc.$clusterIDColumn, f.$faceScore, f.$faceBlur, f.$isSideways
      FROM $faceClustersTable fc
      INNER JOIN $facesTable f
        ON fc.$faceIDColumn = f.$faceIDColumn
      GROUP BY fc.$clusterIDColumn
      HAVING COUNT(*) = 1
      ''');
    final badClusterIDs = <String>{};
    for (final row in rows) {
      final badFace = isBadFaceForClustering(
        faceScore: row[faceScore] as double,
        blurValue: row[faceBlur] as double,
        isSideways: (row[isSideways] as int) == 1,
      );
      if (badFace) {
        badClusterIDs.add(row[clusterIDColumn] as String);
      }
    }
    return badClusterIDs;
  }

  @override
  Future<Set<String>> getClustersWithThreeOrMoreNotPersonFeedback() async {
    final db = await asyncDB;
    final rows = await db.getAll('''
      SELECT $clusterIDColumn
      FROM $notPersonFeedback
      GROUP BY $clusterIDColumn
      HAVING COUNT(*) >= 3
      ''');
    return rows.map((row) => row[clusterIDColumn] as String).toSet();
  }

  @override
  Future<Set<String>> getPersonIgnoredClusters(String personID) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> otherPersonMaps = await db.getAll(
      'SELECT $clusterIDColumn FROM $clusterPersonTable WHERE $personIdColumn != ? AND $personIdColumn IS NOT NULL',
      [personID],
    );
    final Set<String> ignoredClusterIDs = otherPersonMaps
        .map((e) => e[clusterIDColumn] as String)
        .toSet();
    final List<Map<String, dynamic>> rejectMaps = await db.getAll(
      'SELECT $clusterIDColumn FROM $notPersonFeedback WHERE $personIdColumn = ?',
      [personID],
    );
    final Set<String> rejectClusterIDs = rejectMaps
        .map((e) => e[clusterIDColumn] as String)
        .toSet();
    return ignoredClusterIDs.union(rejectClusterIDs);
  }

  @override
  Future<Map<String, Set<String>>> getPersonToRejectedSuggestions() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> rejectMaps = await db.getAll(
      'SELECT $personIdColumn, $clusterIDColumn FROM $notPersonFeedback',
    );
    final Map<String, Set<String>> result = {};
    for (final map in rejectMaps) {
      final personID = map[personIdColumn] as String;
      final clusterID = map[clusterIDColumn] as String;
      result.putIfAbsent(personID, () => {}).add(clusterID);
    }
    return result;
  }

  @override
  Future<Set<String>> getPersonClusterIDs(String personID) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn FROM $clusterPersonTable WHERE $personIdColumn = ?',
      [personID],
    );
    return maps.map((e) => e[clusterIDColumn] as String).toSet();
  }

  @override
  Future<Set<String>> getPersonsClusterIDs(List<String> personID) async {
    final db = await asyncDB;
    final inParam = personID.map((e) => "'$e'").join(',');
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn FROM $clusterPersonTable WHERE $personIdColumn IN ($inParam)',
    );
    return maps.map((e) => e[clusterIDColumn] as String).toSet();
  }

  @override
  Future<void> clearNonPetTables() async {
    final db = await asyncDB;

    await db.execute(deleteFacesTable);
    await db.execute(deleteFaceClustersTable);
    await db.execute(deleteClusterPersonTable);
    await db.execute(deleteClusterSummaryTable);
    await db.execute(deleteClusterCentroidVectorIdMappingTable);
    await db.execute(deleteNotPersonFeedbackTable);
    await db.execute(deleteClipEmbeddingsTable);
    await db.execute(deleteFileDataTable);
  }

  @override
  Future<void> clearPetTables() async {
    final db = await asyncDB;
    await db.execute(deletePetFacesTable);
    await db.execute(deletePetBodiesTable);
    await db.execute(deletePetFaceVectorIdMappingTable);
    await db.execute(deletePetBodyVectorIdMappingTable);
  }

  @override
  Future<Iterable<Uint8List>> getFaceEmbeddingsForCluster(
    String clusterID, {
    int? limit,
  }) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $embeddingColumn FROM $facesTable WHERE  $faceIDColumn in (SELECT $faceIDColumn from $faceClustersTable where $clusterIDColumn = ?) ${limit != null ? 'LIMIT $limit' : ''}',
      [clusterID],
    );
    return maps.map((e) => e[embeddingColumn] as Uint8List);
  }

  @override
  Future<Map<String, Iterable<Uint8List>>> getFaceEmbeddingsForClusters(
    Iterable<String> clusterIDs, {
    int? limit,
  }) async {
    if (clusterIDs.isEmpty) {
      return {};
    }
    final db = await asyncDB;
    final Map<String, List<Uint8List>> result = {};
    final clusterIDList = clusterIDs.toSet().toList(growable: false);
    final maxClusterIDsPerQuery = limit != null
        ? _maxSqlBindParamsPerQuery - 1
        : _maxSqlBindParamsPerQuery;
    int? remainingLimit = limit;

    for (final clusterChunk in _chunkList(
      clusterIDList,
      maxClusterIDsPerQuery,
    )) {
      if (remainingLimit != null && remainingLimit <= 0) {
        break;
      }
      final selectQuery =
          '''
  SELECT fc.$clusterIDColumn, fe.$embeddingColumn
  FROM $faceClustersTable fc
  INNER JOIN $facesTable fe ON fc.$faceIDColumn = fe.$faceIDColumn
  WHERE fc.$clusterIDColumn IN (${SqlDbBase.getParams(clusterChunk.length)})
  ${remainingLimit != null ? 'LIMIT ?' : ''}
''';

      final List<dynamic> selectQueryParams = [...clusterChunk];
      if (remainingLimit != null) {
        selectQueryParams.add(remainingLimit);
      }

      final List<Map<String, dynamic>> maps = await db.getAll(
        selectQuery,
        selectQueryParams,
      );
      if (remainingLimit != null) {
        remainingLimit -= maps.length;
      }

      for (final map in maps) {
        final clusterID = map[clusterIDColumn] as String;
        final faceEmbedding = map[embeddingColumn] as Uint8List;
        result.putIfAbsent(clusterID, () => <Uint8List>[]).add(faceEmbedding);
      }
    }

    return result;
  }

  @override
  Future<Face?> getCoverFaceForPerson({
    required int recentFileID,
    String? personID,
    String? avatarFaceId,
    String? clusterID,
  }) async {
    final db = await asyncDB;
    if (personID != null) {
      final List<int> fileId = [recentFileID];
      int? avatarFileId;
      if (avatarFaceId != null) {
        avatarFileId = tryGetFileIdFromFaceId(avatarFaceId);
        if (avatarFileId != null) {
          fileId.add(avatarFileId);
        }
      }
      const String queryClusterID =
          '''
        SELECT $clusterIDColumn
        FROM $clusterPersonTable
        WHERE $personIdColumn = ?
      ''';
      final clusterRows = await db.getAll(queryClusterID, [personID]);
      final clusterIDs = clusterRows
          .map((e) => e[clusterIDColumn] as String)
          .toList();

      final List<Map<String, dynamic>> faceMaps = await db.getAll(
        '''
        SELECT * FROM $facesTable
        WHERE $faceIDColumn IN (
        SELECT $faceIDColumn
        FROM $faceClustersTable
        WHERE $clusterIDColumn IN (${List.filled(clusterIDs.length, '?').join(',')})
        )
        AND $fileIDColumn IN (${List.filled(fileId.length, '?').join(',')})
        ORDER BY $faceScore DESC
        ''',
        [...clusterIDs, ...fileId],
      );
      if (faceMaps.isNotEmpty) {
        if (avatarFileId != null) {
          final row = faceMaps.firstWhereOrNull(
            (element) => (element[fileIDColumn] as int) == avatarFileId,
          );
          if (row != null) {
            return mapRowToFace(row);
          }
        }
        return mapRowToFace(faceMaps.first);
      }
    }
    if (clusterID != null) {
      const String queryFaceID =
          '''
        SELECT $faceIDColumn
        FROM $faceClustersTable
        WHERE $clusterIDColumn = ?
      ''';
      final List<Map<String, dynamic>> faceMaps = await db.getAll(queryFaceID, [
        clusterID,
      ]);
      final List<Face>? faces = await getFacesForGivenFileID(recentFileID);
      if (faces != null) {
        for (final face in faces) {
          if (faceMaps.any(
            (element) => (element[faceIDColumn] as String) == face.faceID,
          )) {
            return face;
          }
        }
      }
    }
    if (personID == null && clusterID == null) {
      _logger.severe("personID and clusterID cannot be null both");
      throw Exception("personID and clusterID cannot be null");
    }
    _logger.severe(
      "Something went wrong finding a face from `getCoverFaceForPerson` (personID: $personID, clusterID: $clusterID)",
    );
    return null;
  }

  @override
  Future<List<Face>?> getFacesForGivenFileID(int fileUploadID) async {
    final db = await asyncDB;
    const String query =
        '''
      SELECT * FROM $facesTable
      WHERE $fileIDColumn = ?
    ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      fileUploadID,
    ]);
    if (maps.isEmpty) {
      return null;
    }
    return maps.map((e) => mapRowToFace(e)).toList();
  }

  @override
  Future<List<DBPetFace>?> getPetFacesForFileID(int fileUploadID) async {
    final db = await asyncDB;
    const String query =
        '''
      SELECT * FROM $petFacesTable
      WHERE $fileIDColumn = ? AND $speciesColumn != -1
    ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      fileUploadID,
    ]);
    if (maps.isEmpty) {
      return null;
    }
    return maps.map((e) => DBPetFace.fromMap(e)).toList();
  }

  @override
  Future<List<DBPetBody>?> getPetBodiesForFileID(int fileUploadID) async {
    final db = await asyncDB;
    const String query =
        '''
      SELECT * FROM $petBodiesTable
      WHERE $fileIDColumn = ? AND $speciesColumn != -1
    ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      fileUploadID,
    ]);
    if (maps.isEmpty) {
      return null;
    }
    return maps.map((e) => DBPetBody.fromMap(e)).toList();
  }

  @override
  Future<Map<int, List<FaceWithoutEmbedding>>>
  getFileIDsToFacesWithoutEmbedding() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll('''
      SELECT $faceIDColumn, $fileIDColumn, $faceScore, $faceDetectionColumn, $faceBlur FROM $facesTable
    ''');
    if (maps.isEmpty) {
      return {};
    }
    final result = <int, List<FaceWithoutEmbedding>>{};
    for (final map in maps) {
      final face = mapRowToFaceWithoutEmbedding(map);
      final fileID = map[fileIDColumn] as int;
      result.putIfAbsent(fileID, () => <FaceWithoutEmbedding>[]).add(face);
    }
    return result;
  }

  @override
  Future<Map<String, Iterable<String>>> getClusterToFaceIDs(
    Set<String> clusterIDs,
  ) async {
    if (clusterIDs.isEmpty) {
      return {};
    }
    final db = await asyncDB;
    final Map<String, List<String>> result = {};
    final clusterIDList = clusterIDs.toList(growable: false);

    for (final clusterChunk in _chunkList(
      clusterIDList,
      _maxSqlBindParamsPerQuery,
    )) {
      final List<Map<String, dynamic>> maps = await db.getAll('''
  SELECT $clusterIDColumn, $faceIDColumn
  FROM $faceClustersTable
  WHERE $clusterIDColumn IN (${SqlDbBase.getParams(clusterChunk.length)})
  ''', clusterChunk);

      for (final map in maps) {
        final clusterID = map[clusterIDColumn] as String;
        final faceID = map[faceIDColumn] as String;
        result.putIfAbsent(clusterID, () => <String>[]).add(faceID);
      }
    }
    return result;
  }

  @override
  Future<String?> getClusterIDForFaceID(String faceID) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn FROM $faceClustersTable WHERE $faceIDColumn = ?',
      [faceID],
    );
    if (maps.isEmpty) {
      return null;
    }
    return maps.first[clusterIDColumn] as String;
  }

  @override
  Future<Map<String, Iterable<String>>> getAllClusterIdToFaceIDs() async {
    final db = await asyncDB;
    final Map<String, List<String>> result = {};
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn, $faceIDColumn FROM $faceClustersTable',
    );
    for (final map in maps) {
      final clusterID = map[clusterIDColumn] as String;
      final faceID = map[faceIDColumn] as String;
      result.putIfAbsent(clusterID, () => <String>[]).add(faceID);
    }
    return result;
  }

  @override
  Future<Iterable<String>> getFaceIDsForCluster(String clusterID) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $faceIDColumn FROM $faceClustersTable '
      'WHERE $faceClustersTable.$clusterIDColumn = ?',
      [clusterID],
    );
    return maps.map((e) => e[faceIDColumn] as String).toSet();
  }

  @override
  Future<List<String>> getFaceIDsForClusterOrderedByScore(
    String clusterID, {
    int limit = 10,
  }) async {
    final db = await asyncDB;
    final faceIdsResult = await db.getAll(
      'SELECT $facesTable.$faceIDColumn FROM $facesTable '
      'JOIN $faceClustersTable ON $facesTable.$faceIDColumn = $faceClustersTable.$faceIDColumn '
      'WHERE $faceClustersTable.$clusterIDColumn = ? '
      'ORDER BY $facesTable.$faceScore DESC '
      'LIMIT ?',
      [clusterID, limit],
    );
    return faceIdsResult.map((e) => e[faceIDColumn] as String).toList();
  }

  @override
  Future<Map<String, Map<String, Set<String>>>>
  getPersonToClusterIdToFaceIds() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $personIdColumn, $faceClustersTable.$clusterIDColumn, $faceIDColumn FROM $clusterPersonTable '
      'INNER JOIN $faceClustersTable ON $clusterPersonTable.$clusterIDColumn = $faceClustersTable.$clusterIDColumn',
    );
    final Map<String, Map<String, Set<String>>> result = {};
    for (final map in maps) {
      final personID = map[personIdColumn] as String;
      final clusterID = map[clusterIDColumn] as String;
      final faceID = map[faceIDColumn] as String;
      result
          .putIfAbsent(personID, () => {})
          .putIfAbsent(clusterID, () => {})
          .add(faceID);
    }
    return result;
  }

  @override
  Future<Map<String, Set<String>>> getPersonToClusterIDs() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $personIdColumn, $clusterIDColumn FROM $clusterPersonTable',
    );
    final Map<String, Set<String>> result = {};
    for (final map in maps) {
      final personID = map[personIdColumn] as String;
      final clusterID = map[clusterIDColumn] as String;
      result.putIfAbsent(personID, () => {}).add(clusterID);
    }
    return result;
  }

  @override
  Future<Map<String, String>> getFaceIdToPersonIdForFaces(
    Iterable<String> faceIDs,
  ) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $faceIDColumn, $personIdColumn FROM $clusterPersonTable '
      'INNER JOIN $faceClustersTable ON $clusterPersonTable.$clusterIDColumn = $faceClustersTable.$clusterIDColumn '
      'WHERE $faceIDColumn IN (${faceIDs.map((id) => "'$id'").join(",")})',
    );
    final Map<String, String> result = {};
    for (final map in maps) {
      result[map[faceIDColumn] as String] = map[personIdColumn] as String;
    }
    return result;
  }

  @override
  Future<Map<String, Set<String>>> getClusterIdToFaceIdsForPerson(
    String personID,
  ) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $faceClustersTable.$clusterIDColumn, $faceIDColumn FROM $clusterPersonTable '
      'INNER JOIN $faceClustersTable ON $clusterPersonTable.$clusterIDColumn = $faceClustersTable.$clusterIDColumn '
      'WHERE $personIdColumn = ?',
      [personID],
    );
    final Map<String, Set<String>> result = {};
    for (final map in maps) {
      final clusterID = map[clusterIDColumn] as String;
      final faceID = map[faceIDColumn] as String;
      result.putIfAbsent(clusterID, () => {}).add(faceID);
    }
    return result;
  }

  @override
  Future<Set<String>> getFaceIDsForPerson(String personID) async {
    final db = await asyncDB;
    final faceIdsResult = await db.getAll(
      'SELECT $faceIDColumn FROM $faceClustersTable LEFT JOIN $clusterPersonTable '
      'ON $faceClustersTable.$clusterIDColumn = $clusterPersonTable.$clusterIDColumn '
      'WHERE $clusterPersonTable.$personIdColumn = ?',
      [personID],
    );
    return faceIdsResult.map((e) => e[faceIDColumn] as String).toSet();
  }

  @override
  Future<List<String>> getFaceIDsForPersonOrderedByScore(
    String personID, {
    int limit = 10,
  }) async {
    final db = await asyncDB;
    final faceIdsResult = await db.getAll(
      'SELECT $facesTable.$faceIDColumn FROM $facesTable '
      'JOIN $faceClustersTable ON $facesTable.$faceIDColumn = $faceClustersTable.$faceIDColumn '
      'JOIN $clusterPersonTable ON $faceClustersTable.$clusterIDColumn = $clusterPersonTable.$clusterIDColumn '
      'WHERE $clusterPersonTable.$personIdColumn = ? '
      'ORDER BY $facesTable.$faceScore DESC '
      'LIMIT ?',
      [personID, limit],
    );
    return faceIdsResult.map((e) => e[faceIDColumn] as String).toList();
  }

  @override
  Future<Iterable<double>> getBlurValuesForCluster(String clusterID) async {
    final db = await asyncDB;
    const String query =
        '''
        SELECT $facesTable.$faceBlur
        FROM $facesTable
        JOIN $faceClustersTable ON $facesTable.$faceIDColumn = $faceClustersTable.$faceIDColumn
        WHERE $faceClustersTable.$clusterIDColumn = ?
      ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [clusterID]);
    return maps.map((e) => e[faceBlur] as double).toSet();
  }

  @override
  Future<Map<String, String?>> getFaceIdsToClusterIds(
    Iterable<String> faceIds,
  ) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $faceIDColumn, $clusterIDColumn FROM $faceClustersTable where $faceIDColumn IN (${faceIds.map((id) => "'$id'").join(",")})',
    );
    final Map<String, String?> result = {};
    for (final map in maps) {
      result[map[faceIDColumn] as String] = map[clusterIDColumn] as String?;
    }
    return result;
  }

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIds() async {
    final Map<int, Set<String>> result = {};
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $clusterIDColumn, $faceIDColumn FROM $faceClustersTable',
    );

    for (final map in maps) {
      final clusterID = map[clusterIDColumn] as String;
      final faceID = map[faceIDColumn] as String;
      final fileID = getFileIdFromFaceId<int>(faceID);
      result[fileID] = (result[fileID] ?? {})..add(clusterID);
    }
    return result;
  }

  @override
  Future<void> forceUpdateClusterIds(
    Map<String, String> faceIDToClusterID,
  ) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $faceClustersTable ($faceIDColumn, $clusterIDColumn)
      VALUES (?, ?)
      ON CONFLICT($faceIDColumn) DO UPDATE SET $clusterIDColumn = excluded.$clusterIDColumn
    ''';
    final parameterSets = faceIDToClusterID.entries
        .map((e) => [e.key, e.value])
        .toList();
    await db.executeBatch(sql, parameterSets);
  }

  @override
  Future<void> removeFaceIdToClusterId(
    Map<String, String> faceIDToClusterID,
  ) async {
    final db = await asyncDB;
    const String sql =
        '''
      DELETE FROM $faceClustersTable
      WHERE $faceIDColumn = ? AND $clusterIDColumn = ?
    ''';
    final parameterSets = faceIDToClusterID.entries
        .map((e) => [e.key, e.value])
        .toList();
    await db.executeBatch(sql, parameterSets);
  }

  @override
  Future<void> removePerson(String personID) async {
    final db = await asyncDB;

    await db.writeTransaction((tx) async {
      try {
        await tx.execute(
          'DELETE FROM $clusterPersonTable WHERE $personIdColumn = ?',
          [personID],
        );
      } catch (e) {
        _logger.severe('Error in the first write of removePerson', e);
        rethrow;
      }
      try {
        await tx.execute(
          'DELETE FROM $notPersonFeedback WHERE $personIdColumn = ?',
          [personID],
        );
      } catch (e) {
        _logger.severe('Error in the second write of removePerson', e);
        rethrow;
      }
    });
  }

  @override
  Future<List<FaceDbInfoForClustering>> getFaceInfoForClustering({
    int maxFaces = 20000,
    int offset = 0,
    int batchSize = 10000,
  }) async {
    try {
      final EnteWatch w = EnteWatch("getFaceEmbeddingMap")..start();
      w.logAndReset(
        'reading as float offset: $offset, maxFaces: $maxFaces, batchSize: $batchSize',
      );
      final db = await asyncDB;

      final List<FaceDbInfoForClustering> result = <FaceDbInfoForClustering>[];
      while (true) {
        final List<Map<String, dynamic>> maps = await db.getAll(
          'SELECT $faceIDColumn, $embeddingColumn, $faceScore, $faceBlur, $isSideways FROM $facesTable'
          ' WHERE $faceScore > $kMinimumQualityFaceScore AND $faceBlur > $kLaplacianHardThreshold'
          ' ORDER BY $faceIDColumn'
          ' DESC LIMIT $batchSize OFFSET $offset',
        );
        if (maps.isEmpty) {
          break;
        }
        final List<String> faceIds = [];
        for (final map in maps) {
          faceIds.add(map[faceIDColumn] as String);
        }
        final faceIdToClusterId = await getFaceIdsToClusterIds(faceIds);
        for (final map in maps) {
          final faceID = map[faceIDColumn] as String;
          final faceInfo = FaceDbInfoForClustering(
            faceID: faceID,
            clusterId: faceIdToClusterId[faceID],
            embeddingBytes: map[embeddingColumn] as Uint8List,
            faceScore: map[faceScore] as double,
            blurValue: map[faceBlur] as double,
            isSideways: (map[isSideways] as int) == 1,
          );
          result.add(faceInfo);
        }
        if (result.length >= maxFaces) {
          break;
        }
        offset += batchSize;
      }
      w.stopWithLog('done reading face embeddings ${result.length}');
      return result;
    } catch (e) {
      _logger.severe('err in getFaceInfoForClustering', e);
      rethrow;
    }
  }

  @override
  Future<Map<String, Uint8List>> getFaceEmbeddingMapForFaces(
    Iterable<String> faceIDs,
  ) async {
    _logger.info('reading face embeddings for ${faceIDs.length} faces');
    final db = await asyncDB;

    const batchSize = 10000;
    int offset = 0;

    final Map<String, Uint8List> result = {};
    while (true) {
      final String query =
          '''
        SELECT $faceIDColumn, $embeddingColumn
        FROM $facesTable
        WHERE $faceIDColumn IN (${faceIDs.map((id) => "'$id'").join(",")})
        ORDER BY $faceIDColumn DESC
        LIMIT $batchSize OFFSET $offset
      ''';
      final List<Map<String, dynamic>> maps = await db.getAll(query);
      if (maps.isEmpty) {
        break;
      }
      for (final map in maps) {
        final faceID = map[faceIDColumn] as String;
        result[faceID] = map[embeddingColumn] as Uint8List;
      }
      if (result.length > 10000) {
        break;
      }
      offset += batchSize;
    }
    _logger.info('done reading face embeddings for ${faceIDs.length} faces');
    return result;
  }

  @override
  Future<int> getTotalFaceCount() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT COUNT(*) as count FROM $facesTable WHERE $faceScore > $kMinimumQualityFaceScore AND $faceBlur > $kLaplacianHardThreshold',
    );
    return maps.first['count'] as int;
  }

  @override
  Future<int> getErroredFaceCount() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT COUNT(*) as count FROM $facesTable WHERE $faceScore < 0',
    );
    return maps.first['count'] as int;
  }

  @override
  Future<Set<int>> getErroredFileIDs() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT DISTINCT $fileIDColumn FROM $facesTable WHERE $faceScore < 0',
    );
    return maps.map((e) => e[fileIDColumn] as int).toSet();
  }

  @override
  Future<void> pruneResolvedFaceErrorResults(List<int> fileIDs) async {
    if (fileIDs.isEmpty) return;
    final db = await asyncDB;
    for (final chunk in fileIDs.chunks(_maxSqlBindParamsPerQuery)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await db.execute('''
        DELETE FROM $facesTable
        WHERE $fileIDColumn IN ($placeholders)
          AND $faceScore < 0
          AND EXISTS (
            SELECT 1 FROM $facesTable AS successful
            WHERE successful.$fileIDColumn = $facesTable.$fileIDColumn
              AND successful.$faceScore >= 0
              AND successful.$mlVersionColumn >= $facesTable.$mlVersionColumn
          )
        ''', chunk);
    }
  }

  @override
  Future<Set<int>> getFileIDsWithErrorResults(List<int> fileIDs) async {
    if (fileIDs.isEmpty) return {};
    final db = await asyncDB;
    final result = <int>{};
    const chunkSize = _maxSqlBindParamsPerQuery ~/ 3;
    for (final chunk in fileIDs.chunks(chunkSize)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await db.getAll(
        '''
        SELECT failed.$fileIDColumn FROM $facesTable AS failed
        WHERE failed.$fileIDColumn IN ($placeholders)
          AND failed.$faceScore < 0
          AND NOT EXISTS (
            SELECT 1 FROM $facesTable AS successful
            WHERE successful.$fileIDColumn = failed.$fileIDColumn
              AND successful.$faceScore >= 0
              AND successful.$mlVersionColumn >= failed.$mlVersionColumn
          )
        UNION
        SELECT $fileIDColumn FROM $clipTable
        WHERE $fileIDColumn IN ($placeholders) AND LENGTH($embeddingColumn) = 0
        UNION
        SELECT $fileIDColumn FROM $petFacesTable
        WHERE $fileIDColumn IN ($placeholders) AND $faceScore < 0
        ''',
        [...chunk, ...chunk, ...chunk],
      );
      result.addAll(rows.map((row) => row[fileIDColumn] as int));
    }
    return result;
  }

  @override
  Future<void> deleteFaceIndexForFiles(List<int> fileIDs) async {
    final db = await asyncDB;
    final String sql =
        '''
      DELETE FROM $facesTable WHERE $fileIDColumn IN (${fileIDs.join(", ")})
    ''';
    await db.execute(sql);
  }

  @override
  Future<void> deleteUnclusteredFaceIndexForFiles(List<int> fileIDs) async {
    if (fileIDs.isEmpty) return;
    final db = await asyncDB;
    for (final chunk in fileIDs.chunks(_maxSqlBindParamsPerQuery)) {
      final placeholders = List.filled(chunk.length, '?').join(', ');
      await db.execute('''
        DELETE FROM $facesTable
        WHERE $fileIDColumn IN ($placeholders)
        AND NOT EXISTS (
          SELECT 1 FROM $faceClustersTable
          WHERE $faceClustersTable.$faceIDColumn = $facesTable.$faceIDColumn
        )
        ''', chunk);
    }
  }

  @override
  Future<int> getClusteredOrFacelessFileCount() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> clustered = await db.getAll(
      'SELECT $faceIDColumn FROM $faceClustersTable',
    );
    final Set<int> clusteredFileIDs = {};
    for (final map in clustered) {
      final int fileID = getFileIdFromFaceId<int>(map[faceIDColumn] as String);
      clusteredFileIDs.add(fileID);
    }

    final List<Map<String, dynamic>> badFacesFiles = await db.getAll(
      'SELECT DISTINCT $fileIDColumn FROM $facesTable WHERE $faceScore <= $kMinimumQualityFaceScore OR $faceBlur <= $kLaplacianHardThreshold',
    );
    final Set<int> badFileIDs = {};
    for (final map in badFacesFiles) {
      badFileIDs.add(map[fileIDColumn] as int);
    }

    final List<Map<String, dynamic>> goodFacesFiles = await db.getAll(
      'SELECT DISTINCT $fileIDColumn FROM $facesTable WHERE $faceScore > $kMinimumQualityFaceScore AND $faceBlur > $kLaplacianHardThreshold',
    );
    final Set<int> goodFileIDs = {};
    for (final map in goodFacesFiles) {
      goodFileIDs.add(map[fileIDColumn] as int);
    }
    final trulyFacelessFiles = badFileIDs.difference(goodFileIDs);
    return clusteredFileIDs.length + trulyFacelessFiles.length;
  }

  @override
  Future<double> getClusteredToIndexableFilesRatio() async {
    final int indexableFiles = await getIndexableFileCount();
    final int clusteredFiles = await getClusteredOrFacelessFileCount();

    return clusteredFiles / indexableFiles;
  }

  @override
  Future<int> getUnclusteredFaceCount() async {
    final db = await asyncDB;
    const String query =
        '''
      SELECT COUNT(*) as count
      FROM $facesTable f
      LEFT JOIN $faceClustersTable fc ON f.$faceIDColumn = fc.$faceIDColumn
      WHERE f.$faceScore > $kMinimumQualityFaceScore
      AND f.$faceBlur > $kLaplacianHardThreshold
      AND fc.$faceIDColumn IS NULL
    ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query);
    return maps.first['count'] as int;
  }

  // Existing people must go through ClusterFeedbackService instead.
  @override
  Future<void> assignClusterToPerson({
    required String personID,
    required String clusterID,
  }) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $clusterPersonTable ($personIdColumn, $clusterIDColumn) VALUES (?, ?) ON CONFLICT($personIdColumn, $clusterIDColumn) DO NOTHING
    ''';
    await db.execute(sql, [personID, clusterID]);
  }

  @override
  Future<void> bulkAssignClusterToPersonID(
    Map<String, String> clusterToPersonID,
  ) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $clusterPersonTable ($personIdColumn, $clusterIDColumn) VALUES (?, ?) ON CONFLICT($personIdColumn, $clusterIDColumn) DO NOTHING
    ''';
    final parameterSets = clusterToPersonID.entries
        .map((e) => [e.value, e.key])
        .toList();
    await db.executeBatch(sql, parameterSets);
  }

  @override
  Future<void> captureNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $notPersonFeedback ($personIdColumn, $clusterIDColumn) VALUES (?, ?) ON CONFLICT DO NOTHING
    ''';
    await db.execute(sql, [personID, clusterID]);
  }

  @override
  Future<void> bulkCaptureNotPersonFeedback(
    Map<String, String> clusterToPersonID,
  ) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $notPersonFeedback ($personIdColumn, $clusterIDColumn) VALUES (?, ?) ON CONFLICT DO NOTHING
    ''';
    final parameterSets = clusterToPersonID.entries
        .map((e) => [e.value, e.key])
        .toList();

    await db.executeBatch(sql, parameterSets);
  }

  @override
  Future<void> removeNotPersonFeedback({
    required String personID,
    required String clusterID,
  }) async {
    final db = await asyncDB;

    const String sql =
        '''
      DELETE FROM $notPersonFeedback WHERE $personIdColumn = ? AND $clusterIDColumn = ?
    ''';
    await db.execute(sql, [personID, clusterID]);
  }

  @override
  Future<void> removeClusterToPerson({
    required String personID,
    required String clusterID,
  }) async {
    final db = await asyncDB;

    const String sql =
        '''
      DELETE FROM $clusterPersonTable WHERE $personIdColumn = ? AND $clusterIDColumn = ?
    ''';
    await db.execute(sql, [personID, clusterID]);
  }

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSet(String personID) {
    final db = asyncDB;
    return db.then((db) async {
      final List<Map<String, dynamic>> maps = await db.getAll(
        'SELECT $faceClustersTable.$clusterIDColumn, $faceIDColumn FROM $faceClustersTable '
        'INNER JOIN $clusterPersonTable '
        'ON $faceClustersTable.$clusterIDColumn = $clusterPersonTable.$clusterIDColumn '
        'WHERE $clusterPersonTable.$personIdColumn = ?',
        [personID],
      );
      final Map<int, Set<String>> result = {};
      for (final map in maps) {
        final clusterID = map[clusterIDColumn] as String;
        final String faceID = map[faceIDColumn] as String;
        final fileID = getFileIdFromFaceId<int>(faceID);
        result[fileID] = (result[fileID] ?? {})..add(clusterID);
      }
      return result;
    });
  }

  @override
  Future<Map<int, Set<String>>> getFileIdToClusterIDSetForCluster(
    Set<String> clusterIDs,
  ) {
    final db = asyncDB;
    return db.then((db) async {
      final List<Map<String, dynamic>> maps = await db.getAll(
        '''
  SELECT $clusterIDColumn, $faceIDColumn
  FROM $faceClustersTable
  WHERE $clusterIDColumn IN (${List.filled(clusterIDs.length, '?').join(',')})
  ''',
        [...clusterIDs],
      );
      final Map<int, Set<String>> result = {};
      for (final map in maps) {
        final clusterID = map[clusterIDColumn] as String;
        final faceID = map[faceIDColumn] as String;
        final fileID = getFileIdFromFaceId<int>(faceID);
        result[fileID] = (result[fileID] ?? {})..add(clusterID);
      }
      return result;
    });
  }

  @override
  Future<Map<String, int>> getClusterCentroidVectorIdMap(
    Iterable<String> clusterIDs, {
    bool createIfMissing = false,
  }) async {
    final uniqueClusterIDs = clusterIDs.toSet().toList(growable: false);
    if (uniqueClusterIDs.isEmpty) {
      return {};
    }

    final db = await asyncDB;
    if (createIfMissing) {
      const insertSql =
          '''
        INSERT OR IGNORE INTO $clusterCentroidVectorIdMappingTable ($clusterIDColumn)
        VALUES (?)
      ''';
      final insertParams = <List<Object?>>[];
      for (final clusterID in uniqueClusterIDs) {
        insertParams.add([clusterID]);
      }
      await db.executeBatch(insertSql, insertParams);
    }

    final result = <String, int>{};
    const chunkSize = 800;
    for (int i = 0; i < uniqueClusterIDs.length; i += chunkSize) {
      final chunk = uniqueClusterIDs.sublist(
        i,
        min(i + chunkSize, uniqueClusterIDs.length),
      );
      final rows = await db.getAll('''
          SELECT $clusterIDColumn, $clusterCentroidVectorIdColumn
          FROM $clusterCentroidVectorIdMappingTable
          WHERE $clusterIDColumn IN (${List.filled(chunk.length, '?').join(',')})
        ''', chunk);
      for (final row in rows) {
        result[row[clusterIDColumn] as String] =
            row[clusterCentroidVectorIdColumn] as int;
      }
    }
    return result;
  }

  @override
  Future<void> deleteClusterCentroidVectorIdMapping(String clusterID) async {
    final db = await asyncDB;
    const deleteSql =
        '''
      DELETE FROM $clusterCentroidVectorIdMappingTable
      WHERE $clusterIDColumn = ?
    ''';
    await db.execute(deleteSql, [clusterID]);
  }

  @override
  Future<void> clearClusterCentroidVectorIdMappings() async {
    final db = await asyncDB;
    await db.execute(deleteClusterCentroidVectorIdMappingTable);
  }

  @override
  Future<void> upsertClusterSummaryRows(
    Map<String, (Uint8List, int)> summary,
  ) async {
    final db = await asyncDB;

    const String sql =
        '''
      INSERT INTO $clusterSummaryTable ($clusterIDColumn, $avgColumn, $countColumn) VALUES (?, ?, ?) ON CONFLICT($clusterIDColumn) DO UPDATE SET $avgColumn = excluded.$avgColumn, $countColumn = excluded.$countColumn
    ''';
    final List<List<Object?>> parameterSets = [];
    int batchCounter = 0;
    for (final entry in summary.entries) {
      if (batchCounter == 400) {
        await db.executeBatch(sql, parameterSets);
        batchCounter = 0;
        parameterSets.clear();
      }
      final String clusterID = entry.key;
      final int count = entry.value.$2;
      final Uint8List avg = entry.value.$1;
      parameterSets.add([clusterID, avg, count]);
      batchCounter++;
    }
    if (parameterSets.isNotEmpty) {
      await db.executeBatch(sql, parameterSets);
    }
  }

  @override
  Future<void> deleteClusterSummaryRow(String clusterID) async {
    final db = await asyncDB;
    const String sqlDelete =
        'DELETE FROM $clusterSummaryTable WHERE $clusterIDColumn = ?';
    await db.execute(sqlDelete, [clusterID]);
  }

  @override
  Future<Map<String, (Uint8List, int)>> getAllClusterSummary([
    int? minClusterSize,
  ]) async {
    final db = await asyncDB;
    final Map<String, (Uint8List, int)> result = {};
    final rows = await db.getAll(
      'SELECT * FROM $clusterSummaryTable${minClusterSize != null ? ' WHERE $countColumn >= $minClusterSize' : ''}',
    );
    for (final r in rows) {
      final id = r[clusterIDColumn] as String;
      final avg = r[avgColumn] as Uint8List;
      final count = r[countColumn] as int;
      result[id] = (avg, count);
    }
    return result;
  }

  @override
  Future<Map<String, (Uint8List, int)>> getClusterToClusterSummary(
    Iterable<String> clusterIDs,
  ) async {
    final db = await asyncDB;
    final Map<String, (Uint8List, int)> result = {};

    final rows = await db.getAll(
      'SELECT * FROM $clusterSummaryTable WHERE $clusterIDColumn IN (${List.filled(clusterIDs.length, '?').join(',')})',
      [...clusterIDs],
    );

    for (final r in rows) {
      final id = r[clusterIDColumn] as String;
      final avg = r[avgColumn] as Uint8List;
      final count = r[countColumn] as int;
      result[id] = (avg, count);
    }
    return result;
  }

  @override
  Future<Map<String, String>> getClusterIDToPersonID() async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      'SELECT $personIdColumn, $clusterIDColumn FROM $clusterPersonTable',
    );
    final Map<String, String> result = {};
    for (final map in maps) {
      result[map[clusterIDColumn] as String] = map[personIdColumn] as String;
    }
    return result;
  }

  @override
  Future<void> resetClusterTables({required bool faces}) async {
    final db = await asyncDB;
    if (faces) {
      await db.execute(deleteFacesTable);
      await db.execute(createFacesTable);
      await db.execute(deleteFaceClustersTable);
      await db.execute(createFaceClustersTable);
      await db.execute(fcClusterIDIndex);
    }

    await db.execute(deleteClusterPersonTable);
    await db.execute(deleteNotPersonFeedbackTable);
    await db.execute(deleteClusterSummaryTable);
    await db.execute(deleteClusterCentroidVectorIdMappingTable);
    await db.execute(deleteFaceClustersTable);

    await db.execute(createClusterPersonTable);
    await db.execute(createNotPersonFeedbackTable);
    await db.execute(createClusterSummaryTable);
    await db.execute(createClusterCentroidVectorIdMappingTable);
    await db.execute(createFaceClustersTable);
    await db.execute(fcClusterIDIndex);
  }

  @override
  Future<void> dropFacesFeedbackTables() async {
    try {
      final db = await asyncDB;

      await db.execute(deleteClusterPersonTable);
      await db.execute(deleteNotPersonFeedbackTable);

      await db.execute(createClusterPersonTable);
      await db.execute(createNotPersonFeedbackTable);
    } catch (e) {
      _logger.severe('Error dropping feedback tables', e);
    }
  }

  @override
  Future<List<int>> getFileIDsOfPersonID(String personID) async {
    final db = await asyncDB;
    final result = await db.getAll(
      '''
        SELECT DISTINCT $facesTable.$fileIDColumn
        FROM $clusterPersonTable
        JOIN $faceClustersTable ON $clusterPersonTable.$clusterIDColumn = $faceClustersTable.$clusterIDColumn
        JOIN $facesTable ON $faceClustersTable.$faceIDColumn = $facesTable.$faceIDColumn
        WHERE $clusterPersonTable.$personIdColumn = ?
    ''',
      [personID],
    );

    return [for (final row in result) row[fileIDColumn]];
  }

  @override
  Future<List<int>> getFileIDsOfClusterID(String clusterID) async {
    final db = await asyncDB;
    final result = await db.getAll(
      '''
        SELECT DISTINCT $facesTable.$fileIDColumn
        FROM $faceClustersTable
        JOIN $facesTable ON $faceClustersTable.$faceIDColumn = $facesTable.$faceIDColumn
        WHERE $faceClustersTable.$clusterIDColumn = ?
    ''',
      [clusterID],
    );

    return [for (final row in result) row[fileIDColumn]];
  }

  @override
  Future<Set<int>> getAllFileIDsOfFaceIDsNotInAnyCluster() async {
    final db = await asyncDB;
    final result = await db.getAll('''
        SELECT DISTINCT file_id
        FROM faces
        LEFT JOIN face_clusters ON faces.face_id = face_clusters.face_id
        WHERE face_clusters.face_id IS NULL;
    ''');
    return <int>{for (final row in result) row[fileIDColumn]};
  }

  @override
  Future<Set<int>> getAllFilesAssociatedWithAllClusters({
    List<String>? exceptClusters,
  }) async {
    final notInParam = exceptClusters?.map((e) => "'$e'").join(',') ?? '';
    final db = await asyncDB;
    final result = await db.getAll('''
        SELECT DISTINCT $facesTable.$fileIDColumn
        FROM $facesTable
        JOIN $faceClustersTable on $faceClustersTable.$faceIDColumn = $facesTable.$faceIDColumn
        WHERE $faceClustersTable.$clusterIDColumn NOT IN ($notInParam);
    ''');

    return <int>{for (final row in result) row[fileIDColumn]};
  }

  @override
  Future<List<EmbeddingVector>> getAllClipVectors() async {
    Logger("ClipDB").info("reading all embeddings from DB");
    final db = await asyncDB;
    final results = await db.getAll(
      'SELECT $fileIDColumn, $embeddingColumn FROM $clipTable',
    );

    final List<EmbeddingVector> embeddings = [];
    for (final result in results) {
      final embedding = EmbeddingVector(
        fileID: result[fileIDColumn],
        embedding: Float32List.view(result[embeddingColumn].buffer),
      );
      if (embedding.isEmpty) continue;
      embeddings.add(embedding);
    }
    return embeddings;
  }

  @override
  Future<int> countClusterSummaries() async {
    final db = await asyncDB;
    final countResult = await db.getAll(
      'SELECT COUNT($clusterIDColumn) as total FROM $clusterSummaryTable',
    );
    return countResult.first['total'] as int;
  }

  @override
  Future<List<(String, Uint8List)>> getClusterSummaryPage({
    String? beforeClusterID,
    required int limit,
  }) async {
    final db = await asyncDB;
    late final List<Map<String, dynamic>> results;
    if (beforeClusterID == null) {
      results = await db.getAll('''
              SELECT $clusterIDColumn, $avgColumn
              FROM $clusterSummaryTable
              ORDER BY $clusterIDColumn DESC
              LIMIT $limit
            ''');
    } else {
      results = await db.getAll(
        '''
              SELECT $clusterIDColumn, $avgColumn
              FROM $clusterSummaryTable
              WHERE $clusterIDColumn < ?
              ORDER BY $clusterIDColumn DESC
              LIMIT $limit
            ''',
        [beforeClusterID],
      );
    }
    return [
      for (final result in results)
        (result[clusterIDColumn] as String, result[avgColumn] as Uint8List),
    ];
  }

  @override
  Future<int> countClipRows() async {
    final db = await asyncDB;
    final countResult = await db.getAll(
      'SELECT COUNT($fileIDColumn) as total FROM $clipTable',
    );
    return countResult.first['total'] as int;
  }

  @override
  Future<List<(int, Uint8List)>> getClipRowsPage({
    required int limit,
    required int offset,
  }) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> results = await db.getAll('''
        SELECT $fileIDColumn, $embeddingColumn
        FROM $clipTable
        ORDER BY $fileIDColumn DESC
        LIMIT $limit OFFSET $offset
      ''');
    return [
      for (final result in results)
        (result[fileIDColumn] as int, result[embeddingColumn] as Uint8List),
    ];
  }

  @override
  Future<Map<int, int>> clipIndexedFileWithVersion() async {
    final db = await asyncDB;
    final maps = await db.getAll(
      'SELECT $fileIDColumn , $mlVersionColumn FROM $clipTable',
    );
    final Map<int, int> result = {};
    for (final map in maps) {
      result[map[fileIDColumn] as int] = map[mlVersionColumn] as int;
    }
    return result;
  }

  @override
  Future<int> getClipIndexedFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async {
    final db = await asyncDB;
    final String query =
        'SELECT COUNT(DISTINCT $fileIDColumn) as count FROM $clipTable WHERE $mlVersionColumn >= $minimumMlVersion';
    final List<Map<String, dynamic>> maps = await db.getAll(query);
    return maps.first['count'] as int;
  }

  @override
  Future<int> getClipVectorizableFileCount({
    int minimumMlVersion = clipMlVersion,
  }) async {
    final db = await asyncDB;
    const String query =
        'SELECT COUNT(DISTINCT $fileIDColumn) as count FROM $clipTable '
        'WHERE $mlVersionColumn >= ? AND LENGTH($embeddingColumn) = ?';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      minimumMlVersion,
      ClipVectorDB.embeddingBytesLength,
    ]);
    return maps.first['count'] as int;
  }

  @override
  Future<Map<int, int>> petIndexedFileIds({
    int minimumMlVersion = petMlVersion,
  }) async {
    final db = await asyncDB;
    const String query =
        '''
      SELECT DISTINCT $fileIDColumn, $mlVersionColumn
      FROM $petFacesTable
      WHERE $mlVersionColumn >= ?
    ''';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      minimumMlVersion,
    ]);
    final Map<int, int> result = {};
    for (final map in maps) {
      result[map[fileIDColumn] as int] = map[mlVersionColumn] as int;
    }
    return result;
  }

  @override
  Future<int> getPetIndexedFileCount({
    int minimumMlVersion = petMlVersion,
  }) async {
    final db = await asyncDB;
    const String query =
        'SELECT COUNT(DISTINCT $fileIDColumn) as count FROM $petFacesTable WHERE $mlVersionColumn >= ?';
    final List<Map<String, dynamic>> maps = await db.getAll(query, [
      minimumMlVersion,
    ]);
    return maps.first['count'] as int;
  }

  @override
  Future<Set<int>> getFullyIndexedFileIds({required bool includePets}) async {
    final db = await asyncDB;
    String query =
        'SELECT $fileIDColumn FROM $facesTable WHERE $mlVersionColumn >= $faceMlVersion '
        'INTERSECT '
        'SELECT $fileIDColumn FROM $clipTable WHERE $mlVersionColumn >= $clipMlVersion';
    if (includePets) {
      query +=
          ' INTERSECT '
          'SELECT $fileIDColumn FROM $petFacesTable WHERE $mlVersionColumn >= $petMlVersion';
    }
    final List<Map<String, dynamic>> maps = await db.getAll(query);
    return {for (final map in maps) map[fileIDColumn] as int};
  }

  @override
  Future<(List<(String, int?, int)>, List<(String, int?, int)>)>
  getPetRowsForFiles(List<int> fileIDs) async {
    final db = await asyncDB;
    final placeholders = List.filled(fileIDs.length, '?').join(', ');

    final faceRows = await db.getAll(
      'SELECT $petFaceIDColumn, $faceVectorIdColumn, $speciesColumn '
      'FROM $petFacesTable WHERE $fileIDColumn IN ($placeholders)',
      fileIDs,
    );
    final bodyRows = await db.getAll(
      'SELECT $petBodyIDColumn, $bodyVectorIdColumn, $speciesColumn '
      'FROM $petBodiesTable WHERE $fileIDColumn IN ($placeholders)',
      fileIDs,
    );
    return (
      [
        for (final row in faceRows)
          (
            row[petFaceIDColumn] as String,
            row[faceVectorIdColumn] as int?,
            row[speciesColumn] as int,
          ),
      ],
      [
        for (final row in bodyRows)
          (
            row[petBodyIDColumn] as String,
            row[bodyVectorIdColumn] as int?,
            row[speciesColumn] as int,
          ),
      ],
    );
  }

  @override
  Future<void> deletePetRowsForFiles({
    required List<int> fileIDs,
    required List<String> petFaceIds,
    required List<String> petBodyIds,
  }) async {
    final db = await asyncDB;
    final placeholders = List.filled(fileIDs.length, '?').join(', ');

    await db.writeTransaction((tx) async {
      if (petFaceIds.isNotEmpty) {
        final placeholders = List.filled(petFaceIds.length, '?').join(',');
        await tx.execute(
          'DELETE FROM $petFaceVectorIdMappingTable '
          'WHERE $petFaceIDColumn IN ($placeholders)',
          petFaceIds,
        );
      }
      if (petBodyIds.isNotEmpty) {
        final placeholders = List.filled(petBodyIds.length, '?').join(',');
        await tx.execute(
          'DELETE FROM $petBodyVectorIdMappingTable '
          'WHERE $petBodyIDColumn IN ($placeholders)',
          petBodyIds,
        );
      }
      await tx.execute(
        'DELETE FROM $petFacesTable WHERE $fileIDColumn IN ($placeholders)',
        fileIDs,
      );
      await tx.execute(
        'DELETE FROM $petBodiesTable WHERE $fileIDColumn IN ($placeholders)',
        fileIDs,
      );
    });
  }

  @override
  Future<void> insertClipRows(List<ClipEmbedding> embeddings) async {
    final db = await asyncDB;
    if (embeddings.length == 1) {
      await db.execute(
        'INSERT OR REPLACE INTO $clipTable ($fileIDColumn, $embeddingColumn, $mlVersionColumn) VALUES (?, ?, ?)',
        _getRowFromEmbedding(embeddings.first),
      );
    } else {
      final inputs = embeddings.map((e) => _getRowFromEmbedding(e)).toList();
      await db.executeBatch(
        'INSERT OR REPLACE INTO $clipTable ($fileIDColumn, $embeddingColumn, $mlVersionColumn) values(?, ?, ?)',
        inputs,
      );
    }
  }

  // This is the repeated-query cache, not the per-file CLIP store.
  @override
  Future<void> putRepeatedTextEmbeddingCache(
    String query,
    List<double> embedding,
  ) async {
    final db = await asyncDB;
    await db.execute(
      'INSERT OR REPLACE INTO $textEmbeddingsCacheTable '
      '($textQueryColumn, $embeddingColumn, $mlVersionColumn, $createdAtColumn) '
      'VALUES (?, ?, ?, ?)',
      [
        query,
        Float32List.fromList(embedding).buffer.asUint8List(),
        clipMlVersion,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  // This is the repeated-query cache, not the per-file CLIP store.
  @override
  Future<List<double>?> getRepeatedTextEmbeddingCache(String query) async {
    final db = await asyncDB;
    final results = await db.getAll(
      'SELECT $embeddingColumn, $mlVersionColumn, $createdAtColumn '
      'FROM $textEmbeddingsCacheTable '
      'WHERE $textQueryColumn = ?',
      [query],
    );

    if (results.isEmpty) return null;

    final threeMonthsAgo =
        DateTime.now().millisecondsSinceEpoch - (90 * 24 * 60 * 60 * 1000);

    for (final result in results) {
      if (result[mlVersionColumn] == clipMlVersion &&
          result[createdAtColumn] as int > threeMonthsAgo) {
        return Float32List.view((result[embeddingColumn] as Uint8List).buffer);
      }
    }

    await db.execute(
      'DELETE FROM $textEmbeddingsCacheTable WHERE $textQueryColumn = ?',
      [query],
    );
    return null;
  }

  @override
  Future<void> deleteClipRows(List<int> fileIDs) async {
    final db = await asyncDB;
    await db.execute(
      'DELETE FROM $clipTable WHERE $fileIDColumn IN (${fileIDs.join(", ")})',
    );
  }

  @override
  Future<void> deleteAllClipRows() async {
    final db = await asyncDB;
    await db.execute('DELETE FROM $clipTable');
  }

  List<Object?> _getRowFromEmbedding(ClipEmbedding embedding) {
    return [
      embedding.fileID,
      Float32List.fromList(embedding.embedding).buffer.asUint8List(),
      embedding.version,
    ];
  }

  // Prefer the face_thumbnail_cache helper with the same name.
  @override
  Future<void> putFaceIdCachedForPersonOrCluster(
    String personOrClusterId,
    String faceID,
  ) async {
    final db = await asyncDB;
    await db.execute(
      '''
      INSERT OR REPLACE INTO $faceCacheTable ($personOrClusterIdColumn, $faceIDColumn)
      VALUES (?, ?)
    ''',
      [personOrClusterId, faceID],
    );
  }

  @override
  Future<String?> getFaceIdUsedForPersonOrCluster(
    String personOrClusterId,
  ) async {
    final db = await asyncDB;
    final List<Map<String, dynamic>> maps = await db.getAll(
      '''
      SELECT $faceIDColumn FROM $faceCacheTable
      WHERE $personOrClusterIdColumn = ?
    ''',
      [personOrClusterId],
    );
    if (maps.isNotEmpty) {
      return maps.first[faceIDColumn] as String;
    }
    return null;
  }

  @override
  Future<void> removeFaceIdCachedForPersonOrCluster(
    String personOrClusterID,
  ) async {
    final db = await asyncDB;
    const String sql =
        '''
      DELETE FROM $faceCacheTable
      WHERE $personOrClusterIdColumn = ?
    ''';
    final List<Object?> params = [personOrClusterID];
    await db.execute(sql, params);
  }

  @override
  Future<Set<String>> getClustersForMemoryLane(Set<String> assigned) async {
    const batchSize = 256;
    final db = await asyncDB;
    final clusters = <String>{};
    var offset = 0;
    const String sql =
        '''
        SELECT $clusterIDColumn, COUNT(*) AS count
        FROM $faceClustersTable
        WHERE $clusterIDColumn IS NOT NULL
        GROUP BY $clusterIDColumn
        ORDER BY count DESC, $clusterIDColumn
        LIMIT ? OFFSET ?
        ''';
    while (clusters.length < 20) {
      final batch = await db.getAll(sql, [batchSize, offset]);
      for (final row in batch) {
        final cluster = row[clusterIDColumn] as String;
        if (!assigned.contains(cluster)) {
          clusters.add(cluster);
          if (clusters.length == 20) {
            break;
          }
        }
      }
      if (batch.length < batchSize) {
        break;
      }
      offset += batchSize;
    }
    return clusters;
  }

  @override
  Future<void> putFDStatus(List<FDStatus> fdStatusList) async {
    if (fdStatusList.isEmpty) return;
    final db = await asyncDB;
    final inputs = <List<Object?>>[];
    for (var status in fdStatusList) {
      inputs.add([
        status.fileID,
        status.userID,
        status.type,
        status.size,
        status.objectID,
        status.objectNonce,
        status.updatedAt,
      ]);
    }
    await db.executeBatch(
      'INSERT OR REPLACE INTO $fileDataTable ($fileIDColumn, user_id, type, size, obj_id, obj_nonce, updated_at ) values(?, ?, ?, ?, ?, ?, ?)',
      inputs,
    );
  }

  @override
  Future<Map<int, PreviewInfo>> getFileIDsVidPreview() async {
    final db = await asyncDB;
    final res = await db.execute(
      "SELECT $fileIDColumn, $objectIdColumn, size FROM $fileDataTable WHERE type='vid_preview'",
    );
    return res.asMap().map(
      (i, e) => MapEntry(
        e[fileIDColumn] as int,
        PreviewInfo(
          objectId: e[objectIdColumn] as String,
          objectSize: e['size'] as int,
        ),
      ),
    );
  }

  @override
  Future<Set<int>> getFileIDsWithFDData({DataType? type}) async {
    final db = await asyncDB;
    final String query = type == null
        ? 'SELECT $fileIDColumn FROM $fileDataTable'
        : 'SELECT $fileIDColumn FROM $fileDataTable WHERE type = ?';
    final List<Object?> args = type == null ? const [] : [type.toJson()];
    final res = args.isEmpty
        ? await db.execute(query)
        : await db.execute(query, args);
    return res.map((e) => e[fileIDColumn] as int).toSet();
  }
}

class MLDataDB {
  MLDataDB._();

  static final IMLDataDB<int> instance = DartMLDataDB.instance;
  static final IMLDataDB<int> localGalleryInstance =
      DartMLDataDB.localGalleryInstance;
}
