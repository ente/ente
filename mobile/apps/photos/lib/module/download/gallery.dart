import 'dart:io';

import "package:flutter/foundation.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart' as file_path;
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/device_files_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import 'package:photos/models/ignored_file.dart';
import 'package:photos/module/download/decrypt.dart';
import "package:photos/module/download/file.dart";
import "package:photos/module/download/manager.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/utils/apple_photos_errors.dart";
import "package:photos/utils/device_storage_error.dart";
import "package:photos/utils/gallery_save_title.dart";
import "package:photos/utils/gallery_save_video.dart";

final _logger = Logger("file_download_util");
final _galleryDownloadCountsInProgress = <int, int>{};
final _gallerySaveResultsInProgress = <int, ({AssetEntity? asset})>{};

String getDownloadSkipToastFileName(EnteFile file) {
  final title = (file.title ?? "").trim();
  final displayName = file.displayName.trim();
  return title.isNotEmpty ? title : displayName;
}

String _getGallerySaveTitle(EnteFile file, String fallbackPath) {
  final displayName = file.displayName;
  final title = displayName.trim().isNotEmpty
      ? displayName
      : ((file.title != null && file.title!.trim().isNotEmpty)
            ? file.title!
            : file_path.basename(fallbackPath));
  if (file.fileType == FileType.image &&
      file_path.extension(title).isEmpty &&
      file_path.extension(fallbackPath).toLowerCase() == ".unknown") {
    return "$title.jpg";
  }
  return title;
}

Future<List<AssetEntity?>> _findAssetsOnDevice(List<EnteFile> files) async {
  final assets = await Future.wait(files.map(_getExistingAsset));
  final missingFileIDs = {
    for (var i = 0; i < files.length; i++)
      if (assets[i] == null && files[i].uploadedFileID != null)
        files[i].uploadedFileID!,
  };
  if (missingFileIDs.isEmpty) {
    return assets;
  }
  final linkedRowsByFileID = <int, List<EnteFile>>{};
  final rows = await FilesDB.instance.getFilesFromIDs(missingFileIDs.toList());
  for (final row in rows) {
    if (row.localID != null) {
      linkedRowsByFileID.putIfAbsent(row.uploadedFileID!, () => []).add(row);
    }
  }
  for (var i = 0; i < files.length; i++) {
    if (assets[i] != null) {
      continue;
    }
    for (final row in linkedRowsByFileID[files[i].uploadedFileID] ?? []) {
      assets[i] = await _getExistingAsset(row);
      if (assets[i] != null) {
        break;
      }
    }
  }
  return assets;
}

Future<AssetEntity?> _getExistingAsset(EnteFile file) async {
  final asset = await file.getAsset;
  if (asset == null || !(await asset.exists)) {
    return null;
  }
  return asset;
}

Future<List<String?>> linkDownloadsAlreadyOnDevice(
  List<EnteFile> files, {
  required bool persistToFilesDB,
}) async {
  final assets = await _findAssetsOnDevice(files);
  final folderNames = <String?>[];
  final linkedFiles = <EnteFile>[];
  for (var i = 0; i < files.length; i++) {
    final asset = assets[i];
    if (asset == null) {
      folderNames.add(null);
      continue;
    }
    final folderName = await _getDeviceFolderName(asset);
    folderNames.add(folderName);
    if (folderName != null &&
        persistToFilesDB &&
        files[i].localID != asset.id) {
      files[i].localID = asset.id;
      linkedFiles.add(files[i]);
    }
  }
  if (linkedFiles.isNotEmpty) {
    await FilesDB.instance.insertMultiple(linkedFiles);
    Bus.instance.fire(LocalPhotosUpdatedEvent(linkedFiles, source: "download"));
  }
  return folderNames;
}

Future<String?> _getDeviceFolderName(AssetEntity asset) async {
  final folderNames = await FilesDB.instance.getDeviceCollectionNamesForLocalID(
    asset.id,
  );
  if (folderNames.isNotEmpty) {
    return folderNames.last;
  }
  // The asset exists on device but no device-collection mapping is recorded
  // yet (e.g. LocalSyncService hasn't ingested it). Treat this as "not
  // skippable" rather than crashing; a duplicate save is preferable to an
  // unhandled StateError surfacing in the download flow.
  _logger.severe(
    "No device collection name found for localID=${asset.id} "
    "despite asset existing on device.",
  );
  return null;
}

