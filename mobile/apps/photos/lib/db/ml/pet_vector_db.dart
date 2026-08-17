import "dart:io" show File;
import "dart:math" show min;
import "dart:typed_data" show Float32List;

import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Uint64List;
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/db/ml/clip_vector_db.dart" show VectorDbStats;
import "package:photos/db/ml/schema.dart";
import "package:photos/src/rust/api/usearch_api.dart";
import "package:sqlite_async/sqlite_async.dart";
import "package:synchronized/synchronized.dart";

// Each model needs its own vector space; their embeddings are not comparable.
class PetVectorDB {
  static final Logger _logger = Logger("PetVectorDB");

  static const int faceDimension = 128;
  static const int bodyDimension = 192;

  final String _databaseName;
  final BigInt _embeddingDimension;

  static Logger get logger => _logger;

  PetVectorDB._named(this._databaseName, this._embeddingDimension);

  static final dogFace = PetVectorDB._named(
    "ente.ml.vectordb.pet.dog_face.usearch",
    BigInt.from(faceDimension),
  );

  static final catFace = PetVectorDB._named(
    "ente.ml.vectordb.pet.cat_face.usearch",
    BigInt.from(faceDimension),
  );

  static final dogBody = PetVectorDB._named(
    "ente.ml.vectordb.pet.dog_body.usearch",
    BigInt.from(bodyDimension),
  );

  static final catBody = PetVectorDB._named(
    "ente.ml.vectordb.pet.cat_body.usearch",
    BigInt.from(bodyDimension),
  );

  static final localGalleryDogFace = PetVectorDB._named(
    "ente.ml.offline.vectordb.pet.dog_face.usearch",
    BigInt.from(faceDimension),
  );

  static final localGalleryCatFace = PetVectorDB._named(
    "ente.ml.offline.vectordb.pet.cat_face.usearch",
    BigInt.from(faceDimension),
  );

  static final localGalleryDogBody = PetVectorDB._named(
    "ente.ml.offline.vectordb.pet.dog_body.usearch",
    BigInt.from(bodyDimension),
  );

  static final localGalleryCatBody = PetVectorDB._named(
    "ente.ml.offline.vectordb.pet.cat_body.usearch",
    BigInt.from(bodyDimension),
  );

  static final List<PetVectorDB> allInstances = [
    dogFace,
    catFace,
    dogBody,
    catBody,
  ];

  static final List<PetVectorDB> allLocalGalleryInstances = [
    localGalleryDogFace,
    localGalleryCatFace,
    localGalleryDogBody,
    localGalleryCatBody,
  ];

  // Species is 0 for dogs and 1 for cats.
  static PetVectorDB forModel({
    required int species,
    required bool isFace,
    bool localGallery = false,
  }) {
    assert(
      species == 0 || species == 1,
      'Invalid pet species: $species (expected 0=dog or 1=cat)',
    );
    if (localGallery) {
      if (species == 0) {
        return isFace ? localGalleryDogFace : localGalleryDogBody;
      } else {
        return isFace ? localGalleryCatFace : localGalleryCatBody;
      }
    }
    if (species == 0) {
      return isFace ? dogFace : dogBody;
    } else {
      return isFace ? catFace : catBody;
    }
  }

  Future<VectorDb>? _vectorDbFuture;
  final Lock _writeLock = Lock();

  Future<VectorDb> get _vectorDB async {
    _vectorDbFuture ??= _initVectorDB();
    return _vectorDbFuture!;
  }

