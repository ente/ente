import 'dart:io';

import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/module/metadata/local_file.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/sync/local_sync_service.dart';

class DeviceFolderTransferService {
  static final instance = DeviceFolderTransferService._();
  static final _logger = Logger('DeviceFolderTransferService');
  final _client = const DeviceFolderTransferClient();

  DeviceFolderTransferService._();

  Future<Set<DeviceFolderTransferOperation>> supportedOperations({
    String? sourceFolderID,
  }) async {
    if (!Platform.isIOS || !isLocalGalleryMode) {
      return {};
    }
    return _client.supportedOperations(sourceFolderID: sourceFolderID);
  }

  Future<List<DeviceCollection>> destinations({
    required DeviceFolderTransferOperation operation,
    required String? sourceFolderID,
  }) async {
    final paths = await PhotoManager.getAssetPathList(
      hasAll: false,
      type: RequestType.common,
      pathFilterOption: const PMPathFilter(
        darwin: PMDarwinPathFilter(type: [PMDarwinAssetCollectionType.album]),
      ),
      filterOption: FilterOptionGroup(
        orders: [const OrderOption(type: OrderOptionType.createDate)],
      ),
    );
    final eligibleIDs = await _client.eligibleDestinationIDs(
      operation: operation,
      sourceFolderID: sourceFolderID,
      candidateFolderIDs: paths.map((path) => path.id).toList(),
    );
    final folders = <DeviceCollection>[];
    for (final path in paths.where((path) => eligibleIDs.contains(path.id))) {
      final cover = await path.getAssetListPaged(page: 0, size: 1);
      folders.add(
        DeviceCollection(
          path.id,
          path.name,
          count: await path.assetCountAsync,
          thumbnail: cover.isEmpty
              ? null
              : fileFromAsset(path.name, cover.first),
        ),
      );
    }
    return folders;
  }

  Future<({DeviceFolderTransferResult result, bool refreshFailed})> transfer({
    required DeviceFolderTransferOperation operation,
    required String? sourceFolderID,
    required String targetFolderID,
    required List<String> localIDs,
  }) async {
    final localSync = LocalSyncService.instance;
    DeviceFolderTransferResult? result;
    var refreshFailed = false;
    try {
      result = await localSync.getLock().synchronized(() async {
        final operations = await supportedOperations(
          sourceFolderID: sourceFolderID,
        );
        if (!operations.contains(operation)) {
          throw StateError('Device album operation is unavailable');
        }
        return _client.transfer(
          operation: operation,
          sourceFolderID: sourceFolderID,
          targetFolderID: targetFolderID,
          sourceLocalIDs: localIDs,
        );
      });
    } finally {
      if (result?.wasCancelled != true) {
        try {
          await localSync.refreshAfterDeviceFolderTransfer();
        } catch (error, stackTrace) {
          refreshFailed = true;
          _logger.warning(
            'Could not refresh transferred files',
            error,
            stackTrace,
          );
        }
      }
    }
    return (result: result!, refreshFailed: refreshFailed);
  }
}
