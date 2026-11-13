import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:latlong2/latlong.dart";
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart' hide LatLng;
import 'package:photos/core/configuration.dart';
import "package:photos/db/device_files_db.dart";
import 'package:photos/db/files_db.dart';
import "package:photos/gateways/files/files_gateway.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file_load_result.dart";
import "package:photos/models/freeable_space_info.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/file_magic_service.dart';
import "package:photos/services/ignored_files_service.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";

class FilesService {
  late Logger _logger;
  late FilesDB _filesDB;
  late Configuration _config;

  FilesGateway get _gateway => filesGateway;

  FilesService._privateConstructor() {
    _logger = Logger("FilesService");
    _filesDB = FilesDB.instance;
    _config = Configuration.instance;
  }

  static final FilesService instance = FilesService._privateConstructor();

  Future<int> getFileSize(int uploadedFileID) async {
    try {
      return await _gateway.getFilesSize([uploadedFileID]);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<bool> hasMigratedSizes() async {
    try {
      final List<int> uploadIDsWithMissingSize = await _filesDB
          .getUploadIDsWithMissingSize(_config.getUserID()!);
      if (uploadIDsWithMissingSize.isEmpty) {
        return true;
      }
      await backFillSizes(uploadIDsWithMissingSize);
      return true;
    } catch (e, s) {
      _logger.severe("error during has migrated sizes", e, s);
      return Future.value(false);
    }
  }

  Future<void> backFillSizes(List<int> uploadIDsWithMissingSize) async {
    final batchedFiles = uploadIDsWithMissingSize.chunks(1000);
    for (final batch in batchedFiles) {
      final Map<int, int> uploadIdToSize = await getFilesSizeFromInfo(batch);
      await _filesDB.updateSizeForUploadIDs(uploadIdToSize);
    }
  }

  Future<FreeableSpaceInfo> getFreeableSpaceInfo({String? pathID}) async {
    // PhotoManager cannot delete iCloud shared-album assets.
    final excludeLocalIDs = await _getICloudSharedAlbumAssetIDs();
    FreeableFileIDs ids;
    final bool hasMigratedSize = await FilesService.instance.hasMigratedSizes();
    if (pathID == null) {
      ids = await FilesDB.instance.getFreeableFileIDs(
        ownerID: Configuration.instance.getUserID()!,
        excludeLocalIDs: excludeLocalIDs,
      );
    } else {
      ids = await FilesDB.instance.getFreeableFileIDsForDeviceCollection(
        pathID,
        Configuration.instance.getUserID()!,
        excludeLocalIDs: excludeLocalIDs,
      );
    }
    late int size;
    if (hasMigratedSize) {
      size = ids.localSize;
    } else {
      size = await _getFileSize(ids.uploadedIDs);
    }
    return FreeableSpaceInfo(ids.localIDs, size);
  }

  Future<List<AssetPathEntity>> _getICloudSharedAlbumPaths() async {
    if (!Platform.isIOS) return [];
    return PhotoManager.getAssetPathList(
      hasAll: false,
      type: RequestType.common,
      pathFilterOption: const PMPathFilter(
        darwin: PMDarwinPathFilter(
          type: [PMDarwinAssetCollectionType.album],
          subType: [PMDarwinAssetCollectionSubtype.albumCloudShared],
        ),
      ),
    );
  }

  Future<Set<String>> _getICloudSharedAlbumAssetIDs() async {
    final paths = await _getICloudSharedAlbumPaths();
    final Set<String> sharedIDs = {};
    for (final path in paths) {
      final count = await path.assetCountAsync;
      final assets = await path.getAssetListRange(start: 0, end: count);
      for (final asset in assets) {
        sharedIDs.add(asset.id);
      }
    }
    _logger.info("Found ${sharedIDs.length} assets in iCloud shared albums");
    return sharedIDs;
  }

  Future<Set<String>> getICloudSharedAlbumPathIDs() async {
    final paths = await _getICloudSharedAlbumPaths();
    return paths.map((p) => p.id).toSet();
  }

  Future<int> _getFileSize(List<int> fileIDs) async {
    try {
      return await _gateway.getFilesSize(fileIDs);
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
  }

  Future<Map<int, int>> getFilesSizeFromInfo(List<int> uploadedFileID) async {
    try {
      return await _gateway.getFilesInfo(uploadedFileID);
    } catch (e, s) {
      _logger.severe("failed to fetch size from fileInfo", e, s);
      rethrow;
    }
  }

  Future<void> bulkEditLocationData(
    List<EnteFile> files,
    LatLng location,
    BuildContext context,
  ) async {
    final List<EnteFile> uploadedFiles = files
        .where((element) => element.uploadedFileID != null)
        .toList();

    final List<EnteFile> remoteFilesToUpdate = [];
    final Map<int, Map<String, dynamic>> fileIDToUpdateMetadata = {};
    await showActionSheet(
      context: context,
      body: context.strings.changeLocationOfSelectedItems,
      buttons: [
        ButtonWidget(
          labelText: context.strings.yes,
          buttonType: ButtonType.neutral,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          isInAlert: true,
          onTap: () async {
            await _editLocationData(
              uploadedFiles,
              fileIDToUpdateMetadata,
              remoteFilesToUpdate,
              location,
            );
          },
        ),
        ButtonWidget(
          labelText: context.strings.cancel,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
        ),
      ],
    );
  }

  Future<void> _editLocationData(
    List<EnteFile> uploadedFiles,
    Map<int, Map<String, dynamic>> fileIDToUpdateMetadata,
    List<EnteFile> remoteFilesToUpdate,
    LatLng location,
  ) async {
    for (EnteFile remoteFile in uploadedFiles) {
      if (remoteFile.ownerID != _config.getUserID()! ||
          fileIDToUpdateMetadata.containsKey(remoteFile.uploadedFileID!)) {
        continue;
      }

      remoteFilesToUpdate.add(remoteFile);
      fileIDToUpdateMetadata[remoteFile.uploadedFileID!] = {
        latKey: location.latitude,
        longKey: location.longitude,
      };
    }

    if (remoteFilesToUpdate.isNotEmpty) {
      await FileMagicService.instance.updatePublicMagicMetadata(
        remoteFilesToUpdate,
        null,
        metadataUpdateMap: fileIDToUpdateMetadata,
      );
    }
  }

  Future<void> removeIgnoredFiles(Future<FileLoadResult> result) async {
    final ignoredIDs = await IgnoredFilesService.instance.idToIgnoreReasonMap;
    (await result).files.removeWhere(
      (f) =>
          f.uploadedFileID == null &&
          IgnoredFilesService.instance.shouldSkipUpload(ignoredIDs, f),
    );
  }
}