// Note: callers that tap Download repeatedly on a public-link file
// (persistToFilesDB == false) may produce duplicate on-device copies, because
// the in-memory EnteFile they hold is not updated with the saved localID and
// LocalSyncService ingests the asset as a new local row rather than marking
// the existing remote entry. Revisit if this surfaces as a user complaint.
Future<void> downloadToGallery(
  EnteFile file, {
  bool forceResumableDownload = false,
  bool persistToFilesDB = true,
}) async {
  final fileID = file.uploadedFileID;
  if (fileID != null) {
    _galleryDownloadCountsInProgress.update(
      fileID,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  try {
    await _downloadToGallery(
      file,
      forceResumableDownload: forceResumableDownload,
      persistToFilesDB: persistToFilesDB,
    );
  } catch (e, s) {
    if (forceResumableDownload && isDeviceStorageFullError(e)) {
      _logger.severe("Failed to save file due to storage limit", e, s);
      throw const DeviceStorageFullException();
    }
    if (isPHPhotosUnsupportedResourceError(e)) {
      _logger.warning(
        "Failed to save file because Apple Photos rejected the resource",
        e,
        s,
      );
      throw DownloadFailedError(
        DownloadManager.applePhotosUnsupportedResourceError,
      );
    }
    _logger.severe("Failed to save file", e, s);
    rethrow;
  } finally {
    if (fileID != null) {
      _endGalleryDownload(fileID);
    }
  }
}

void _endGalleryDownload(int fileID) {
  final remaining = _galleryDownloadCountsInProgress[fileID]! - 1;
  if (remaining > 0) {
    _galleryDownloadCountsInProgress[fileID] = remaining;
    return;
  }
  _galleryDownloadCountsInProgress.remove(fileID);
  _gallerySaveResultsInProgress.remove(fileID);
}

Future<void> _downloadToGallery(
  EnteFile file, {
  required bool forceResumableDownload,
  required bool persistToFilesDB,
}) async {
  try {
    final FileType type = file.fileType;
    final bool downloadLivePhotoOnDroid =
        type == FileType.livePhoto && Platform.isAndroid;
    AssetEntity? savedAsset;
    final File? fileToSave = await getFile(
      file,
      forGalleryDownload: forceResumableDownload,
    );
    if (fileToSave == null) {
      throw DownloadFailedError("Unable to fetch file for gallery download");
    }
    final galleryTitle = _getGallerySaveTitle(file, fileToSave.path);
    final mediaStoreTitle = await getMediaStoreCompatibleTitle(galleryTitle);
    // Keep sync from seeing the saved asset before it is inserted into FilesDB.
    // https://github.com/ente/ente/issues/4296
    await LocalSyncService.instance.getLock().synchronized(() async {
      final fileID = file.uploadedFileID;
      var savedResult = fileID == null
          ? null
          : _gallerySaveResultsInProgress[fileID];
      final cachedAsset = savedResult?.asset;
      if (cachedAsset != null && !(await cachedAsset.exists)) {
        savedResult = null;
      }
      savedAsset = savedResult?.asset;
      if (savedResult == null && persistToFilesDB) {
        savedAsset = (await _findAssetsOnDevice([file])).single;
      }
      try {
        await PhotoManager.stopChangeNotify();
        if (savedResult == null && savedAsset == null) {
          if (type == FileType.image) {
            savedAsset = await PhotoManager.editor.saveImageWithPath(
              fileToSave.path,
              title: mediaStoreTitle,
            );
          } else if (type == FileType.video) {
            savedAsset = await saveVideoToGallery(
              fileToSave,
              title: mediaStoreTitle,
              creationDate: file.captureDate,
            );
          } else if (type == FileType.livePhoto) {
            final File? liveVideoFile = await getFileFromServer(
              file,
              liveVideo: true,
              forGalleryDownload: forceResumableDownload,
            );
            if (liveVideoFile == null) {
              throw AssertionError("Live video can not be null");
            }
            if (downloadLivePhotoOnDroid) {
              await _saveLivePhotoOnDroid(
                fileToSave,
                liveVideoFile,
                mediaStoreTitle,
              );
            } else {
              savedAsset = await PhotoManager.editor.darwin.saveLivePhoto(
                imageFile: fileToSave,
                videoFile: liveVideoFile,
                title: galleryTitle,
              );
            }
          }
        }

        if (fileID != null &&
            (savedAsset != null || downloadLivePhotoOnDroid)) {
          _gallerySaveResultsInProgress[fileID] = (asset: savedAsset);
        }
        if (savedAsset != null) {
          // Public-link downloads should be discovered by local sync so they are
          // materialized as true on-device files instead of remote/shared
          // entries in FilesDB.
          if (persistToFilesDB) {
            file.localID = savedAsset!.id;
            await FilesDB.instance.insert(file);
            Bus.instance.fire(
              LocalPhotosUpdatedEvent([file], source: "download"),
            );
          }
        } else if (!downloadLivePhotoOnDroid && savedAsset == null) {
          _logger.severe('Failed to save assert of type $type');
        }
      } finally {
        await PhotoManager.startChangeNotify();
      }
    });
  } finally {
    LocalSyncService.instance.checkAndSync().ignore();
  }
}

Future<void> _saveLivePhotoOnDroid(
  File image,
  File video,
  String imageTitle,
) async {
  debugPrint("Downloading LivePhoto on Droid");
  var savedAsset = await PhotoManager.editor.saveImageWithPath(
    image.path,
    title: imageTitle,
  );
  IgnoredFile ignoreVideoFile = IgnoredFile(
    savedAsset.id,
    savedAsset.title ?? '',
    savedAsset.relativePath ?? 'remoteDownload',
    "remoteDownload",
  );
  await IgnoredFilesService.instance.cacheAndInsert([ignoreVideoFile]);
  final videoTitle = await getMediaStoreCompatibleTitle(
    file_path.basenameWithoutExtension(imageTitle) +
        file_path.extension(video.path),
  );
  savedAsset = await PhotoManager.editor.saveVideo(video, title: videoTitle);

  ignoreVideoFile = IgnoredFile(
    savedAsset.id,
    savedAsset.title ?? videoTitle,
    savedAsset.relativePath ?? 'remoteDownload',
    "remoteDownload",
  );
  await IgnoredFilesService.instance.cacheAndInsert([ignoreVideoFile]);
}
