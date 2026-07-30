import 'dart:async';
import "dart:math";

import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart' show join;
import 'package:path_provider/path_provider.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/db/common/base.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/db_model_mappers.dart";
import "package:photos/db/ml/db_pet_model_mappers.dart";
import "package:photos/db/ml/pet_vector_db.dart";
import 'package:photos/db/ml/schema.dart';
import "package:photos/events/embedding_updated_event.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/compute_controller.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_db_info_for_clustering.dart";
import 'package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart';
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/utils/ml_util.dart";
import 'package:sqlite_async/sqlite_async.dart';
import "package:synchronized/synchronized.dart";

/// Stores all data for the ML related features. The database can be accessed by `MLDataDB.instance.database`.
///
/// This includes:
/// [facesTable] - Stores all the detected faces and its embeddings in the images.
/// [faceClustersTable] - Stores all the mappings from the faces (faceID) to the clusters (clusterID).
/// [clusterPersonTable] - Stores all the clusters that are mapped to a certain person.
/// [clusterSummaryTable] - Stores a summary of each cluster, containg the mean embedding and the number of faces in the cluster.
/// [notPersonFeedback] - Stores the clusters that are confirmed not to belong to a certain person by the user
///
/// [clipTable] - Stores the embeddings of the CLIP model
/// [fileDataTable] - Stores data about the files that are already processed by the ML models
///
/// [faceCacheTable] - Stores a all the mappings from personID or clusterID to the faceID that has been used as cover face.
class MLDataDB with SqlDbBase implements IMLDataDB<int> {
  static final Logger _logger = Logger("MLDataDB");
  static const int _maxSqlBindParamsPerQuery = 10000;

  static Logger get logger => _logger;

  // static const _databaseVersion = 1;

  final String _databaseName;
  final ClipVectorDB _clipVectorDB;
  final ClusterCentroidVectorDB _clusterCentroidVectorDB;
  final bool _isLocalGallery;
  final List<String> _migrationScripts;
  int _clusterSummaryMutationVersion = 0;
  Future<void>? _clipVectorDbRecoveryFuture;
  final Lock _clipVectorRecoveryLock = Lock();
  final Lock _clipVectorMigrationLock = Lock();
  bool _clipVectorDbRecoveryRequested = false;
  Future<void>? _clusterCentroidVectorDbRecoveryFuture;
  final Lock _clusterCentroidVectorRecoveryLock = Lock();
  final Lock _clusterCentroidVectorMigrationLock = Lock();
  bool _clusterCentroidVectorDbRecoveryRequested = false;

