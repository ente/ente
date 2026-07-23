import 'dart:io';

import "package:flutter/foundation.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart' as file_path;
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/device_files_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
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

final _logger = Logger("file_download_util");

/// Use this instead of `file.displayName` directly for skip toasts.
///
/// Rationale:
/// 1. We prefer the original title for stable, filename-like copy in the toast.
String getDownloadSkipToastFileName(EnteFile file) {
  final title = (file.title ?? "").trim();
  final displayName = file.displayName.trim();
  return title.isNotEmpty ? title : displayName;
}

String _getGallerySaveTitle(EnteFile file, String fallbackPath) {
  final displayName = file.displayName;
  if (displayName.trim().isNotEmpty) {
    return displayName;
  }
  final title = file.title;
  if (title != null && title.trim().isNotEmpty) {
    return title;
  }
  return file_path.basename(fallbackPath);
}

Future<String?> getExistingLocalFolderNameForDownloadSkipToast(
  EnteFile file,
) async {
  if (file.localID == null) {
    return null;
  }
  final asset = await file.getAsset;
  if (asset == null || !(await asset.exists)) {
    return null;
  }
  final folderNames = await FilesDB.instance.getDeviceCollectionNamesForLocalID(
    file.localID!,
  );
  if (folderNames.isNotEmpty) {
    return folderNames.last;
  }
  // The asset exists on device but no device-collection mapping is recorded
  // yet (e.g. LocalSyncService hasn't ingested it). Treat this as "not
  // skippable" rather than crashing; a duplicate save is preferable to an
  // unhandled StateError surfacing in the download flow.
  _logger.severe(
    "No device collection name found for localID=${file.localID} "
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
    // We use a lock to prevent synchronisation to occur while it is downloading
    // as this introduces wrong entry in FilesDB due to race condition
    // This is a fix for https://github.com/ente/ente/issues/4296
    await LocalSyncService.instance.getLock().synchronized(() async {
      //Disabling notifications for assets changing to insert the file into
      //files db before triggering a sync.
      await PhotoManager.stopChangeNotify();
      if (type == FileType.image) {
        savedAsset = await PhotoManager.editor.saveImageWithPath(
          fileToSave.path,
          title: mediaStoreTitle,
        );
      } else if (type == FileType.video) {
        savedAsset = await PhotoManager.editor.saveVideo(
          fileToSave,
          title: mediaStoreTitle,
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
    });
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
    await PhotoManager.startChangeNotify();
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
