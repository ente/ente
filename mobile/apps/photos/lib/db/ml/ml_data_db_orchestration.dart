import "dart:async";
import "dart:typed_data";

import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/cluster_centroid_vector_db.dart";
import "package:photos/db/ml/ml_exclusive_operation.dart";
import "package:photos/db/ml/usearch_clip_vector_db.dart";
import "package:photos/db/ml/usearch_cluster_centroid_vector_db.dart";
import "package:photos/events/embedding_updated_event.dart";
import "package:photos/generated/protos/ente/common/vector.pb.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/compute_controller.dart";
import "package:photos/services/machine_learning/ml_process_lock.dart";
import "package:synchronized/synchronized.dart";

mixin MLDataDBOrchestration implements IMLDataDB<int> {
  int _clusterSummaryMutationVersion = 0;
  Future<void>? _clipVectorDbRecoveryFuture;
  final Lock _clipVectorRecoveryLock = Lock();
  final Lock _clipVectorMigrationLock = Lock();
  bool _clipVectorDbRecoveryRequested = false;
  Future<void>? _clusterCentroidVectorDbRecoveryFuture;
  final Lock _clusterCentroidVectorRecoveryLock = Lock();
  final Lock _clusterCentroidVectorMigrationLock = Lock();
  bool _clusterCentroidVectorDbRecoveryRequested = false;

  UsearchClipVectorDB get clipVectorDB;
  UsearchClusterCentroidVectorDB get clusterCentroidVectorDB;
  Logger get logger;

  Future<void> clearNonPetTables();
  Future<void> clearPetTables();
  Future<void> resetClusterTables({required bool faces});
  Future<void> upsertClusterSummaryRows(Map<String, (Uint8List, int)> summary);
  Future<void> deleteClusterSummaryRow(String clusterID);
  Future<void> insertClipRows(List<ClipEmbedding> embeddings);
  Future<void> deleteClipRows(List<int> fileIDs);
  Future<void> deleteAllClipRows();
  Future<int> countClusterSummaries();
  Future<List<(String, Uint8List)>> getClusterSummaryPage({
    String? beforeClusterID,
    required int limit,
  });
  Future<int> countClipRows();
  Future<List<(int, Uint8List)>> getClipRowsPage({
    required int limit,
    required int offset,
  });
  Future<Map<String, int>> getClusterCentroidVectorIdMap(
    Iterable<String> clusterIDs, {
    bool createIfMissing,
  });
  Future<void> deleteClusterCentroidVectorIdMapping(String clusterID);
  Future<void> clearClusterCentroidVectorIdMappings();

  @override
  Future<void> clearTable() =>
      runMlOperationExclusive(MlOperation.clearData, _clearTable);

  Future<void> _clearTable() async {
    await clearNonPetTables();
    await clipVectorDB.deleteIndexFile();
    await clusterCentroidVectorDB.deleteIndexFile();
    await clearPetTables();
    _markClusterSummaryMutated();
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
    await upsertClusterSummaryRows(summary);
    _markClusterSummaryMutated();

    if (!flagService.enableVectorDb ||
        !await clusterCentroidVectorDB.isReady()) {
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
          logger.warning(
            "Failed to decode centroid embedding for cluster ${entry.key}, skipping vector update",
            e,
            s,
          );
          continue;
        }
        if (centroid.length != ClusterCentroidVectorDB.embeddingDimensions) {
          logger.warning(
            "Unexpected centroid embedding size ${centroid.length} for cluster ${entry.key}, skipping vector update",
          );
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
    await deleteClusterSummaryRow(clusterID);
    _markClusterSummaryMutated();

    if (!flagService.enableVectorDb ||
        !await clusterCentroidVectorDB.isReady()) {
      await deleteClusterCentroidVectorIdMapping(clusterID);
      return;
    }

    try {
      final clusterIDToVectorID = await getClusterCentroidVectorIdMap([
        clusterID,
      ], createIfMissing: false);
      final vectorID = clusterIDToVectorID[clusterID];
      if (vectorID != null) {
        await clusterCentroidVectorDB.deleteCentroids([vectorID]);
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

  @override
  Future<void> dropClustersAndPersonTable({bool faces = false}) async {
    try {
      await resetClusterTables(faces: faces);
      _markClusterSummaryMutated();

      if (await clusterCentroidVectorDB.isReady()) {
        await _withClusterCentroidVectorWriteRecovery(
          operation: "dropClustersAndPersonTable",
          writeOperation: () async {
            await clusterCentroidVectorDB.deleteAllCentroids();
          },
        );
      }
    } catch (e, s) {
      logger.severe('Error dropping clusters and person table', e, s);
    }
  }

  @override
  Future<void> checkMigrateFillClusterCentroidVectorDB({
    bool force = false,
  }) async {
    if (!force && await clusterCentroidVectorDB.isReady()) {
      return;
    }
    await runMlOperationExclusive(
      MlOperation.clusterCentroidVectorMigration,
      () => _checkMigrateFillClusterCentroidVectorDB(force: force),
      waitDeadline: kMlMigrationLockWaitDeadline,
    );
  }

  Future<void> _checkMigrateFillClusterCentroidVectorDB({
    required bool force,
  }) async {
    await _clusterCentroidVectorMigrationLock.synchronized(() async {
      final migrationDone = await clusterCentroidVectorDB.isReady();
      if (migrationDone && !force) {
        logger.info(
          "ClusterCentroidVectorDB migration not needed, already done",
        );
        return;
      }
      logger.info("Starting ClusterCentroidVectorDB migration");

      const maxStableAttempts = 3;
      for (int attempt = 1; attempt <= maxStableAttempts; attempt++) {
        final startMutationVersion = _clusterSummaryMutationSnapshot();
        logger.info(
          "ClusterCentroidVectorDB migration attempt $attempt/$maxStableAttempts from mutationVersion=$startMutationVersion",
        );

        await _runClusterCentroidMigrationPass();

        final endMutationVersion = _clusterSummaryMutationSnapshot();
        if (endMutationVersion != startMutationVersion) {
          logger.info(
            "Cluster summaries changed during migration attempt $attempt (mutationVersion=$startMutationVersion->$endMutationVersion), retrying full migration",
          );
          continue;
        }

        await clusterCentroidVectorDB.setMigrationDone();
        final finalizedMutationVersion = _clusterSummaryMutationSnapshot();
        if (finalizedMutationVersion == endMutationVersion) {
          logger.info("ClusterCentroidVectorDB migration done");
          return;
        }

        logger.info(
          "Cluster summaries changed while finalizing migration attempt $attempt (mutationVersion=$endMutationVersion->$finalizedMutationVersion), retrying full migration",
        );
        await clusterCentroidVectorDB.invalidateMigrationState();
      }

      logger.severe(
        "ClusterCentroidVectorDB migration did not reach a stable snapshot after $maxStableAttempts attempts. Leaving migration state invalidated for safe fallback.",
      );
      await clusterCentroidVectorDB.invalidateMigrationState();
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
    logger.severe(
      "ClusterCentroidVectorDB write failed during `$operation`. Marking migration stale and scheduling rebuild.",
      error,
      stackTrace,
    );
    try {
      await clusterCentroidVectorDB.invalidateMigrationState();
    } catch (invalidateError, invalidateStackTrace) {
      logger.severe(
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
      logger.info(
        "Queued ClusterCentroidVectorDB rebuild from SQLite after index write failure",
      );
      while (computeController.computeState != ComputeRunState.idle) {
        logger.info(
          "Waiting for compute to become idle before ClusterCentroidVectorDB rebuild (current state: ${computeController.computeState})",
        );
        await Future.delayed(idlePollDelay);
      }
      logger.info("Starting ClusterCentroidVectorDB rebuild from SQLite");
      await checkMigrateFillClusterCentroidVectorDB(force: true);
      logger.info("ClusterCentroidVectorDB rebuild from SQLite completed");
    } catch (e, s) {
      logger.severe("ClusterCentroidVectorDB rebuild from SQLite failed", e, s);
    }
  }

  Future<void> _runClusterCentroidMigrationPass() async {
    final totalCount = await countClusterSummaries();
    if (totalCount == 0) {
      logger.info("No cluster summaries to migrate");
      await clearClusterCentroidVectorIdMappings();
      await clusterCentroidVectorDB.deleteAllCentroids();
      return;
    }
    logger.info("Total count of cluster summaries: $totalCount");

    await clusterCentroidVectorDB.deleteAllCentroids();
    await clearClusterCentroidVectorIdMappings();
    logger.info("ClusterCentroidVectorDB cleared before migration");

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
        logger.info("$whileCount st round of centroid migration while loop");
        await Future.delayed(const Duration(milliseconds: 100));

        final results = await getClusterSummaryPage(
          beforeClusterID: lastClusterID,
          limit: batchSize,
        );

        if (results.isEmpty) {
          logger.info("No more centroid rows, breaking out of while loop");
          break;
        }
        lastClusterID = results.last.$1;

        final clusterIDs = <String>[];
        final clusterIDToCentroid = <String, Float32List>{};
        for (final (clusterID, centroidBytes) in results) {
          Float32List centroid;
          try {
            final centroidValues = EVector.fromBuffer(centroidBytes).values;
            centroid = Float32List.fromList(centroidValues);
          } catch (e, s) {
            weirdCount++;
            logger.warning(
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
            logger.warning(
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
        logger.info(
          "migrated $processedCount/$totalCount cluster centroids to ClusterCentroidVectorDB",
        );
      }
      logger.info(
        "migrated $processedCount cluster centroids to ClusterCentroidVectorDB in ${stopwatch.elapsed.inMilliseconds} ms, with $weirdCount malformed rows skipped",
      );
      try {
        final vectorStats = await clusterCentroidVectorDB.getIndexStats();
        if (vectorStats.size != processedCount) {
          logger.warning(
            "ClusterCentroidVectorDB size mismatch: vectorDb=${vectorStats.size}, migratedRows=$processedCount",
          );
        } else {
          logger.info(
            "ClusterCentroidVectorDB size match: vectorDb=${vectorStats.size}, migratedRows=$processedCount",
          );
        }
      } catch (e, s) {
        logger.warning(
          "Failed to log ClusterCentroidVectorDB size after migration",
          e,
          s,
        );
      }
    } catch (e, s) {
      logger.severe(
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

  @override
  Future<void> checkMigrateFillClipVectorDB({bool force = false}) async {
    if (!force && await clipVectorDB.isReady()) {
      return;
    }
    await runMlOperationExclusive(
      MlOperation.clipVectorMigration,
      () => _checkMigrateFillClipVectorDB(force: force),
      waitDeadline: kMlMigrationLockWaitDeadline,
    );
  }

  Future<void> _checkMigrateFillClipVectorDB({required bool force}) async {
    await _clipVectorMigrationLock.synchronized(() async {
      final migrationDone = await clipVectorDB.isReady();
      if (migrationDone && !force) {
        logger.info("ClipVectorDB migration not needed, already done");
        return;
      }
      logger.info("Starting ClipVectorDB migration");

      logger.info("Getting total count of clip embeddings");
      final totalCount = await countClipRows();
      if (totalCount == 0) {
        logger.info("No clip embeddings to migrate");
        await clipVectorDB.deleteAllEmbeddings();
        await clipVectorDB.setMigrationDone();
        return;
      }
      logger.info("Total count of clip embeddings: $totalCount");

      logger.info(
        "First time referencing ClipVectorDB rust index in migration",
      );
      await clipVectorDB.deleteAllEmbeddings();
      logger.info("ClipVectorDB rust index referenced");
      logger.info("ClipVectorDB all embeddings cleared");

      logger.info(
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
        computeController.blockCompute(blocker: migrationKey);
        while (true) {
          whileCount++;
          logger.info("$whileCount st round of while loop");
          await Future.delayed(const Duration(milliseconds: 100));

          logger.info("Reading $batchSize rows from DB");
          final results = await getClipRowsPage(
            limit: batchSize,
            offset: offset,
          );
          logger.info("Got ${results.length} results from DB");
          if (results.isEmpty) {
            logger.info("No more results, breaking out of while loop");
            break;
          }
          logger.info("Processing ${results.length} results");
          final List<int> fileIDs = [];
          final List<Float32List> embeddings = [];
          for (final (fileID, embeddingBytes) in results) {
            final embedding = Float32List.view(embeddingBytes.buffer);
            if (embedding.length == ClipVectorDB.embeddingDimensions) {
              fileIDs.add(fileID);
              embeddings.add(Float32List.view(embeddingBytes.buffer));
            } else if (embedding.isEmpty) {
              emptyCount++;
            } else {
              malformedCount++;
              logger.warning(
                "Malformed clip embedding length ${embedding.length} for fileID $fileID, skipping ClipVectorDB migration for this row",
              );
            }
          }
          logger.info(
            "Got ${fileIDs.length} valid clip embeddings, skipped $emptyCount empty and $malformedCount malformed embeddings so far",
          );

          await clipVectorDB.bulkInsertEmbeddings(
            fileIDs: fileIDs,
            embeddings: embeddings,
          );
          logger.info("Inserted ${fileIDs.length} embeddings to ClipVectorDB");
          processedCount += fileIDs.length;
          offset += batchSize;
          logger.info(
            "migrated $processedCount/$totalCount embeddings to ClipVectorDB",
          );
          if (processedCount >= totalCount) {
            logger.info("All embeddings migrated, breaking out of while loop");
            break;
          }
          logger.info("Waiting for 100ms out of precaution, for GC to finish");
          await Future.delayed(const Duration(milliseconds: 100));
        }
        logger.info(
          "migrated all vectorizable clip embeddings from $totalCount SQLite rows to ClipVectorDB in ${stopwatch.elapsed.inMilliseconds} ms; skipped $emptyCount empty and $malformedCount malformed embeddings",
        );
        await clipVectorDB.setMigrationDone();
        logger.info("ClipVectorDB migration done");
        try {
          final latestClipCount = await getClipVectorizableFileCount();
          final vectorStats = await clipVectorDB.getIndexStats();
          if (vectorStats.size != latestClipCount) {
            logger.warning(
              "ClipVectorDB size mismatch: vectorDb=${vectorStats.size}, clipTableVectorizable=$latestClipCount",
            );
          } else {
            logger.info(
              "ClipVectorDB size match: vectorDb=${vectorStats.size}, clipTableVectorizable=$latestClipCount",
            );
          }
        } catch (e, s) {
          logger.warning(
            "Failed to log ClipVectorDB size after migration",
            e,
            s,
          );
        }
      } catch (e, s) {
        logger.severe(
          "Error migrating ClipVectorDB after ${stopwatch.elapsed.inMilliseconds} ms, clearing out DB again",
          e,
          s,
        );
        await clipVectorDB.deleteAllEmbeddings();
        rethrow;
      } finally {
        stopwatch.stop();
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
    logger.severe(
      "ClipVectorDB write failed during `$operation`. Marking migration stale and scheduling rebuild.",
      error,
      stackTrace,
    );
    try {
      await clipVectorDB.invalidateMigrationState();
    } catch (invalidateError, invalidateStackTrace) {
      logger.severe(
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
      logger.warning(
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
      logger.info(
        "Queued ClipVectorDB rebuild from SQLite after index write failure",
      );
      while (computeController.computeState != ComputeRunState.idle) {
        logger.info(
          "Waiting for compute to become idle before ClipVectorDB rebuild (current state: ${computeController.computeState})",
        );
        await Future.delayed(idlePollDelay);
      }
      logger.info("Starting ClipVectorDB rebuild from SQLite");
      await checkMigrateFillClipVectorDB(force: true);
      logger.info("ClipVectorDB rebuild from SQLite completed");
    } catch (e, s) {
      logger.severe("ClipVectorDB rebuild from SQLite failed", e, s);
    }
  }

  @override
  Future<void> putClip(List<ClipEmbedding> embeddings) async {
    if (embeddings.isEmpty) return;
    final vectorizableEmbeddings = _vectorizableClipEmbeddings(embeddings);
    await insertClipRows(embeddings);
    if (embeddings.length == 1) {
      if (flagService.enableVectorDb &&
          vectorizableEmbeddings.isNotEmpty &&
          await clipVectorDB.isReady()) {
        await _withClipVectorWriteRecovery(
          operation: "putClip(single)",
          writeOperation: () async {
            await clipVectorDB.insertEmbedding(
              fileID: vectorizableEmbeddings.first.fileID,
              embedding: vectorizableEmbeddings.first.embedding,
            );
          },
        );
      }
    } else {
      if (flagService.enableVectorDb &&
          vectorizableEmbeddings.isNotEmpty &&
          await clipVectorDB.isReady()) {
        await _withClipVectorWriteRecovery(
          operation: "putClip(bulk)",
          writeOperation: () async {
            await clipVectorDB.bulkInsertEmbeddings(
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

  @override
  Future<void> deleteClipEmbeddings(List<int> fileIDs) async {
    await deleteClipRows(fileIDs);
    if (flagService.enableVectorDb && await clipVectorDB.isReady()) {
      await _withClipVectorWriteRecovery(
        operation: "deleteClipEmbeddings",
        writeOperation: () async {
          await clipVectorDB.deleteEmbeddings(fileIDs);
        },
      );
    }
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }

  @override
  Future<void> deleteClipIndexes() async {
    await deleteAllClipRows();
    if (flagService.enableVectorDb && await clipVectorDB.isReady()) {
      await _withClipVectorWriteRecovery(
        operation: "deleteClipIndexes",
        writeOperation: () async {
          await clipVectorDB.deleteAllEmbeddings();
        },
      );
    }
    Bus.instance.fire(EmbeddingUpdatedEvent());
  }
}
