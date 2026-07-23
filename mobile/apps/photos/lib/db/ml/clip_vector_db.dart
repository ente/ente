import "dart:io" show File;
import "dart:typed_data" show Float32List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Uint64List;
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/machine_learning/semantic_search/query_result.dart";
import "package:photos/src/rust/api/usearch_api.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:synchronized/synchronized.dart";

class ClipVectorDB {
  static final Logger _logger = Logger("ClipVectorDB");
  static const int embeddingDimensions = 512;
  static const int embeddingBytesLength = embeddingDimensions * 4;

  final String _databaseName;
  final String _migrationKey;

  static final BigInt _embeddingDimension = BigInt.from(embeddingDimensions);

  static Logger get logger => _logger;

  // Singleton pattern
  ClipVectorDB._privateConstructor(this._databaseName, this._migrationKey);
  static final instance = ClipVectorDB._privateConstructor(
    "ente.ml.vectordb.clip.usearch",
    "clip_vectordb_migration",
  );
  static final localGalleryInstance = ClipVectorDB._privateConstructor(
    "ente.ml.offline.vectordb.clip.usearch",
    "clip_vectordb_migration_offline",
  );
  factory ClipVectorDB() => instance;

  // only have a single app-wide reference to the database
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
    _logger.info("Opening vectorDB access: DB path " + dbPath);
    final indexFile = File(dbPath);
    if (!await indexFile.exists() && await checkIfMigrationDone()) {
      _logger.severe(
        "VectorDB file is missing while migration is marked done. Invalidating migration state.",
      );
      await invalidateMigrationState();
    }
    late VectorDb vectorDB;
    try {
      vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
    } catch (e, s) {
      _logger.severe("Could not open VectorDB at path $dbPath", e, s);
      _logger.severe("Deleting the index file and trying again");
      await deleteIndexFile();
      try {
        vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
      } catch (e, s) {
        _logger.severe("Still can't open VectorDB at path $dbPath", e, s);
        rethrow;
      }
    }
    final stats = await getIndexStats(vectorDB);
    _logger.info("VectorDB connection opened with stats: ${stats.toString()}");

