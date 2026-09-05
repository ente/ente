import 'dart:async';
import "dart:io";

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import "package:photo_manager/photo_manager.dart";
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/metadata/exif.dart';
import 'package:photos/module/metadata/local_file.dart';
import 'package:photos/utils/dialog_util.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';
import "package:uuid/uuid.dart";

final _logger = Logger("ShareUtil");

Future<void> share(
  BuildContext context,
  List<EnteFile> files, {
  GlobalKey? shareButtonKey,
}) async {
  final remoteOnlyFileCount = files
      .where((element) => element.isRemoteOnlyFile)
      .length;
  final dialog = createProgressDialog(
    context,
    "Preparing...",
    isDismissible: remoteOnlyFileCount > 2,
  );
  await dialog.show();
  try {
    final List<Future<String?>> pathFutures = [];
    for (EnteFile file in files) {
      // iOS origin files are faster to share but remain cached until restart;
      // the share API has no completion callback for cleanup.
      pathFutures.add(
        getFile(file, isOrigin: true).then((fetchedFile) {
          final path = fetchedFile?.path;
          if (path == null && file.localID != null && file.isUploaded) {
            _logger.warning(
              "path was null for $file with localID: ${file.localID}. Getting file from server now",
            );
            return getFileFromServer(
              file,
            ).then((remoteFile) => remoteFile?.path);
          }
          return path;
        }),
      );
    }
    final paths = await Future.wait(pathFutures);
    await dialog.hide();
    final resolvedPaths = <String>[];
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (path == null) {
        _logger.warning(
          "share missing local path for file $i/${files.length} "
          "(remoteOnly: ${files[i].isRemoteOnlyFile})",
        );
        continue;
      }
      resolvedPaths.add(path);
    }
    if (resolvedPaths.isEmpty) {
      _logger.severe(
        "share aborted: unable to resolve any files "
        "(requested: ${files.length}, remoteOnly: $remoteOnlyFileCount)",
      );
      throw ArgumentError("No files resolved for system share");
    }
    final xFiles = resolvedPaths.map((path) => XFile(path)).toList();
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: xFiles,
        sharePositionOrigin: shareButtonRect(context, shareButtonKey),
      ),
    );
  } catch (e, s) {
    _logger.severe(
      "failed to complete system share ${files.length} "
      "(remoteOnly: $remoteOnlyFileCount)",
      e,
      s,
    );
    await dialog.hide();
    if (!context.mounted) return;
    await showGenericErrorDialog(context: context, error: e);
  }
}

Rect shareButtonRect(BuildContext context, GlobalKey? shareButtonKey) {
  Size size = MediaQuery.sizeOf(context);
  final RenderObject? renderObject = shareButtonKey?.currentContext
      ?.findRenderObject();
  RenderBox? renderBox;
  if (renderObject != null && renderObject is RenderBox) {
    renderBox = renderObject;
  }
  if (renderBox == null) {
    return Rect.fromLTWH(0, 0, size.width, size.height / 2);
  }
  size = renderBox.size;
  final Offset position = renderBox.localToGlobal(Offset.zero);
  return Rect.fromCenter(
    center: position + Offset(size.width / 2, size.height / 2),
    width: size.width,
    height: size.height,
  );
}

Future<ShareResult> shareText(
  String text, {
  BuildContext? context,
  GlobalKey? key,
}) async {
  try {
    final sharePosOrigin = _sharePosOrigin(context, key);
    return await SharePlus.instance.share(
      ShareParams(text: text, sharePositionOrigin: sharePosOrigin),
    );
  } catch (e, s) {
    _logger.severe("failed to share text", e, s);
    return ShareResult.unavailable;
  }
}

String formatMemoryShareText(String title, String shareUrl) =>
    '$title: $shareUrl';

String formatAlbumShareText(
  String albumName,
  String? albumDescription,
  String shareUrl,
) {
  final sharedDescription =
      albumDescription != null && albumDescription.characters.length > 100
      ? '${albumDescription.characters.take(100)}...'
      : albumDescription;
  return sharedDescription == null
      ? '$albumName: $shareUrl'
      : '$albumName - $sharedDescription: $shareUrl';
}

