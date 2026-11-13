import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/album_slideshow/album_slideshow_page.dart";

Future<bool> showAlbumSlideshow(
  BuildContext context, {
  required Iterable<EnteFile> files,
  required String title,
  bool includeBackupExcludedFiles = false,
}) async {
  final ignoredIDs = includeBackupExcludedFiles
      ? null
      : await IgnoredFilesService.instance.idToIgnoreReasonMap;
  if (!context.mounted) return false;

  final uploadedFileIDs = <int>{};
  final localFileIDs = <String>{};
  final slideshowFiles = <EnteFile>[];
  for (final file in files) {
    if (file.fileType != FileType.image &&
        file.fileType != FileType.livePhoto) {
      continue;
    }

    final uploadedFileID = file.uploadedFileID;
    if (uploadedFileID == null &&
        ignoredIDs != null &&
        IgnoredFilesService.instance.shouldSkipUpload(ignoredIDs, file)) {
      continue;
    }

    if (uploadedFileID != null) {
      if (!uploadedFileIDs.add(uploadedFileID)) continue;
    } else {
      final localFileID = file.localID;
      if (localFileID != null && !localFileIDs.add(localFileID)) continue;
    }
    slideshowFiles.add(file);
  }

  if (slideshowFiles.isEmpty) {
    showToast(context, context.strings.noPhotosFoundHere);
    return false;
  }

  await routeToPage(
    context,
    AlbumSlideshowPage(files: slideshowFiles, title: title),
    forceCustomPageRoute: true,
  );
  return true;
}
