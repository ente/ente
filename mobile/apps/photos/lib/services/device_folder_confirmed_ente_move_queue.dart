import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/device_folder_confirmed_move_planner.dart';
import 'package:synchronized/synchronized.dart';

enum ConfirmedMoveQueueDecision { defer, discard, ready, completed }

ConfirmedMoveQueueDecision resolvePreparedConfirmedMove({
  required bool mappingsValid,
  required bool onlyInDestination,
  required int sourceRowCount,
}) {
  if (!mappingsValid || sourceRowCount > 1 || sourceRowCount == 0) {
    return ConfirmedMoveQueueDecision.discard;
  }
  if (onlyInDestination && sourceRowCount == 1) {
    return ConfirmedMoveQueueDecision.ready;
  }
  return ConfirmedMoveQueueDecision.defer;
}

ConfirmedMoveQueueDecision resolveReadyConfirmedMove({
  required bool isPendingUpload,
  required bool mappingsValid,
  required bool onlyInDestination,
  required int sourceRowCount,
  required int destinationRowCount,
}) {
  if (isPendingUpload) return ConfirmedMoveQueueDecision.defer;
  if (!mappingsValid || !onlyInDestination || sourceRowCount > 1) {
    return ConfirmedMoveQueueDecision.discard;
  }
  if (sourceRowCount == 1) return ConfirmedMoveQueueDecision.ready;
  return destinationRowCount == 1
      ? ConfirmedMoveQueueDecision.completed
      : ConfirmedMoveQueueDecision.discard;
}

class DeviceFolderConfirmedEnteMoveQueue {
  DeviceFolderConfirmedEnteMoveQueue._();

  static final instance = DeviceFolderConfirmedEnteMoveQueue._();

  static final _logger = Logger('DeviceFolderConfirmedEnteMoveQueue');
  final _processingLock = Lock();