  Future<VectorDb> _initVectorDB() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final String dbPath = join(documentsDirectory.path, _databaseName);
    _logger.info("Opening pet vectorDB: DB path $dbPath");
    late VectorDb vectorDB;
    try {
      vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
    } catch (e, s) {
      _logger.severe("Could not open Pet VectorDB at $dbPath", e, s);
      _logger.severe("Deleting the index file and trying again");
      await deleteIndexFile();
      try {
        vectorDB = VectorDb(filePath: dbPath, dimensions: _embeddingDimension);
      } catch (e, s) {
        _logger.severe("Still can't open Pet VectorDB at $dbPath", e, s);
        rethrow;
      }
    }
    final stats = await getIndexStats(vectorDB);
    _logger.info("Pet VectorDB opened with stats: ${stats.toString()}");
    return vectorDB;
  }

  // usearch needs integer keys; faces and bodies use separate ID spaces.

  Future<Map<String, int>> getPetFaceVectorIdMap(
    Iterable<String> petFaceIds, {
    required SqliteDatabase db,
    bool createIfMissing = false,
  }) async {
    final uniqueIds = petFaceIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) return {};

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

  Future<Map<String, int>> getObjectVectorIdMap(
    Iterable<String> objectIds, {
    required SqliteDatabase db,
    bool createIfMissing = false,
  }) async {
    final uniqueIds = objectIds.toSet().toList(growable: false);
    if (uniqueIds.isEmpty) return {};

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

  Future<void> _runWriteOperation(
    Future<void> Function(VectorDb db) operation,
  ) async {
    final db = await _vectorDB;
    await _writeLock.synchronized(() async {
      await operation(db);
    });
  }

  Future<void> insertEmbedding({
    required int vectorId,
    required List<double> embedding,
  }) async {
    try {
      await _runWriteOperation((db) async {
        await db.addVector(key: BigInt.from(vectorId), vector: embedding);
      });
    } catch (e, s) {
      _logger.severe("Error inserting pet embedding", e, s);
      rethrow;
    }
  }

  Future<void> bulkInsertEmbeddings({
    required List<int> vectorIds,
    required List<Float32List> embeddings,
  }) async {
    if (vectorIds.isEmpty || embeddings.isEmpty) {
      return;
    }
    final bigKeys = Uint64List.fromList(vectorIds);
    try {
      await _runWriteOperation((db) async {
        await db.bulkAddVectors(keys: bigKeys, vectors: embeddings);
      });
    } catch (e, s) {
      _logger.severe("Error bulk inserting pet embeddings", e, s);
      rethrow;
    }
  }

  Future<List<Float32List>> getEmbeddings(List<int> vectorIds) async {
    final db = await _vectorDB;
    try {
      final keys = Uint64List.fromList(vectorIds);
      return await db.bulkGetVectors(keys: keys);
    } catch (e, s) {
      _logger.severe("Error getting pet embeddings", e, s);
      rethrow;
    }
  }

  Future<void> deleteEmbeddings(List<int> vectorIds) async {
    if (vectorIds.isEmpty) {
      return;
    }
    try {
      BigInt deletedCount = BigInt.zero;
      await _runWriteOperation((db) async {
        deletedCount = await db.bulkRemoveVectors(
          keys: Uint64List.fromList(vectorIds),
        );
      });
      _logger.info(
        "Deleted $deletedCount pet embeddings, from ${vectorIds.length} keys",
      );
    } catch (e, s) {
      _logger.severe("Error deleting pet embeddings", e, s);
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
      return await db.searchVectors(
        query: query,
        count: BigInt.from(count),
        exact: exact,
      );
    } catch (e, s) {
      _logger.severe("Error searching pet vectors", e, s);
      rethrow;
    }
  }

  Future<void> deleteAllEmbeddings() async {
    try {
      await _runWriteOperation((db) async {
        await db.resetIndex();
      });
    } catch (e, s) {
      _logger.severe("Error deleting all pet embeddings", e, s);
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
      _logger.severe("Error getting pet index stats", e, s);
      rethrow;
    }
  }

  Future<void> deleteIndex() async {
    final db = await _vectorDB;
    try {
      await _writeLock.synchronized(() async {
        await db.deleteIndex();
        _vectorDbFuture = null;
      });
    } catch (e, s) {
      _logger.severe("Error deleting pet index", e, s);
      rethrow;
    }
  }

  Future<void> deleteIndexFile() async {
    await _writeLock.synchronized(() async {
      try {
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final String dbPath = join(documentsDirectory.path, _databaseName);
        _logger.info("Delete pet index file: $dbPath");
        final file = File(dbPath);
        if (await file.exists()) {
          await file.delete();
        }
        _vectorDbFuture = null;
      } catch (e, s) {
        _logger.severe("Error deleting pet index file", e, s);
        rethrow;
      }
    });
  }
}