  MLDataDB._privateConstructor({
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

  static final MLDataDB instance = MLDataDB._privateConstructor();
  static final MLDataDB localGalleryInstance = MLDataDB._privateConstructor(
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

  // only have a single app-wide reference to the database
  Future<SqliteDatabase>? _sqliteAsyncDBFuture;

  Future<SqliteDatabase> get asyncDB async {
    _sqliteAsyncDBFuture ??= _initSqliteAsyncDatabase();
    return _sqliteAsyncDBFuture!;
  }

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
    final stopwatch = Stopwatch()..start();
    _logger.info("MLDataDB: Starting migration");
    await migrate(asyncDBConnection, _migrationScripts);
    _logger.info("MLDataDB Migration took ${stopwatch.elapsedMilliseconds} ms");
    stopwatch.stop();

    return asyncDBConnection;
  }

  Iterable<List<T>> _chunkList<T>(List<T> values, int chunkSize) sync* {
    for (int i = 0; i < values.length; i += chunkSize) {
      final end = min(i + chunkSize, values.length);
      yield values.sublist(i, end);
    }
  }

  // bulkInsertFaces inserts the faces in the database in batches of 1000.
  // This is done to avoid the error "too many SQL variables" when inserting
  // a large number of faces.
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

  /// Store pet face embeddings into PetVectorDB after SQLite insert.
  Future<void> storePetFaceEmbeddings(
    List<DBPetFace> dbPetFaces,
    List<PetFaceResult> petFaces,
  ) async {
    if (dbPetFaces.length != petFaces.length) {
      throw StateError(
        'dbPetFaces.length (${dbPetFaces.length}) != petFaces.length (${petFaces.length})',
      );
    }
    try {
      final db = await asyncDB;
      // Group by species
      final bySpecies = <int, List<(DBPetFace, PetFaceResult)>>{};
      for (int i = 0; i < dbPetFaces.length; i++) {
        final species = petFaces[i].species;
        bySpecies.putIfAbsent(species, () => []);
        bySpecies[species]!.add((dbPetFaces[i], petFaces[i]));
      }
      for (final entry in bySpecies.entries) {
        final vdb = PetVectorDB.forModel(
          species: entry.key,
          isFace: true,
          localGallery: _isLocalGallery,
        );
        final petFaceIds = entry.value.map((e) => e.$1.petFaceId).toList();
        final idMap = await vdb.getPetFaceVectorIdMap(
          petFaceIds,
          db: db,
          createIfMissing: true,
        );
        final vectorIds = <int>[];
        final embeddings = <Float32List>[];
        final insertedPetFaceIds = <String>[];
        for (final (dbFace, pfResult) in entry.value) {
          final vid = idMap[dbFace.petFaceId];
          if (vid == null) continue;
          final emb = Float32List.fromList(pfResult.embedding);
          if (emb.length != PetVectorDB.faceDimension) {
            _logger.warning(
              "Skipping pet face embedding with wrong dimension ${emb.length}",
            );
            continue;
          }
          vectorIds.add(vid);
          embeddings.add(emb);
          insertedPetFaceIds.add(dbFace.petFaceId);
        }
        if (vectorIds.isNotEmpty) {
          await vdb.bulkInsertEmbeddings(
            vectorIds: vectorIds,
            embeddings: embeddings,
          );
          final updateMap = Map.fromIterables(insertedPetFaceIds, vectorIds);
          await updatePetFaceVectorIds(updateMap);
        }
      }
    } catch (e, s) {
      _logger.severe("Failed to store pet face embeddings in vector DB", e, s);
      rethrow;
    }
  }

  /// Store pet body embeddings into PetVectorDB after SQLite insert.
  Future<void> storePetBodyEmbeddings(
    List<DBPetBody> dbPetBodies,
    List<PetBodyResult> petBodies,
  ) async {
    if (dbPetBodies.length != petBodies.length) {
      throw StateError(
        'dbPetBodies.length (${dbPetBodies.length}) != petBodies.length (${petBodies.length})',
      );
    }
    try {
      final db = await asyncDB;
      // Group by species (0 = dog, 1 = cat)
      final bySpecies = <int, List<(DBPetBody, PetBodyResult)>>{};
      for (int i = 0; i < dbPetBodies.length; i++) {
        final species = dbPetBodies[i].species;
        bySpecies.putIfAbsent(species, () => []);
        bySpecies[species]!.add((dbPetBodies[i], petBodies[i]));
      }
      for (final entry in bySpecies.entries) {
        final vdb = PetVectorDB.forModel(
          species: entry.key,
          isFace: false,
          localGallery: _isLocalGallery,
        );
        final bodyIds = entry.value.map((e) => e.$1.petBodyId).toList();
        final idMap = await vdb.getObjectVectorIdMap(
          bodyIds,
          db: db,
          createIfMissing: true,
        );
        final vectorIds = <int>[];
        final embeddings = <Float32List>[];
        final insertedBodyIds = <String>[];
        for (final (dbBody, bodyResult) in entry.value) {
          final vid = idMap[dbBody.petBodyId];
          if (vid == null) continue;
          final emb = Float32List.fromList(bodyResult.embedding);
          if (emb.length != PetVectorDB.bodyDimension) {
            _logger.warning(
              "Skipping pet body embedding with wrong dimension ${emb.length}",
            );
            continue;
          }
          vectorIds.add(vid);
          embeddings.add(emb);
          insertedBodyIds.add(dbBody.petBodyId);
        }
        if (vectorIds.isNotEmpty) {
          await vdb.bulkInsertEmbeddings(
            vectorIds: vectorIds,
            embeddings: embeddings,
          );
          final updateMap = Map.fromIterables(insertedBodyIds, vectorIds);
          await updatePetBodyVectorIds(updateMap);
        }
      }
    } catch (e, s) {
      _logger.severe("Failed to store pet body embeddings in vector DB", e, s);
      rethrow;
    }
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

  /// Returns a map of fileID to the indexed ML version
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
  Future<Set<String>> getPersonIgnoredClusters(String personID) async {
    final db = await asyncDB;
    // find out clusterIds that are assigned to other persons using the clusters table
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
  Future<void> clearTable() async {
    final db = await asyncDB;

    await db.execute(deleteFacesTable);
    await db.execute(deleteFaceClustersTable);
    await db.execute(deleteClusterPersonTable);
    await db.execute(deleteClusterSummaryTable);
    await db.execute(deleteClusterCentroidVectorIdMappingTable);
    await db.execute(deleteNotPersonFeedbackTable);
    await db.execute(deleteClipEmbeddingsTable);
    await db.execute(deleteFileDataTable);
    await _clipVectorDB.deleteIndexFile();
    await _clusterCentroidVectorDB.deleteIndexFile();
    // Pet tables
    await db.execute(deletePetFacesTable);
    await db.execute(deletePetBodiesTable);
    await db.execute(deletePetFaceVectorIdMappingTable);
    await db.execute(deletePetBodyVectorIdMappingTable);
    final petVdbs = _isLocalGallery
        ? PetVectorDB.allLocalGalleryInstances
        : PetVectorDB.allInstances;
    for (final vdb in petVdbs) {
      await vdb.deleteIndexFile();
    }
    _markClusterSummaryMutated();
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
    // read person from db
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

  // Get Map of personID to Map of clusterID to faceIDs
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
    // const String query2 = '''
    //     SELECT $faceBlur
    //     FROM $facesTable
    //     WHERE $faceIDColumn IN (SELECT $faceIDColumn FROM $faceClustersTable WHERE $clusterIDColumn = ?)
    //   ''';
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
        // Query a batch of rows
        final List<Map<String, dynamic>> maps = await db.getAll(
          'SELECT $faceIDColumn, $embeddingColumn, $faceScore, $faceBlur, $isSideways FROM $facesTable'
          ' WHERE $faceScore > $kMinimumQualityFaceScore AND $faceBlur > $kLaplacianHardThreshold'
          ' ORDER BY $faceIDColumn'
          ' DESC LIMIT $batchSize OFFSET $offset',
        );
        // Break the loop if no more rows
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

    // Define the batch size
    const batchSize = 10000;
    int offset = 0;

    final Map<String, Uint8List> result = {};
    while (true) {
      // Query a batch of rows
      final String query =
          '''
        SELECT $faceIDColumn, $embeddingColumn
        FROM $facesTable
        WHERE $faceIDColumn IN (${faceIDs.map((id) => "'$id'").join(",")})
        ORDER BY $faceIDColumn DESC
        LIMIT $batchSize OFFSET $offset
      ''';
      final List<Map<String, dynamic>> maps = await db.getAll(query);
      // Break the loop if no more rows
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
  Future<void> deleteFaceIndexForFiles(List<int> fileIDs) async {
    final db = await asyncDB;
    final String sql =
        '''
      DELETE FROM $facesTable WHERE $fileIDColumn IN (${fileIDs.join(", ")})
    ''';
    await db.execute(sql);
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

  /// WARNING: Only use this method if the person has just been created.
  /// Otherwise, use [ClusterFeedbackService.instance.addClusterToExistingPerson] instead.
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

  // for a given personID, return a map of clusterID to fileIDs using join query
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

  Future<void> deleteClusterCentroidVectorIdMapping(String clusterID) async {
    final db = await asyncDB;
    const deleteSql =
        '''
      DELETE FROM $clusterCentroidVectorIdMappingTable
      WHERE $clusterIDColumn = ?
    ''';
    await db.execute(deleteSql, [clusterID]);
  }

  Future<void> clearClusterCentroidVectorIdMappings() async {
    final db = await asyncDB;
    await db.execute(deleteClusterCentroidVectorIdMappingTable);
  }

  void _markClusterSummaryMutated() {
    _clusterSummaryMutationVersion++;
  }

  int _clusterSummaryMutationSnapshot() {
    return _clusterSummaryMutationVersion;
  }

  @override
  Future<void> clusterSummaryUpdate(
    Map<String, (Uint8List, int)> summary,
  ) async {
    if (summary.isEmpty) {
      return;
    }
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
    _markClusterSummaryMutated();

    if (!flagService.enableVectorDb ||
        !await _clusterCentroidVectorDB.checkIfMigrationDone()) {
      return;
    }

    try {
      final clusterIDToVectorID = await getClusterCentroidVectorIdMap(
        summary.keys,
        createIfMissing: true,
      );
      final vectorIDs = <int>[];
      final centroids = <Float32List>[];

      for (final entry in summary.entries) {
        final vectorID = clusterIDToVectorID[entry.key];
        if (vectorID == null) {
          continue;
        }
        final centroidBytes = entry.value.$1;
        Float32List centroid;
        try {
          final centroidValues = EVector.fromBuffer(centroidBytes).values;
          centroid = Float32List.fromList(centroidValues);
        } catch (e, s) {
          _logger.warning(
            "Failed to decode centroid embedding for cluster ${entry.key}, skipping vector update",
            e,
            s,
          );
          continue;
        }
        if (centroid.length != ClusterCentroidVectorDB.embeddingDimensions) {
          _logger.warning(
            "Unexpected centroid embedding size ${centroid.length} for cluster ${entry.key}, skipping vector update",
          );
          continue;
        }
        vectorIDs.add(vectorID);
        centroids.add(centroid);
      }

      if (vectorIDs.isNotEmpty) {
        await _clusterCentroidVectorDB.bulkInsertCentroids(
          clusterVectorIDs: vectorIDs,
          centroids: centroids,
        );
      }
    } catch (e, s) {
      await _handleClusterCentroidVectorWriteFailure(
        operation: "clusterSummaryUpdate",
        error: e,
        stackTrace: s,
      );
    }
  }

  @override
  Future<void> deleteClusterSummary(String clusterID) async {
    final db = await asyncDB;
    const String sqlDelete =
        'DELETE FROM $clusterSummaryTable WHERE $clusterIDColumn = ?';
    await db.execute(sqlDelete, [clusterID]);
    _markClusterSummaryMutated();

    if (!flagService.enableVectorDb ||
        !await _clusterCentroidVectorDB.checkIfMigrationDone()) {
      await deleteClusterCentroidVectorIdMapping(clusterID);
      return;
    }

    try {
      final clusterIDToVectorID = await getClusterCentroidVectorIdMap([
        clusterID,
      ], createIfMissing: false);
      final vectorID = clusterIDToVectorID[clusterID];
      if (vectorID != null) {
        await _clusterCentroidVectorDB.deleteCentroids([vectorID]);
      }
      await deleteClusterCentroidVectorIdMapping(clusterID);
    } catch (e, s) {
      await _handleClusterCentroidVectorWriteFailure(
        operation: "deleteClusterSummary",
        error: e,
        stackTrace: s,
      );
    }
  }

  /// Returns a map of clusterID to (avg embedding, count)
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

  /// WARNING: This will delete ALL data in the database! Only use this for debug/testing purposes!
  @override
  Future<void> dropClustersAndPersonTable({bool faces = false}) async {
    try {
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
      _markClusterSummaryMutated();

      if (await _clusterCentroidVectorDB.checkIfMigrationDone()) {
        await _withClusterCentroidVectorWriteRecovery(
          operation: "dropClustersAndPersonTable",
          writeOperation: () async {
            await _clusterCentroidVectorDB.deleteAllCentroids();
          },
        );
      }
    } catch (e, s) {
      _logger.severe('Error dropping clusters and person table', e, s);
    }
  }

  /// WARNING: This will delete ALL data in the tables! Only use this for debug/testing purposes!
  @override
  Future<void> dropFacesFeedbackTables() async {
    try {
      final db = await asyncDB;

      // Drop the tables
      await db.execute(deleteClusterPersonTable);
      await db.execute(deleteNotPersonFeedbackTable);

      // Recreate the tables
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

    // Convert rows to vectors
    final List<EmbeddingVector> embeddings = [];
    for (final result in results) {
      // Convert to EmbeddingVector
      final embedding = EmbeddingVector(
        fileID: result[fileIDColumn],
        embedding: Float32List.view(result[embeddingColumn].buffer),
      );
      if (embedding.isEmpty) continue;
      embeddings.add(embedding);
    }
    return embeddings;
  }

  Future<void> checkMigrateFillClusterCentroidVectorDB({
    bool force = false,
  }) async {
    await _clusterCentroidVectorMigrationLock.synchronized(() async {
      final migrationDone = await _clusterCentroidVectorDB
          .checkIfMigrationDone();
      if (migrationDone && !force) {
        _logger.info(
          "ClusterCentroidVectorDB migration not needed, already done",
        );
        return;
      }
      _logger.info("Starting ClusterCentroidVectorDB migration");

      const maxStableAttempts = 3;
      for (int attempt = 1; attempt <= maxStableAttempts; attempt++) {
        final startMutationVersion = _clusterSummaryMutationSnapshot();
        _logger.info(
          "ClusterCentroidVectorDB migration attempt $attempt/$maxStableAttempts from mutationVersion=$startMutationVersion",
        );

        await _runClusterCentroidMigrationPass();

        final endMutationVersion = _clusterSummaryMutationSnapshot();
        if (endMutationVersion != startMutationVersion) {
          _logger.info(
            "Cluster summaries changed during migration attempt $attempt (mutationVersion=$startMutationVersion->$endMutationVersion), retrying full migration",
          );
          continue;
        }

        await _clusterCentroidVectorDB.setMigrationDone();
        final finalizedMutationVersion = _clusterSummaryMutationSnapshot();
        if (finalizedMutationVersion == endMutationVersion) {
          _logger.info("ClusterCentroidVectorDB migration done");
          return;
        }

        _logger.info(
          "Cluster summaries changed while finalizing migration attempt $attempt (mutationVersion=$endMutationVersion->$finalizedMutationVersion), retrying full migration",
        );
        await _clusterCentroidVectorDB.invalidateMigrationState();
      }

      _logger.severe(
        "ClusterCentroidVectorDB migration did not reach a stable snapshot after $maxStableAttempts attempts. Leaving migration state invalidated for safe fallback.",
      );
      await _clusterCentroidVectorDB.invalidateMigrationState();
    });
  }

  Future<void> _withClusterCentroidVectorWriteRecovery({
    required String operation,
    required Future<void> Function() writeOperation,
  }) async {
    try {
      await writeOperation();
    } catch (e, s) {
      await _handleClusterCentroidVectorWriteFailure(
        operation: operation,
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  Future<void> _handleClusterCentroidVectorWriteFailure({
    required String operation,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    _logger.severe(
      "ClusterCentroidVectorDB write failed during `$operation`. Marking migration stale and scheduling rebuild.",
      error,
      stackTrace,
    );
    try {
      await _clusterCentroidVectorDB.invalidateMigrationState();
    } catch (invalidateError, invalidateStackTrace) {
      _logger.severe(
        "Failed to invalidate ClusterCentroidVectorDB migration state after `$operation` failure",
        invalidateError,
        invalidateStackTrace,
      );
    }
    unawaited(_scheduleClusterCentroidVectorDbRecovery());
  }

  Future<void> _scheduleClusterCentroidVectorDbRecovery() async {
    late Future<void> recoveryFuture;
    await _clusterCentroidVectorRecoveryLock.synchronized(() {
      _clusterCentroidVectorDbRecoveryRequested = true;
      recoveryFuture = _clusterCentroidVectorDbRecoveryFuture ??=
          _runClusterCentroidVectorDbRecoveryLoop();
    });
    await recoveryFuture;
  }

  Future<void> _runClusterCentroidVectorDbRecoveryLoop() async {
    while (true) {
      await _clusterCentroidVectorRecoveryLock.synchronized(() {
        _clusterCentroidVectorDbRecoveryRequested = false;
      });

      await _recoverClusterCentroidVectorDbFromSqlite();

      final shouldContinue = await _clusterCentroidVectorRecoveryLock
          .synchronized(() {
            if (_clusterCentroidVectorDbRecoveryRequested) {
              return true;
            }
            _clusterCentroidVectorDbRecoveryFuture = null;
            return false;
          });
      if (!shouldContinue) {
        return;
      }
    }
  }

  Future<void> _recoverClusterCentroidVectorDbFromSqlite() async {
    const idlePollDelay = Duration(seconds: 5);
    try {
      _logger.info(
        "Queued ClusterCentroidVectorDB rebuild from SQLite after index write failure",
      );
      while (computeController.computeState != ComputeRunState.idle) {
        _logger.info(
          "Waiting for compute to become idle before ClusterCentroidVectorDB rebuild (current state: ${computeController.computeState})",
        );
        await Future.delayed(idlePollDelay);
      }
      _logger.info("Starting ClusterCentroidVectorDB rebuild from SQLite");
      await checkMigrateFillClusterCentroidVectorDB(force: true);
      _logger.info("ClusterCentroidVectorDB rebuild from SQLite completed");
    } catch (e, s) {
      _logger.severe(
        "ClusterCentroidVectorDB rebuild from SQLite failed",
        e,
        s,
      );
    }
  }

  Future<void> _runClusterCentroidMigrationPass() async {
    final db = await asyncDB;
    final countResult = await db.getAll(
      'SELECT COUNT($clusterIDColumn) as total FROM $clusterSummaryTable',
    );
    final totalCount = countResult.first['total'] as int;
    if (totalCount == 0) {
      _logger.info("No cluster summaries to migrate");
      await clearClusterCentroidVectorIdMappings();
      await _clusterCentroidVectorDB.deleteAllCentroids();
      return;
    }
    _logger.info("Total count of cluster summaries: $totalCount");

    final clusterCentroidVectorDB = _clusterCentroidVectorDB;
    await clusterCentroidVectorDB.deleteAllCentroids();
    await clearClusterCentroidVectorIdMappings();
    _logger.info("ClusterCentroidVectorDB cleared before migration");

    const batchSize = 2000;
    int processedCount = 0;
    int weirdCount = 0;
    int whileCount = 0;
    String? lastClusterID;
    const String migrationKey =
        "cluster_centroid_vector_db_migration_in_progress";
    final stopwatch = Stopwatch()..start();
    try {
      computeController.blockCompute(blocker: migrationKey);
      while (true) {
        whileCount++;
        _logger.info("$whileCount st round of centroid migration while loop");
        await Future.delayed(const Duration(milliseconds: 100));

        late final List<Map<String, dynamic>> results;
        if (lastClusterID == null) {
          results = await db.getAll('''
              SELECT $clusterIDColumn, $avgColumn
              FROM $clusterSummaryTable
              ORDER BY $clusterIDColumn DESC
              LIMIT $batchSize
            ''');
        } else {
          results = await db.getAll(
            '''
              SELECT $clusterIDColumn, $avgColumn
              FROM $clusterSummaryTable
              WHERE $clusterIDColumn < ?
              ORDER BY $clusterIDColumn DESC
              LIMIT $batchSize
            ''',
            [lastClusterID],
          );
        }

        if (results.isEmpty) {
          _logger.info("No more centroid rows, breaking out of while loop");
          break;
        }
        lastClusterID = results.last[clusterIDColumn] as String;

        final clusterIDs = <String>[];
        final clusterIDToCentroid = <String, Float32List>{};
        for (final result in results) {
          final clusterID = result[clusterIDColumn] as String;
          final centroidBytes = result[avgColumn] as Uint8List;
          Float32List centroid;
          try {
            final centroidValues = EVector.fromBuffer(centroidBytes).values;
            centroid = Float32List.fromList(centroidValues);
          } catch (e, s) {
            weirdCount++;
            _logger.warning(
              "Failed to decode centroid embedding for clusterID $clusterID, skipping",
              e,
              s,
            );
            continue;
          }
          if (centroid.length == ClusterCentroidVectorDB.embeddingDimensions) {
            clusterIDs.add(clusterID);
            clusterIDToCentroid[clusterID] = centroid;
          } else {
            weirdCount++;
            _logger.warning(
              "Weird centroid embedding length ${centroid.length} for clusterID $clusterID, skipping",
            );
          }
        }

        final clusterIDToVectorID = await getClusterCentroidVectorIdMap(
          clusterIDs,
          createIfMissing: true,
        );
        final vectorIDs = <int>[];
        final centroids = <Float32List>[];
        for (final clusterID in clusterIDs) {
          final vectorID = clusterIDToVectorID[clusterID];
          final centroid = clusterIDToCentroid[clusterID];
          if (vectorID == null || centroid == null) {
            continue;
          }
          vectorIDs.add(vectorID);
          centroids.add(centroid);
        }

        if (vectorIDs.isNotEmpty) {
          await clusterCentroidVectorDB.bulkInsertCentroids(
            clusterVectorIDs: vectorIDs,
            centroids: centroids,
          );
        }

        processedCount += vectorIDs.length;
        _logger.info(
          "migrated $processedCount/$totalCount cluster centroids to ClusterCentroidVectorDB",
        );
      }
      _logger.info(
        "migrated $processedCount cluster centroids to ClusterCentroidVectorDB in ${stopwatch.elapsed.inMilliseconds} ms, with $weirdCount malformed rows skipped",
      );
      try {
        final vectorStats = await _clusterCentroidVectorDB.getIndexStats();
        if (vectorStats.size != processedCount) {
          _logger.warning(
            "ClusterCentroidVectorDB size mismatch: vectorDb=${vectorStats.size}, migratedRows=$processedCount",
          );
        } else {
          _logger.info(
            "ClusterCentroidVectorDB size match: vectorDb=${vectorStats.size}, migratedRows=$processedCount",
          );
        }
      } catch (e, s) {
        _logger.warning(
          "Failed to log ClusterCentroidVectorDB size after migration",
          e,
          s,
        );
      }
    } catch (e, s) {
      _logger.severe(
        "Error migrating ClusterCentroidVectorDB after ${stopwatch.elapsed.inMilliseconds} ms, clearing out DB again",
        e,
        s,
      );
      await clusterCentroidVectorDB.deleteAllCentroids();
      await clearClusterCentroidVectorIdMappings();
      rethrow;
    } finally {
      stopwatch.stop();
      computeController.unblockCompute(blocker: migrationKey);
    }
  }

  Future<void> checkMigrateFillClipVectorDB({bool force = false}) async {
    await _clipVectorMigrationLock.synchronized(() async {
      final migrationDone = await _clipVectorDB.checkIfMigrationDone();
      if (migrationDone && !force) {
        _logger.info("ClipVectorDB migration not needed, already done");
        return;
      }
      _logger.info("Starting ClipVectorDB migration");

      // Get total count first to track progress
      _logger.info("Getting total count of clip embeddings");
      final db = await asyncDB;
      final countResult = await db.getAll(
        'SELECT COUNT($fileIDColumn) as total FROM $clipTable',
      );
      final totalCount = countResult.first['total'] as int;
      if (totalCount == 0) {
        _logger.info("No clip embeddings to migrate");
        await _clipVectorDB.deleteAllEmbeddings();
        await _clipVectorDB.setMigrationDone();
        return;
      }
      _logger.info("Total count of clip embeddings: $totalCount");

      _logger.info(
        "First time referencing ClipVectorDB rust index in migration",
      );
      final clipVectorDB = _clipVectorDB;
      await clipVectorDB.deleteAllEmbeddings();
      _logger.info("ClipVectorDB rust index referenced");
      _logger.info("ClipVectorDB all embeddings cleared");

      _logger.info(
        "Starting migration of $totalCount clip embeddings to vector DB",
      );
      const batchSize = 5000;
      int offset = 0;
      int processedCount = 0;
      int emptyCount = 0;
      int malformedCount = 0;
      int whileCount = 0;
      const String migrationKey = "clip_vector_db_migration_in_progress";
      final stopwatch = Stopwatch()..start();
      try {
        // Make sure no other heavy compute is running
        computeController.blockCompute(blocker: migrationKey);
        while (true) {
          whileCount++;
          _logger.info("$whileCount st round of while loop");
          // Allow some time for any GC to finish
          await Future.delayed(const Duration(milliseconds: 100));

          _logger.info("Reading $batchSize rows from DB");
          final List<Map<String, dynamic>> results = await db.getAll('''
        SELECT $fileIDColumn, $embeddingColumn
        FROM $clipTable
        ORDER BY $fileIDColumn DESC
        LIMIT $batchSize OFFSET $offset
      ''');
          _logger.info("Got ${results.length} results from DB");
          if (results.isEmpty) {
            _logger.info("No more results, breaking out of while loop");
            break;
          }
          _logger.info("Processing ${results.length} results");
          final List<int> fileIDs = [];
          final List<Float32List> embeddings = [];
          for (final result in results) {
            final embedding = Float32List.view(
              (result[embeddingColumn] as Uint8List).buffer,
            );
            if (embedding.length == ClipVectorDB.embeddingDimensions) {
              fileIDs.add(result[fileIDColumn] as int);
              embeddings.add(Float32List.view(result[embeddingColumn].buffer));
            } else if (embedding.isEmpty) {
              emptyCount++;
            } else {
              malformedCount++;
              _logger.warning(
                "Malformed clip embedding length ${embedding.length} for fileID ${result[fileIDColumn]}, skipping ClipVectorDB migration for this row",
              );
            }
          }
          _logger.info(
            "Got ${fileIDs.length} valid clip embeddings, skipped $emptyCount empty and $malformedCount malformed embeddings so far",
          );

          await _clipVectorDB.bulkInsertEmbeddings(
            fileIDs: fileIDs,
            embeddings: embeddings,
          );
          _logger.info("Inserted ${fileIDs.length} embeddings to ClipVectorDB");
          processedCount += fileIDs.length;
          offset += batchSize;
          _logger.info(
            "migrated $processedCount/$totalCount embeddings to ClipVectorDB",
          );
          if (processedCount >= totalCount) {
            _logger.info("All embeddings migrated, breaking out of while loop");
            break;
          }
          // Allow some time for any GC to finish
          _logger.info("Waiting for 100ms out of precaution, for GC to finish");
          await Future.delayed(const Duration(milliseconds: 100));
        }
        _logger.info(
          "migrated all vectorizable clip embeddings from $totalCount SQLite rows to ClipVectorDB in ${stopwatch.elapsed.inMilliseconds} ms; skipped $emptyCount empty and $malformedCount malformed embeddings",
        );
        await _clipVectorDB.setMigrationDone();
        _logger.info("ClipVectorDB migration done");
        try {
          final latestClipCount = await getClipVectorizableFileCount();
          final vectorStats = await _clipVectorDB.getIndexStats();
          if (vectorStats.size != latestClipCount) {
            _logger.warning(
              "ClipVectorDB size mismatch: vectorDb=${vectorStats.size}, clipTableVectorizable=$latestClipCount",
            );
          } else {
            _logger.info(
              "ClipVectorDB size match: vectorDb=${vectorStats.size}, clipTableVectorizable=$latestClipCount",
            );
          }
        } catch (e, s) {
          _logger.warning(
            "Failed to log ClipVectorDB size after migration",
            e,
            s,
          );
        }
      } catch (e, s) {
        _logger.severe(
          "Error migrating ClipVectorDB after ${stopwatch.elapsed.inMilliseconds} ms, clearing out DB again",
          e,
          s,
        );
        await clipVectorDB.deleteAllEmbeddings();
        rethrow;
      } finally {
        stopwatch.stop();
        // Make sure compute can run again
        computeController.unblockCompute(blocker: migrationKey);
      }
    });
  }

  Future<void> _withClipVectorWriteRecovery({
    required String operation,
    required Future<void> Function() writeOperation,
  }) async {
    try {
      await writeOperation();
    } catch (e, s) {
      await _handleClipVectorWriteFailure(
        operation: operation,
        error: e,
        stackTrace: s,
      );
      rethrow;
    }
  }

  Future<void> _handleClipVectorWriteFailure({
    required String operation,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    _logger.severe(
      "ClipVectorDB write failed during `$operation`. Marking migration stale and scheduling rebuild.",
      error,
      stackTrace,
    );
    try {
      await _clipVectorDB.invalidateMigrationState();
    } catch (invalidateError, invalidateStackTrace) {
      _logger.severe(
        "Failed to invalidate ClipVectorDB migration state after `$operation` failure",
        invalidateError,
        invalidateStackTrace,
      );
    }
    unawaited(_scheduleClipVectorDbRecovery());
  }

  bool _isVectorizableClipEmbedding(ClipEmbedding embedding) {
    return embedding.embedding.length == ClipVectorDB.embeddingDimensions;
  }

  List<ClipEmbedding> _vectorizableClipEmbeddings(
    Iterable<ClipEmbedding> embeddings,
  ) {
    final vectorizable = <ClipEmbedding>[];
    final skippedNonEmpty = <(int, int)>[];

    for (final embedding in embeddings) {
      if (_isVectorizableClipEmbedding(embedding)) {
        vectorizable.add(embedding);
        continue;
      }
      if (embedding.embedding.isNotEmpty) {
        skippedNonEmpty.add((embedding.fileID, embedding.embedding.length));
      }
    }

    for (final (fileID, length) in skippedNonEmpty) {
      _logger.warning(
        "Skipping ClipVectorDB write for fileID $fileID because embedding length $length does not match expected ${ClipVectorDB.embeddingDimensions}",
      );
    }

    return vectorizable;
  }

  Future<void> _scheduleClipVectorDbRecovery() async {
    late Future<void> recoveryFuture;
    await _clipVectorRecoveryLock.synchronized(() {
      _clipVectorDbRecoveryRequested = true;
      recoveryFuture = _clipVectorDbRecoveryFuture ??=
          _runClipVectorDbRecoveryLoop();
    });
    await recoveryFuture;
  }

  Future<void> _runClipVectorDbRecoveryLoop() async {
    while (true) {
      await _clipVectorRecoveryLock.synchronized(() {
        _clipVectorDbRecoveryRequested = false;
      });

      await _recoverClipVectorDbFromSqlite();

      final shouldContinue = await _clipVectorRecoveryLock.synchronized(() {
        if (_clipVectorDbRecoveryRequested) {
          return true;
        }
        _clipVectorDbRecoveryFuture = null;
        return false;
      });
      if (!shouldContinue) {
        return;
      }
    }
  }

  Future<void> _recoverClipVectorDbFromSqlite() async {
    const idlePollDelay = Duration(seconds: 5);
    try {
      _logger.info(
        "Queued ClipVectorDB rebuild from SQLite after index write failure",
      );
      while (computeController.computeState != ComputeRunState.idle) {
        _logger.info(
          "Waiting for compute to become idle before ClipVectorDB rebuild (current state: ${computeController.computeState})",
        );
        await Future.delayed(idlePollDelay);
      }
      _logger.info("Starting ClipVectorDB rebuild from SQLite");
      await checkMigrateFillClipVectorDB(force: true);
      _logger.info("ClipVectorDB rebuild from SQLite completed");
    } catch (e, s) {
      _logger.severe("ClipVectorDB rebuild from SQLite failed", e, s);
    }
  }

  // Get indexed FileIDs
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
  Future<void> deletePetDataForFiles(List<int> fileIDs) async {
    if (fileIDs.isEmpty) return;
    final db = await asyncDB;
    final placeholders = List.filled(fileIDs.length, '?').join(', ');

    // Collect vector IDs grouped by species before deleting rows,
    // so we can remove them from the usearch indexes and mapping tables.
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

    // Group face vector IDs by species for targeted vector DB deletion.
    final faceVidsBySpecies = <int, List<int>>{};
    final faceIdsToRemove = <String>[];
    for (final row in faceRows) {
      final vid = row[faceVectorIdColumn] as int?;
      final petFaceId = row[petFaceIDColumn] as String;
      faceIdsToRemove.add(petFaceId);
      if (vid != null) {
        final species = row[speciesColumn] as int;
        faceVidsBySpecies.putIfAbsent(species, () => []);
        faceVidsBySpecies[species]!.add(vid);
      }
    }

    // Group body vector IDs by species.
    final bodyVidsBySpecies = <int, List<int>>{};
    final bodyIdsToRemove = <String>[];
    for (final row in bodyRows) {
      final vid = row[bodyVectorIdColumn] as int?;
      final petBodyId = row[petBodyIDColumn] as String;
      bodyIdsToRemove.add(petBodyId);
      if (vid != null) {
        final species = row[speciesColumn] as int;
        bodyVidsBySpecies.putIfAbsent(species, () => []);
        bodyVidsBySpecies[species]!.add(vid);
      }
    }

    // Delete from usearch vector indexes.
    for (final entry in faceVidsBySpecies.entries) {
      try {
        final vdb = PetVectorDB.forModel(
          species: entry.key,
          isFace: true,
          localGallery: _isLocalGallery,
        );
        await vdb.deleteEmbeddings(entry.value);
      } catch (e, s) {
        _logger.warning("Failed to delete pet face vectors", e, s);
      }
    }
    for (final entry in bodyVidsBySpecies.entries) {
      try {
        final vdb = PetVectorDB.forModel(
          species: entry.key,
          isFace: false,
          localGallery: _isLocalGallery,
        );
        await vdb.deleteEmbeddings(entry.value);
      } catch (e, s) {
        _logger.warning("Failed to delete pet body vectors", e, s);
      }
    }

    // Delete mapping table entries and detection rows atomically.
    await db.writeTransaction((tx) async {
      if (faceIdsToRemove.isNotEmpty) {
        final placeholders = List.filled(faceIdsToRemove.length, '?').join(',');
        await tx.execute(
          'DELETE FROM $petFaceVectorIdMappingTable '
          'WHERE $petFaceIDColumn IN ($placeholders)',
          faceIdsToRemove,
        );
      }
      if (bodyIdsToRemove.isNotEmpty) {
        final placeholders = List.filled(bodyIdsToRemove.length, '?').join(',');
        await tx.execute(
          'DELETE FROM $petBodyVectorIdMappingTable '
          'WHERE $petBodyIDColumn IN ($placeholders)',
          bodyIdsToRemove,
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
  Future<void> putClip(List<ClipEmbedding> embeddings) async {
    if (embeddings.isEmpty) return;
    final db = await asyncDB;
    final vectorizableEmbeddings = _vectorizableClipEmbeddings(embeddings);
    if (embeddings.length == 1) {
      await db.execute(
        'INSERT OR REPLACE INTO $clipTable ($fileIDColumn, $embeddingColumn, $mlVersionColumn) VALUES (?, ?, ?)',
        _getRowFromEmbedding(embeddings.first),
      );
      if (flagService.enableVectorDb &&
          vectorizableEmbeddings.isNotEmpty &&
          await _clipVectorDB.checkIfMigrationDone()) {
        await _withClipVectorWriteRecovery(
          operation: "putClip(single)",
          writeOperation: () async {
            await _clipVectorDB.insertEmbedding(
              fileID: vectorizableEmbeddings.first.fileID,
              embedding: vectorizableEmbeddings.first.embedding,
            );
          },
        );
      }
    } else {
      final inputs = embeddings.map((e) => _getRowFromEmbedding(e)).toList();
      await db.executeBatch(
        'INSERT OR REPLACE INTO $clipTable ($fileIDColumn, $embeddingColumn, $mlVersionColumn) values(?, ?, ?)',
        inputs,
      );
      if (flagService.enableVectorDb &&
          vectorizableEmbeddings.isNotEmpty &&
          await _clipVectorDB.checkIfMigrationDone()) {
        await _withClipVectorWriteRecovery(
          operation: "putClip(bulk)",
          writeOperation: () async {
            await _clipVectorDB.bulkInsertEmbeddings(
              fileIDs: vectorizableEmbeddings.map((e) => e.fileID).toList(),
              embeddings: vectorizableEmbeddings
                  .map((e) => Float32List.fromList(e.embedding))
                  .toList(),
            );
          },
        );
      }
    }
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  /// WARNING: don't confuse this with [putClip]. If you're not sure, use [putClip]
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

  /// WARNING: don't confuse this with [getAllClipVectors]. If you're not sure, use [getAllClipVectors]
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

    // Find first valid entry
    for (final result in results) {
      if (result[mlVersionColumn] == clipMlVersion &&
          result[createdAtColumn] as int > threeMonthsAgo) {
        return Float32List.view((result[embeddingColumn] as Uint8List).buffer);
      }
    }

    // No valid entry found, clean up
    await db.execute(
      'DELETE FROM $textEmbeddingsCacheTable WHERE $textQueryColumn = ?',
      [query],
    );
    return null;
  }

  @override
  Future<void> deleteClipEmbeddings(List<int> fileIDs) async {
    final db = await asyncDB;
    await db.execute(
      'DELETE FROM $clipTable WHERE $fileIDColumn IN (${fileIDs.join(", ")})',
    );
    if (flagService.enableVectorDb &&
        await _clipVectorDB.checkIfMigrationDone()) {
      await _withClipVectorWriteRecovery(
        operation: "deleteClipEmbeddings",
        writeOperation: () async {
          await _clipVectorDB.deleteEmbeddings(fileIDs);
        },
      );
    }
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  @override
  Future<void> deleteClipIndexes() async {
    final db = await asyncDB;
    await db.execute('DELETE FROM $clipTable');
    if (flagService.enableVectorDb &&
        await _clipVectorDB.checkIfMigrationDone()) {
      await _withClipVectorWriteRecovery(
        operation: "deleteClipIndexes",
        writeOperation: () async {
          await _clipVectorDB.deleteAllEmbeddings();
        },
      );
    }
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  List<Object?> _getRowFromEmbedding(ClipEmbedding embedding) {
    return [
      embedding.fileID,
      Float32List.fromList(embedding.embedding).buffer.asUint8List(),
      embedding.version,
    ];
  }

  /// WARNING: Better to use the similarly named [putFaceIdCachedForPersonOrCluster]
  /// method from face_thumbnail_cache instead!
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
}
