import 'dart:async';

import 'package:collection/collection.dart';
import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:logging/logging.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/services/device_folder_confirmed_ente_move_queue.dart';
import 'package:photos/services/device_folder_confirmed_move_planner.dart';
import 'package:photos/services/sync/local_sync_service.dart';

class DeviceFolderTransferCoordinator {
  DeviceFolderTransferCoordinator._();

  static final instance = DeviceFolderTransferCoordinator._();

  final _logger = Logger('DeviceFolderTransferCoordinator');
  final _client = DeviceFolderTransferClient();

  Future<DeviceFolderTransferResult> transfer({
    required DeviceFolderTransferRequest request,
    required DeviceCollection source,
    required DeviceCollection destination,
    ConfirmedDeviceFolderMovePlan? confirmedMovePlan,
  }) async {
    if (!DeviceFolderTransferClient.isSupportedOnCurrentPlatform) {
      throw UnsupportedError('Device folder transfers are Android-only');
    }
    final result = await LocalSyncService.instance.getLock().synchronized(
      () async {
        final folders = await FilesDB.instance.getDeviceCollections();
        final currentSource = folders.firstWhereOrNull(
          (folder) => folder.id == source.id,
        );
        final currentDestination = folders.firstWhereOrNull(
          (folder) => folder.id == destination.id,
        );
        if (currentSource == null || currentDestination == null) {
          throw StateError('The selected device folder is no longer available');
        }
        if (request.sourceFolderID != currentSource.id ||
            request.targetFolderID != currentDestination.id) {
          throw StateError('The device folder transfer request is stale');
        }
        if (source.shouldBackup != currentSource.shouldBackup ||
            destination.shouldBackup != currentDestination.shouldBackup) {
          throw StateError('The device folder backup state changed');
        }
        ConfirmedDeviceFolderMovePlan? preparedPlan;
        if (confirmedMovePlan != null &&
            request.operation == DeviceFolderTransferOperation.move) {
          preparedPlan = await DeviceFolderConfirmedMovePlanner.instance
              .planDeviceMove(
                source: currentSource,
                destination: currentDestination,
                localIDs: confirmedMovePlan.entries.map(
                  (entry) => entry.localID,
                ),
              );
          if (preparedPlan != null && preparedPlan.entries.isNotEmpty) {
            await DeviceFolderConfirmedEnteMoveQueue.instance.prepare(
              preparedPlan,
            );
          }
        }
        late final DeviceFolderTransferResult result;
        try {
          result = await _client.transfer(request);
        } catch (_) {
          if (preparedPlan != null) {
            await DeviceFolderConfirmedEnteMoveQueue.instance.discardPrepared(
              preparedPlan,
            );
          }
          rethrow;
        }
        if (result.destinations.isEmpty) {
          if (preparedPlan != null) {
            await DeviceFolderConfirmedEnteMoveQueue.instance.settle(
              plan: preparedPlan,
              successfulLocalIDs: const {},
            );
          }
          return result;
        }
        if (request.operation == DeviceFolderTransferOperation.move &&
            result.destinations.entries.any(
              (entry) => entry.key != entry.value,
            )) {
          _logger.warning('Native move unexpectedly changed a local ID');
          if (preparedPlan != null) {
            await DeviceFolderConfirmedEnteMoveQueue.instance.settle(
              plan: preparedPlan,
              successfulLocalIDs: const {},
            );
          }
          return result.copyWith(localReconciliationFailed: true);
        }
        if (request.operation == DeviceFolderTransferOperation.move &&
            result.destinations.isNotEmpty) {
          final movedLocalIDs = result.destinations.keys.toSet();
          try {
            await FilesDB.instance.deletePathIDToLocalIDMapping({
              currentSource.id: movedLocalIDs,
            });
            await FilesDB.instance.insertPathIDToLocalIDMapping({
              currentDestination.id: movedLocalIDs,
            });
          } catch (error, stackTrace) {
            _logger.warning(
              'Could not reconcile completed device-folder move',
              error,
              stackTrace,
            );
            return result.copyWith(localReconciliationFailed: true);
          }
        }
        if (preparedPlan != null) {
          await DeviceFolderConfirmedEnteMoveQueue.instance.settle(
            plan: preparedPlan,
            successfulLocalIDs: result.successLocalIDs,
          );
        }
        return result;
      },
    );
    if (!result.wasCancelled && result.destinations.isNotEmpty) {
      unawaited(LocalSyncService.instance.refreshAfterDeviceFolderTransfer());
    }
    return result;
  }
}