Future<ShareResult> shareLinkWithDescription(
  String url, {
  String? description,
  BuildContext? context,
  GlobalKey? key,
}) async {
  final text = description != null ? '$url\n$description' : url;
  return shareText(text, context: context, key: key);
}

Future<List<EnteFile>> convertIncomingSharedMediaToFile(
  List<SharedMediaFile> sharedMedia,
  int collectionID,
) async {
  final List<EnteFile> localFiles = [];
  for (var media in sharedMedia) {
    if (!(media.type == SharedMediaType.image ||
        media.type == SharedMediaType.video)) {
      _logger.warning(
        "ignore unsupported file type ${media.type.toString()} path: ${media.path}",
      );
      continue;
    }
    final enteFile = EnteFile();
    final fileExtension = extension(media.path);
    final safeExtension =
        RegExp(r'^\.[A-Za-z0-9]{1,15}$').stringMatch(fileExtension) ==
            fileExtension
        ? fileExtension
        : '';
    final sharedLocalId = const Uuid().v4() + safeExtension;
    enteFile.title = basename(media.path);
    var ioFile = File(media.path);
    try {
      ioFile = ioFile.renameSync(
        Configuration.instance.getSharedMediaDirectory() + "/" + sharedLocalId,
      );
    } catch (e) {
      if (e is FileSystemException) {
        // renameSync may not move files across filesystems.
        _logger.info("Creating new copy of file in path ${ioFile.path}");
        final newIoFile = ioFile.copySync(
          Configuration.instance.getSharedMediaDirectory() +
              "/" +
              sharedLocalId,
        );
        if (media.path.contains("io.ente.photos")) {
          _logger.info("delete original file in path ${ioFile.path}");
          ioFile.deleteSync();
        }
        ioFile = newIoFile;
      } else {
        rethrow;
      }
    }
    enteFile.localID = sharedMediaIdentifier + sharedLocalId;
    enteFile.collectionID = collectionID;
    enteFile.fileType = media.type == SharedMediaType.image
        ? FileType.image
        : FileType.video;
    if (enteFile.fileType == FileType.image) {
      final dateResult = await tryParseExifDateTime(ioFile, null);
      if (dateResult != null) {
        enteFile.creationTime = dateResult.time.microsecondsSinceEpoch;
      }
    } else if (enteFile.fileType == FileType.video) {
      enteFile.duration = (media.duration ?? 0) ~/ 1000;
    }
    if (enteFile.creationTime == null || enteFile.creationTime == 0) {
      final parsedDateTime = parseDateTimeFromFileNameV2(
        basenameWithoutExtension(media.path),
      );
      if (parsedDateTime != null) {
        enteFile.creationTime = parsedDateTime.microsecondsSinceEpoch;
      } else {
        enteFile.creationTime = DateTime.now().microsecondsSinceEpoch;
      }
    }
    enteFile.modificationTime = enteFile.creationTime;
    enteFile.metadataVersion = -1;
    localFiles.add(enteFile);
  }
  return localFiles;
}

Future<List<EnteFile>> convertPicketAssets(
  List<AssetEntity> pickedAssets,
  int collectionID,
) async {
  final List<EnteFile> localFiles = [];
  for (var asset in pickedAssets) {
    final enteFile = fileFromAsset('', asset);
    enteFile.collectionID = collectionID;
    localFiles.add(enteFile);
  }
  return localFiles;
}

void shareSelected(
  BuildContext context,
  GlobalKey shareButtonKey,
  List<EnteFile> selectedFiles,
) {
  share(context, selectedFiles.toList(), shareButtonKey: shareButtonKey);
}

Future<void> shareAlbumLink(
  BuildContext context,
  String url,
  GlobalKey key, {
  required String albumName,
  String? albumDescription,
}) async {
  await shareText(
    formatAlbumShareText(albumName, albumDescription, url),
    context: context,
    key: key,
  );
}

// iPad share sheets require a source rectangle.
Rect _sharePosOrigin(BuildContext? context, GlobalKey? key) {
  late final Rect rect;
  if (context != null) {
    rect = shareButtonRect(context, key);
  } else {
    rect = const Offset(20.0, 20.0) & const Size(10, 10);
  }
  return rect;
}
