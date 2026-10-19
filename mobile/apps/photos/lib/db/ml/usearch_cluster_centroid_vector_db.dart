import "dart:io" show File;
import "dart:typed_data" show Float32List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Uint64List;
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/dart_db.dart";
import "package:photos/src/rust/api/usearch_api.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class UsearchClusterCentroidVectorDB implements ClusterCentroidVectorDB {
  static final Logger _logger = Logger("UsearchClusterCentroidVectorDB");

  final String _databaseName;
  final String _migrationKey;
  final bool _localGallery;

  static final BigInt _embeddingDimension = BigInt.from(
    ClusterCentroidVectorDB.embeddingDimensions,
  );

  static Logger get logger => _logger;

  UsearchClusterCentroidVectorDB._privateConstructor(
    this._databaseName,
    this._migrationKey, {
    required bool localGallery,
  }) : _localGallery = localGallery;

  static final instance = UsearchClusterCentroidVectorDB._privateConstructor(
    "ente.ml.vectordb.cluster_centroid.usearch",
    "cluster_centroid_vectordb_migration",
    localGallery: false,
  );
  static final localGalleryInstance =
      UsearchClusterCentroidVectorDB._privateConstructor(
        "ente.ml.offline.vectordb.cluster_centroid.usearch",
        "cluster_centroid_vectordb_migration_offline",
        localGallery: true,
      );

  factory UsearchClusterCentroidVectorDB() => instance;

  DartMLDataDB get _mlDataDB =>
      _localGallery ? DartMLDataDB.localGalleryInstance : DartMLDataDB.instance;

  Future<VectorDb>? _vectorDbFuture;
  Future<void>? _warmupFuture;
  final Lock _writeLock = Lock();

  Future<VectorDb> get _vectorDB async {
    _vectorDbFuture ??= _initVectorDB();
    return _vectorDbFuture!;
  }

  bool? _migrationDone;

  Future<VectorDb> _initVectorDB() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String dbPath = join(documentsDirectory.path, _databaseName);
    _logger.info("Opening cluster centroid vector DB access: DB path $dbPath");
    final indexFile = File(dbPath);
    if (!await indexFile.exists() && await isReady()) {
      _logger.severe(
        "Cluster centroid vector DB file is missing while migration is marked done. Invalidating migration state.",
      );
      await invalidateMigrationState();
    }

    late VectorDb vectorDB;
    try {
      vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
    } catch (e, s) {
      _logger.severe(
        "Could not open cluster centroid vector DB at path $dbPath",
        e,
        s,
      );
      _logger.severe("Deleting the index file and trying again");
      await deleteIndexFile();
      try {
        vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
      } catch (e, s) {
        _logger.severe(
          "Still can't open cluster centroid vector DB at path $dbPath",
          e,
          s,
        );
        rethrow;
      }
    }

    final stats = await getIndexStats(vectorDB);
    _logger.info(
      "Cluster centroid vector DB connection opened with stats: ${stats.toString()}",
    );

    return vectorDB;
  }

  @override
  Future<bool> isReady() async {
    if (_migrationDone != null) return _migrationDone!;
    _logger.info("Checking if cluster centroid vector DB migration has run");
    final prefs = await SharedPreferences.getInstance();
    final migrationDone = prefs.getBool(_migrationKey) ?? false;
    if (migrationDone) {
      _logger.info("Cluster centroid vector DB migration already done");
      _migrationDone = true;
      return _migrationDone!;
    } else {
      _logger.info("Cluster centroid vector DB migration not done");
      _migrationDone = false;
      return _migrationDone!;
    }
  }

  Future<void> setMigrationDone() async {
    _logger.info("Setting cluster centroid vector DB migration done");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationKey, true);
    _migrationDone = true;
  }

  Future<void> invalidateMigrationState() async {
    _logger.info("Invalidating cluster centroid vector DB migration state");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationKey, false);
    _migrationDone = false;
  }

  Future<void> _runWriteOperation(
    Future<void> Function(VectorDb db) operation,
  ) async {
    final db = await _vectorDB;
    await _writeLock.synchronized(() async {
      await operation(db);
    });
  }

  Future<void> insertCentroid({
    required int clusterVectorID,
    required List<double> centroid,
  }) async {
    try {
      await _runWriteOperation((db) async {
        await db.addVector(key: BigInt.from(clusterVectorID), vector: centroid);
      });
    } catch (e, s) {
      _logger.severe("Error inserting cluster centroid", e, s);
      rethrow;
    }
  }

  Future<void> bulkInsertCentroids({
    required List<int> clusterVectorIDs,
    required List<Float32List> centroids,
  }) async {
    if (clusterVectorIDs.isEmpty || centroids.isEmpty) {
      return;
    }
    try {
      await _runWriteOperation((db) async {
        await db.bulkAddVectors(
          keys: Uint64List.fromList(clusterVectorIDs),
          vectors: centroids,
        );
      });
    } catch (e, s) {
      _logger.severe("Error bulk inserting cluster centroids", e, s);
      rethrow;
    }
  }

  Future<void> deleteCentroids(List<int> clusterVectorIDs) async {
    if (clusterVectorIDs.isEmpty) {
      return;
    }
    try {
      BigInt deletedCount = BigInt.zero;
      await _runWriteOperation((db) async {
        deletedCount = await db.bulkRemoveVectors(
          keys: Uint64List.fromList(clusterVectorIDs),
        );
      });
      _logger.info(
        "Deleted $deletedCount centroids from ${clusterVectorIDs.length} keys",
      );
    } catch (e, s) {
      _logger.severe("Error bulk deleting specific centroids", e, s);
      rethrow;
    }
  }

  Future<void> deleteAllCentroids() async {
    await invalidateMigrationState();
    try {
      await _runWriteOperation((db) async {
        await db.resetIndex();
      });
    } catch (e, s) {
      _logger.severe("Error deleting all cluster centroids", e, s);
      rethrow;
    }
  }

  Future<ClusterCentroidVectorDbStats> getIndexStats([VectorDb? db]) async {
    db ??= await _vectorDB;
    try {
      final stats = await db.getIndexStats();
      return ClusterCentroidVectorDbStats(
        size: stats.$1.toInt(),
        capacity: stats.$2.toInt(),
        dimensions: stats.$3.toInt(),
        fileSize: stats.$4.toInt(),
        memoryUsage: stats.$5.toInt(),
        expansionAdd: stats.$6.toInt(),
        expansionSearch: stats.$7.toInt(),
      );
    } catch (e, s) {
      _logger.severe("Error getting cluster centroid index stats", e, s);
      rethrow;
    }
  }

  Future<Map<String, int>> _clusterIDToVectorID(Iterable<String> clusterIDs) =>
      _mlDataDB.getClusterCentroidVectorIdMap(
        clusterIDs,
        createIfMissing: false,
      );

  static Map<int, String> _invert(
    Map<String, int> clusterIDToVectorID, {
    required Set<String> within,
  }) => {
    for (final entry in clusterIDToVectorID.entries)
      if (within.contains(entry.key)) entry.value: entry.key,
  };

  static List<List<(String, double)>> _noMatchesPerQuery(int queryCount) =>
      List.generate(queryCount, (_) => const <(String, double)>[]);

  static List<(String, double)> _toClusterMatches(
    List<(int, double)> matches,
    Map<int, String> vectorIDToClusterID,
  ) {
    final output = <(String, double)>[];
    for (final (vectorID, distance) in matches) {
      final clusterID = vectorIDToClusterID[vectorID];
      if (clusterID == null) {
        continue;
      }
      output.add((clusterID, distance));
    }
    return output;
  }

  @override
  Future<List<List<(String, double)>>> bulkSearchNearestAllowed(
    List<List<double>> queries,
    Set<String> allowedClusterIDs, {
    required double maxDistance,
    int count = 10,
  }) async {
    if (!await isReady()) {
      throw StateError(
        "Cluster centroid vector DB migration is not done, cannot run approximate search",
      );
    }
    if (count <= 0 || queries.isEmpty || allowedClusterIDs.isEmpty) {
      return _noMatchesPerQuery(queries.length);
    }
    final vectorIDToClusterID = _invert(
      await _clusterIDToVectorID(allowedClusterIDs),
      within: allowedClusterIDs,
    );
    if (vectorIDToClusterID.isEmpty) {
      return _noMatchesPerQuery(queries.length);
    }
    final matchesPerQuery = await _bulkSearchNearestAllowedVectorIDs(
      queries,
      vectorIDToClusterID.keys.toSet(),
      maxDistance: maxDistance,
      count: count,
    );
    return [
      for (var i = 0; i < queries.length; i++)
        i < matchesPerQuery.length
            ? _toClusterMatches(matchesPerQuery[i], vectorIDToClusterID)
            : const <(String, double)>[],
    ];
  }

  @override
  Future<Map<String, ClusterCentroidMatches>> bulkSearchNearestForClusters(
    Set<String> queryClusterIDs, {
    required Set<String> candidateClusterIDs,
    required int count,
    double? maxDistance,
  }) async {
    if (!await isReady()) {
      throw StateError(
        "Cluster centroid vector DB migration is not done, cannot run approximate search",
      );
    }
    if (count <= 0 || queryClusterIDs.isEmpty) {
      return const {};
    }
    final clusterIDToVectorID = await _clusterIDToVectorID(
      queryClusterIDs.union(candidateClusterIDs),
    );
    final queryVectorIDToClusterID = _invert(
      clusterIDToVectorID,
      within: queryClusterIDs,
    );
    if (queryVectorIDToClusterID.isEmpty) {
      return const {};
    }
    final candidateVectorIDToClusterID = _invert(
      clusterIDToVectorID,
      within: candidateClusterIDs,
    );
    final matchesByQueryVectorID = await _bulkSearchNearestForVectorIDs(
      queryVectorIDToClusterID.keys.toSet(),
      count: count,
      maxDistance: maxDistance,
    );
    final output = <String, ClusterCentroidMatches>{};
    for (final entry in matchesByQueryVectorID.entries) {
      final queryClusterID = queryVectorIDToClusterID[entry.key];
      if (queryClusterID == null) {
        continue;
      }
      final rawMatches = entry.value;
      output[queryClusterID] = (
        matches: _toClusterMatches(rawMatches, candidateVectorIDToClusterID),
        reachedCount: rawMatches.length >= count,
      );
    }
    return output;
  }

  Future<List<List<(int, double)>>> _bulkSearchNearestAllowedVectorIDs(
    List<List<double>> queries,
    Set<int> allowedClusterVectorIDs, {
    required double maxDistance,
    required int count,
  }) async {
    final db = await _vectorDB;
    try {
      final rustQueries = <Float32List>[];
      for (final query in queries) {
        if (query is Float32List) {
          rustQueries.add(query);
        } else {
          rustQueries.add(Float32List.fromList(query));
        }
      }
      final allowedKeys = Uint64List.fromList(
        allowedClusterVectorIDs.toList(growable: false),
      );
      final result = await db.bulkApproxFilteredSearchVectorsWithinDistance(
        queries: rustQueries,
        allowedKeys: allowedKeys,
        count: BigInt.from(count),
        maxDistance: maxDistance,
      );

      final keysPerQuery = result.$1;
      final distancesPerQuery = result.$2;
      final alignedQueryLength = keysPerQuery.length < distancesPerQuery.length
          ? keysPerQuery.length
          : distancesPerQuery.length;
      final output = <List<(int, double)>>[];
      for (var i = 0; i < alignedQueryLength; i++) {
        final keys = keysPerQuery[i];
        final distances = distancesPerQuery[i];
        final alignedLength = keys.length < distances.length
            ? keys.length
            : distances.length;
        final matches = <(int, double)>[];
        for (var j = 0; j < alignedLength; j++) {
          matches.add((keys[j].toInt(), distances[j]));
        }
        output.add(matches);
      }
      return output;
    } catch (e, s) {
      _logger.severe("Error bulk searching filtered centroids", e, s);
      rethrow;
    }
  }

  Future<Map<int, List<(int, double)>>> _bulkSearchNearestForVectorIDs(
    Set<int> queryClusterVectorIDs, {
    required int count,
    double? maxDistance,
  }) async {
    final db = await _vectorDB;
    try {
      final queryKeys = queryClusterVectorIDs.toList(growable: false);
      final result = await db.bulkSearchKeys(
        potentialKeys: Uint64List.fromList(queryKeys),
        count: BigInt.from(count),
        exact: false,
      );
      final containedKeys = result.$1;
      final matchedKeys = result.$2;
      final matchedDistances = result.$3;

      final output = <int, List<(int, double)>>{};
      for (var i = 0; i < containedKeys.length; i++) {
        final queryKey = containedKeys[i].toInt();
        final keysForQuery = matchedKeys[i];
        final distancesForQuery = matchedDistances[i];
        final alignedLength = keysForQuery.length < distancesForQuery.length
            ? keysForQuery.length
            : distancesForQuery.length;
        final matches = <(int, double)>[];
        for (var j = 0; j < alignedLength; j++) {
          final distance = distancesForQuery[j];
          if (maxDistance != null && distance > maxDistance) {
            break;
          }
          matches.add((keysForQuery[j].toInt(), distance));
        }
        output[queryKey] = matches;
      }
      return output;
    } catch (e, s) {
      _logger.severe("Error bulk searching centroids", e, s);
      rethrow;
    }
  }

  @override
  Future<void> warmup() async {
    _warmupFuture ??= _warmupInternal();
    await _warmupFuture;
  }

  Future<void> _warmupInternal() async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await _vectorDB;
      final stats = await getIndexStats(db);
      if (stats.size == 0) {
        _logger.info(
          "Skipping cluster centroid vector DB warmup: index is empty",
        );
        return;
      }

      final warmupQuery = List<double>.filled(
        stats.dimensions,
        0.0,
        growable: false,
      );
      await db.searchVectors(
        query: warmupQuery,
        count: BigInt.one,
        exact: false,
      );
      _logger.info(
        "Cluster centroid vector DB warmup finished in ${stopwatch.elapsedMilliseconds} ms",
      );
    } catch (e, s) {
      _logger.warning("Cluster centroid vector DB warmup failed", e, s);
      _warmupFuture = null;
    } finally {
      stopwatch.stop();
    }
  }

  Future<void> deleteIndex() async {
    await invalidateMigrationState();
    final db = await _vectorDB;
    try {
      await _writeLock.synchronized(() async {
        await db.deleteIndex();
        _vectorDbFuture = null;
        _warmupFuture = null;
      });
    } catch (e, s) {
      _logger.severe("Error deleting cluster centroid index", e, s);
      rethrow;
    }
  }

  Future<void> deleteIndexFile() async {
    await _writeLock.synchronized(() async {
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final String dbPath = join(documentsDirectory.path, _databaseName);
        _logger.info("Delete cluster centroid index file: DB path $dbPath");
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
        _logger.info("Deleted cluster centroid index file on disk");
        _vectorDbFuture = null;
        _warmupFuture = null;
        await invalidateMigrationState();
      } catch (e, s) {
        _logger.severe(
          "Error deleting cluster centroid index file on disk",
          e,
          s,
        );
        rethrow;
      }
    });
  }
}

class ClusterCentroidVectorDbStats {
  final int size;
  final int capacity;
  final int dimensions;

  final int fileSize;
  final int memoryUsage;

  final int expansionAdd;
  final int expansionSearch;

  ClusterCentroidVectorDbStats({
    required this.size,
    required this.capacity,
    required this.dimensions,
    required this.fileSize,
    required this.memoryUsage,
    required this.expansionAdd,
    required this.expansionSearch,
  });

  @override
  String toString() {
    return "ClusterCentroidVectorDbStats(size: $size, capacity: $capacity, dimensions: $dimensions, file size on disk (bytes): $fileSize, memory usage (bytes): $memoryUsage, expansionAdd: $expansionAdd, expansionSearch: $expansionSearch)";
  }
}