    return vectorDB;
  }

  Future<bool> checkIfMigrationDone() async {
    if (_migrationDone != null) return _migrationDone!;
    _logger.info("Checking if ClipVectorDB migration has run");
    final prefs = await SharedPreferences.getInstance();
    final migrationDone = prefs.getBool(_migrationKey) ?? false;
    if (migrationDone) {
      _logger.info("ClipVectorDB migration already done");
      _migrationDone = true;
      return _migrationDone!;
    } else {
      _logger.info("ClipVectorDB migration not done");
      _migrationDone = false;
      return _migrationDone!;
    }
  }

  Future<void> setMigrationDone() async {
    _logger.info("Setting ClipVectorDB migration done");
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationKey, true);
    _migrationDone = true;
  }

  Future<void> invalidateMigrationState() async {
    _logger.info("Invalidating ClipVectorDB migration state");
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

  Future<void> insertEmbedding({
    required int fileID,
    required List<double> embedding,
  }) async {
    try {
      await _runWriteOperation((db) async {
        await db.addVector(key: BigInt.from(fileID), vector: embedding);
      });
    } catch (e, s) {
      _logger.severe("Error inserting embedding", e, s);
      rethrow;
    }
  }

  Future<void> bulkInsertEmbeddings({
    required List<int> fileIDs,
    required List<Float32List> embeddings,
  }) async {
    if (fileIDs.isEmpty || embeddings.isEmpty) {
      return;
    }
    final bigKeys = Uint64List.fromList(fileIDs);
    try {
      await _runWriteOperation((db) async {
        await db.bulkAddVectors(keys: bigKeys, vectors: embeddings);
      });
    } catch (e, s) {
      _logger.severe("Error bulk inserting embeddings", e, s);
      rethrow;
    }
  }

  Future<List<EmbeddingVector>> getEmbeddings(List<int> fileIDs) async {
    final db = await _vectorDB;
    try {
      final keys = Uint64List.fromList(fileIDs);
      final vectors = await db.bulkGetVectors(keys: keys);
      return List.generate(
        vectors.length,
        (index) =>
            EmbeddingVector(fileID: fileIDs[index], embedding: vectors[index]),
      );
    } catch (e, s) {
      _logger.severe("Error getting embeddings", e, s);
      rethrow;
    }
  }

  Future<void> deleteEmbeddings(List<int> fileIDs) async {
    if (fileIDs.isEmpty) {
      return;
    }
    try {
      BigInt deletedCount = BigInt.zero;
      await _runWriteOperation((db) async {
        deletedCount = await db.bulkRemoveVectors(
          keys: Uint64List.fromList(fileIDs),
        );
      });
      _logger.info(
        "Deleted $deletedCount embeddings, from ${fileIDs.length} keys",
      );
    } catch (e, s) {
      _logger.severe("Error bulk deleting specific embeddings", e, s);
      rethrow;
    }
  }

  Future<void> deleteAllEmbeddings() async {
    await invalidateMigrationState();
    try {
      await _runWriteOperation((db) async {
        await db.resetIndex();
      });
    } catch (e, s) {
      _logger.severe("Error deleting all embeddings", e, s);
      rethrow;
    }
  }

  Future<VectorDbStats> getIndexStats([VectorDb? db]) async {
    db ??= await _vectorDB;
    try {
      final stats = await db.getIndexStats();
      return VectorDbStats(
        size: stats.$1.toInt(),
        capacity: stats.$2.toInt(),
        dimensions: stats.$3.toInt(),
        fileSize: stats.$4.toInt(),
        memoryUsage: stats.$5.toInt(),
        expansionAdd: stats.$6.toInt(),
        expansionSearch: stats.$7.toInt(),
      );
    } catch (e, s) {
      _logger.severe("Error getting index stats", e, s);
      rethrow;
    }
  }

  Future<(Uint64List, Float32List)> searchClosestVectors(
    List<double> query,
    int count, {
    bool exact = false,
  }) async {
    final db = await _vectorDB;
    try {
      final result = await db.searchVectors(
        query: query,
        count: BigInt.from(count),
        exact: exact,
      );
      return result;
    } catch (e, s) {
      _logger.severe("Error searching closest vectors", e, s);
      rethrow;
    }
  }

  Future<(BigInt, double)> searchClosestVector(
    List<double> query, {
    bool exact = false,
  }) async {
    final db = await _vectorDB;
    try {
      final result = await db.searchVectors(
        query: query,
        count: BigInt.one,
        exact: exact,
      );
      return (result.$1[0], result.$2[0]);
    } catch (e, s) {
      _logger.severe("Error searching closest vector", e, s);
      rethrow;
    }
  }

  Future<void> warmupApproxSearch() async {
    _warmupFuture ??= _warmupApproxSearchInternal();
    await _warmupFuture;
  }

  Future<void> _warmupApproxSearchInternal() async {
    final stopwatch = Stopwatch()..start();
    try {
      final db = await _vectorDB;
      final stats = await getIndexStats(db);
      if (stats.size == 0) {
        _logger.info("Skipping VectorDB warmup: index is empty");
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
        "VectorDB warmup finished in ${stopwatch.elapsedMilliseconds} ms",
      );
    } catch (e, s) {
      _logger.warning("VectorDB warmup failed", e, s);
      _warmupFuture = null;
    } finally {
      stopwatch.stop();
    }
  }

  Future<List<QueryResult>> searchApproxSimilaritiesWithinThreshold(
    List<double> query,
    double minimumSimilarity,
  ) async {
    final db = await _vectorDB;
    if (!await checkIfMigrationDone()) {
      throw StateError(
        "ClipVectorDB migration is not done, cannot run approximate search",
      );
    }
    try {
      final result = await db.approxSearchVectorsWithinSimilarity(
        query: query,
        minimumSimilarity: minimumSimilarity,
      );
      final keys = result.$1;
      final distances = result.$2;
      final queryResults = <QueryResult>[];
      for (var i = 0; i < keys.length; i++) {
        queryResults.add(QueryResult(keys[i].toInt(), 1.0 - distances[i]));
      }
      return queryResults;
    } catch (e, s) {
      _logger.severe("Error searching approximate similarities", e, s);
      rethrow;
    }
  }

  Future<(List<Uint64List>, List<Float32List>)> bulkSearchVectors(
    List<Float32List> queries,
    BigInt count, {
    bool exact = false,
  }) async {
    final db = await _vectorDB;
    try {
      final result = await db.bulkSearchVectors(
        queries: queries,
        count: count,
        exact: exact,
      );
      return result;
    } catch (e, s) {
      _logger.severe("Error bulk searching vectors", e, s);
      rethrow;
    }
  }

  Future<(Uint64List, List<Uint64List>, List<Float32List>)> bulkSearchWithKeys(
    Uint64List potentialKeys,
    BigInt count, {
    bool exact = false,
  }) async {
    final db = await _vectorDB;
    try {
      final result = await db.bulkSearchKeys(
        potentialKeys: potentialKeys,
        count: count,
        exact: exact,
      );
      return result;
    } catch (e, s) {
      _logger.severe("Error bulk searching vectors with potential keys", e, s);
      rethrow;
    }
  }

  Future<Map<String, List<QueryResult>>> computeBulkSimilarities(
    Map<String, List<double>> textQueryToEmbeddingMap,
    Map<String, double> minimumSimilarityMap, {
    int? maxResults,
  }) async {
    try {
      int? resolvedMaxResults = maxResults;
      if (resolvedMaxResults == null || resolvedMaxResults <= 0) {
        final stats = await getIndexStats();
        resolvedMaxResults = stats.size;
      }
      if (resolvedMaxResults == 0) {
        return {
          for (final query in textQueryToEmbeddingMap.keys)
            query: <QueryResult>[],
        };
      }
      final queryToResults = <String, List<QueryResult>>{};
      for (final MapEntry<String, List<double>> entry
          in textQueryToEmbeddingMap.entries) {
        final query = entry.key;
        final minimumSimilarity = minimumSimilarityMap[query]!;
        final textEmbedding = entry.value;
        final (potentialFileIDs, distances) = await searchClosestVectors(
          textEmbedding,
          resolvedMaxResults,
        );
        final queryResults = <QueryResult>[];
        for (var i = 0; i < potentialFileIDs.length; i++) {
          final similarity = 1 - distances[i];
          if (similarity >= minimumSimilarity) {
            queryResults.add(
              QueryResult(potentialFileIDs[i].toInt(), similarity),
            );
          } else {
            break;
          }
        }
        queryToResults[query] = queryResults;
      }
      return queryToResults;
    } catch (e, s) {
      _logger.severe(
        "Could not bulk find embeddings similarities using vector DB",
        e,
        s,
      );
      rethrow;
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
      _logger.severe("Error deleting index", e, s);
      rethrow;
    }
  }

  Future<void> deleteIndexFile() async {
    await _writeLock.synchronized(() async {
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final String dbPath = join(documentsDirectory.path, _databaseName);
        _logger.info("Delete index file: DB path " + dbPath);
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
        _logger.info("Deleted index file on disk");
        _vectorDbFuture = null;
        _warmupFuture = null;
        await invalidateMigrationState();
      } catch (e, s) {
        _logger.severe("Error deleting index file on disk", e, s);
        rethrow;
      }
    });
  }
}

class VectorDbStats {
  final int size;
  final int capacity;
  final int dimensions;

  // in bytes
  final int fileSize;
  final int memoryUsage;

  final int expansionAdd;
  final int expansionSearch;

  VectorDbStats({
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
    return "VectorDbStats(size: $size, capacity: $capacity, dimensions: $dimensions, file size on disk (bytes): $fileSize, memory usage (bytes): $memoryUsage, expansionAdd: $expansionAdd, expansionSearch: $expansionSearch)";
  }
}