  Future<void> prepare(ConfirmedDeviceFolderMovePlan plan) async {
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null || plan.entries.isEmpty) return;
    final db = await FilesDB.instance.sqliteAsyncDB;
    final createdAt = DateTime.now().microsecondsSinceEpoch;
    await db.executeBatch(
      'INSERT OR REPLACE INTO ${FilesDB.deviceFolderEnteMoveQueueTable} '
      '(owner_id, source_path_id, destination_path_id, source_collection_id, '
      'destination_collection_id, local_id, state, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?, \'prepared\', ?);',
      plan.entries
          .map(
            (entry) => [
              ownerID,
              plan.source.id,
              plan.destination.id,
              entry.sourceCollectionID,
              entry.destinationCollectionID,
              entry.localID,
              createdAt,
            ],
          )
          .toList(growable: false),
    );
  }

  Future<void> settle({
    required ConfirmedDeviceFolderMovePlan plan,
    required Set<String> successfulLocalIDs,
  }) async {
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null || plan.entries.isEmpty) return;
    final db = await FilesDB.instance.sqliteAsyncDB;
    for (final entry in plan.entries) {
      final params = _queueParams(
        ownerID,
        plan.source,
        plan.destination,
        entry,
      );
      await db.execute(
        successfulLocalIDs.contains(entry.localID)
            ? 'UPDATE ${FilesDB.deviceFolderEnteMoveQueueTable} '
                  "SET state = 'ready' WHERE ${_queueWhere()} AND state = 'prepared';"
            : 'DELETE FROM ${FilesDB.deviceFolderEnteMoveQueueTable} '
                  "WHERE ${_queueWhere()} AND state = 'prepared';",
        params,
      );
    }
  }

  Future<void> discardPrepared(ConfirmedDeviceFolderMovePlan plan) =>
      settle(plan: plan, successfulLocalIDs: const {});

  Future<void> processPendingMoves() async {
    try {
      await _processingLock.synchronized(_processPendingMoves);
    } catch (error, stackTrace) {
      _logger.warning(
        'Could not process confirmed device-folder moves in Ente',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _processPendingMoves() async {
    if (!Platform.isAndroid ||
        isLocalGalleryMode ||
        !Configuration.instance.isLoggedIn()) {
      return;
    }
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null) return;
    await _recoverPreparedMoves(ownerID);
    final queuedMoves = await _load(ownerID);
    if (queuedMoves.isEmpty) return;

    final folders = {
      for (final folder in await FilesDB.instance.getDeviceCollections())
        folder.id: folder,
    };
    final memberships = await _memberships(
      queuedMoves.map((move) => move.localID),
    );
    final readyMoves = <_ReadyQueuedMove>[];
    for (final move in queuedMoves) {
      try {
        final readyMove = await _processReadyMove(
          move,
          folders,
          memberships[move.localID],
        );
        if (readyMove != null) readyMoves.add(readyMove);
      } catch (error, stackTrace) {
        _logger.warning(
          'Could not process confirmed device-folder move',
          error,
          stackTrace,
        );
      }
    }
    final movesByCollectionPair = <(int, int), List<_ReadyQueuedMove>>{};
    for (final readyMove in readyMoves) {
      movesByCollectionPair
          .putIfAbsent((
            readyMove.move.sourceCollectionID,
            readyMove.move.destinationCollectionID,
          ), () => [])
          .add(readyMove);
    }
    for (final readyMoves in movesByCollectionPair.values) {
      final move = readyMoves.first.move;
      try {
        await CollectionsService.instance.move(
          readyMoves.map((readyMove) => readyMove.file.copyWith()).toList(),
          toCollectionID: move.destinationCollectionID,
          fromCollectionID: move.sourceCollectionID,
        );
        await _delete(readyMoves.map((readyMove) => readyMove.move));
      } catch (error, stackTrace) {
        _logger.warning(
          'Could not process confirmed device-folder move',
          error,
          stackTrace,
        );
        if (_shouldIsolateFailedBatch(error)) {
          for (final readyMove in readyMoves) {
            try {
              await CollectionsService.instance.move(
                [readyMove.file.copyWith()],
                toCollectionID: readyMove.move.destinationCollectionID,
                fromCollectionID: readyMove.move.sourceCollectionID,
              );
              await _delete([readyMove.move]);
            } catch (error, stackTrace) {
              _logger.warning(
                'Could not process confirmed device-folder move',
                error,
                stackTrace,
              );
            }
          }
        }
      }
    }
  }

  Future<void> _recoverPreparedMoves(int ownerID) async {
    final prepared = await _load(ownerID, state: 'prepared');
    if (prepared.isEmpty) return;
    final folders = {
      for (final folder in await FilesDB.instance.getDeviceCollections())
        folder.id: folder,
    };
    final memberships = await _memberships(
      prepared.map((move) => move.localID),
    );
    for (final move in prepared) {
      final source = folders[move.sourceFolderID];
      final destination = folders[move.destinationFolderID];
      final localMappingAvailable =
          source != null &&
          destination != null &&
          memberships[move.localID] != null;
      if (!localMappingAvailable) {
        await _delete([move]);
        continue;
      }
      final sourceFiles = await _sourceFiles(move);
      final decision = resolvePreparedConfirmedMove(
        mappingsValid: _hasSavedLinkedMappings(move, source, destination),
        onlyInDestination: _isOnlyInDestination(
          memberships[move.localID],
          move.destinationFolderID,
        ),
        sourceRowCount: sourceFiles.length,
      );
      if (decision == ConfirmedMoveQueueDecision.defer) {
        continue;
      }
      if (decision == ConfirmedMoveQueueDecision.discard) {
        await _delete([move]);
        continue;
      }
      await _setReady(move);
    }
  }

  Future<_ReadyQueuedMove?> _processReadyMove(
    _QueuedMove move,
    Map<String, DeviceCollection> folders,
    Set<String>? membership,
  ) async {
    final source = folders[move.sourceFolderID];
    final destination = folders[move.destinationFolderID];
    final sourceFiles = await _sourceFiles(move);
    final decision = resolveReadyConfirmedMove(
      isPendingUpload: FileUploader.instance.allBackups.containsKey(
        move.localID,
      ),
      mappingsValid:
          source != null &&
          destination != null &&
          _hasSavedLinkedMappings(move, source, destination),
      onlyInDestination: _isOnlyInDestination(
        membership,
        move.destinationFolderID,
      ),
      sourceRowCount: sourceFiles.length,
      destinationRowCount: sourceFiles.isEmpty
          ? (await _destinationFiles(move)).length
          : 0,
    );
    if (decision == ConfirmedMoveQueueDecision.defer) return null;
    if (decision != ConfirmedMoveQueueDecision.ready) {
      await _delete([move]);
      return null;
    }

    final refreshed = {
      for (final folder in await FilesDB.instance.getDeviceCollections())
        folder.id: folder,
    };
    final refreshedSource = refreshed[move.sourceFolderID];
    final refreshedDestination = refreshed[move.destinationFolderID];
    if (refreshedSource == null ||
        refreshedDestination == null ||
        !_hasSavedLinkedMappings(move, refreshedSource, refreshedDestination)) {
      await _delete([move]);
      return null;
    }
    final currentMembership = (await _memberships([
      move.localID,
    ]))[move.localID];
    final currentSourceFiles = await _sourceFiles(move);
    final currentDestinationFiles = currentSourceFiles.isEmpty
        ? await _destinationFiles(move)
        : const <EnteFile>[];
    final currentDecision = resolveReadyConfirmedMove(
      isPendingUpload: FileUploader.instance.allBackups.containsKey(
        move.localID,
      ),
      mappingsValid: _hasSavedLinkedMappings(
        move,
        refreshedSource,
        refreshedDestination,
      ),
      onlyInDestination: _isOnlyInDestination(
        currentMembership,
        move.destinationFolderID,
      ),
      sourceRowCount: currentSourceFiles.length,
      destinationRowCount: currentDestinationFiles.length,
    );
    if (currentDecision == ConfirmedMoveQueueDecision.defer) return null;
    if (currentDecision != ConfirmedMoveQueueDecision.ready) {
      await _delete([move]);
      return null;
    }
    return _ReadyQueuedMove(move, currentSourceFiles.single.copyWith());
  }

  bool _hasSavedLinkedMappings(
    _QueuedMove move,
    DeviceCollection source,
    DeviceCollection destination,
  ) {
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null ||
        !source.shouldBackup ||
        !destination.shouldBackup ||
        source.collectionID != move.sourceCollectionID ||
        destination.collectionID != move.destinationCollectionID) {
      return false;
    }
    final sourceCollection = CollectionsService.instance.getCollectionByID(
      move.sourceCollectionID,
    );
    final destinationCollection = CollectionsService.instance.getCollectionByID(
      move.destinationCollectionID,
    );
    return sourceCollection != null &&
        destinationCollection != null &&
        sourceCollection.canLinkToDevicePath(ownerID) &&
        destinationCollection.canLinkToDevicePath(ownerID);
  }

  Future<Map<String, Set<String>>> _memberships(Iterable<String> localIDs) =>
      FilesDB.instance.getDevicePathIDsForLocalIDs(localIDs);

  bool _isOnlyInDestination(Set<String>? membership, String destinationID) =>
      membership?.length == 1 && membership!.single == destinationID;

  bool _shouldIsolateFailedBatch(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode;
    return statusCode == 400 || statusCode == 404 || statusCode == 409;
  }

  Future<List<EnteFile>> _sourceFiles(_QueuedMove move) =>
      FilesDB.instance.getUploadedFilesForLocalIDs([
        move.localID,
      ], collectionID: move.sourceCollectionID);

  Future<List<EnteFile>> _destinationFiles(_QueuedMove move) =>
      FilesDB.instance.getUploadedFilesForLocalIDs([
        move.localID,
      ], collectionID: move.destinationCollectionID);

  Future<void> _setReady(_QueuedMove move) async {
    final db = await FilesDB.instance.sqliteAsyncDB;
    await db.execute(
      'UPDATE ${FilesDB.deviceFolderEnteMoveQueueTable} '
      "SET state = 'ready' WHERE ${_queueWhere()} AND state = 'prepared';",
      move.params,
    );
  }

  Future<Map<String, Set<String>>> pendingDestinationLocalIDsByFolder() async {
    if (!Platform.isAndroid) return const {};
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null) return const {};
    final db = await FilesDB.instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT destination_path_id, local_id '
      'FROM ${FilesDB.deviceFolderEnteMoveQueueTable} '
      "WHERE owner_id = ? AND state IN ('prepared', 'ready');",
      [ownerID],
    );
    final result = <String, Set<String>>{};
    for (final row in rows) {
      final folderID = row['destination_path_id'] as String;
      result
          .putIfAbsent(folderID, () => <String>{})
          .add(row['local_id'] as String);
    }
    return result;
  }

  Future<List<_QueuedMove>> _load(int ownerID, {String state = 'ready'}) async {
    final db = await FilesDB.instance.sqliteAsyncDB;
    final rows = await db.getAll(
      'SELECT owner_id, source_path_id, destination_path_id, '
      'source_collection_id, destination_collection_id, local_id '
      'FROM ${FilesDB.deviceFolderEnteMoveQueueTable} '
      'WHERE owner_id = ? AND state = ? ORDER BY created_at ASC;',
      [ownerID, state],
    );
    return rows
        .map(
          (row) => _QueuedMove(
            ownerID: row['owner_id'] as int,
            sourceFolderID: row['source_path_id'] as String,
            destinationFolderID: row['destination_path_id'] as String,
            sourceCollectionID: row['source_collection_id'] as int,
            destinationCollectionID: row['destination_collection_id'] as int,
            localID: row['local_id'] as String,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _delete(Iterable<_QueuedMove> queuedMoves) async {
    final moves = queuedMoves.toList(growable: false);
    if (moves.isEmpty) return;
    final db = await FilesDB.instance.sqliteAsyncDB;
    await db.executeBatch(
      'DELETE FROM ${FilesDB.deviceFolderEnteMoveQueueTable} '
      'WHERE ${_queueWhere()};',
      moves.map((move) => move.params).toList(growable: false),
    );
  }

  static String _queueWhere() =>
      'owner_id = ? AND source_path_id = ? AND destination_path_id = ? '
      'AND source_collection_id = ? AND destination_collection_id = ? '
      'AND local_id = ?';

  static List<Object> _queueParams(
    int ownerID,
    DeviceCollection source,
    DeviceCollection destination,
    ConfirmedDeviceFolderMoveEntry entry,
  ) => [
    ownerID,
    source.id,
    destination.id,
    entry.sourceCollectionID,
    entry.destinationCollectionID,
    entry.localID,
  ];
}

class _ReadyQueuedMove {
  const _ReadyQueuedMove(this.move, this.file);

  final _QueuedMove move;
  final EnteFile file;
}

class _QueuedMove {
  const _QueuedMove({
    required this.ownerID,
    required this.sourceFolderID,
    required this.destinationFolderID,
    required this.sourceCollectionID,
    required this.destinationCollectionID,
    required this.localID,
  });

  final int ownerID;
  final String sourceFolderID;
  final String destinationFolderID;
  final int sourceCollectionID;
  final int destinationCollectionID;
  final String localID;

  List<Object> get params => [
    ownerID,
    sourceFolderID,
    destinationFolderID,
    sourceCollectionID,
    destinationCollectionID,
    localID,
  ];
}
