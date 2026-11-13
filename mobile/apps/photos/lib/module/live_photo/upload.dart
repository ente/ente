import 'dart:io';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart'
    show deleteFileSystemEntityIfPresent;
import 'package:logging/logging.dart';
import 'package:motionphoto/motionphoto.dart';
import 'package:path/path.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/live_photo/archive.dart';
import 'package:uuid/uuid.dart';

typedef LivePhotoUploadData = ({File sourceFile, String fileHash});

final _logger = Logger('LivePhotoUpload');

// Uploads may prepare several files concurrently. Keep this per-file pipeline
// sequential to limit duplicate reads and I/O pressure.
Future<LivePhotoUploadData> prepareLivePhotoForUpload(
  EnteFile livePhoto,
  File imageFile,
  String imageHash,
) async {
  final exportedVideo = await _exportLivePhotoVideo(livePhoto);
  try {
    final livePhotoHash = await _computeLivePhotoHash(exportedVideo, imageHash);
    final archiveFile = await _createLivePhotoArchiveFile(
      livePhoto,
      imageFile,
      exportedVideo,
    );
    try {
      // photo_manager can return the same iOS temp copy to concurrent upload or
      // hash-check paths, where cleanup may have already run.
      await deleteFileSystemEntityIfPresent(imageFile);
      return (sourceFile: archiveFile, fileHash: livePhotoHash);
    } catch (_) {
      await deleteFileSystemEntityIfPresent(archiveFile);
      rethrow;
    }
  } finally {
    await _deleteExportedVideo(exportedVideo);
  }
}

Future<String> getLivePhotoFileHash(
  EnteFile livePhoto,
  String imageHash,
) async {
  final exportedVideo = await _exportLivePhotoVideo(livePhoto);
  try {
    return await _computeLivePhotoHash(exportedVideo, imageHash);
  } finally {
    await _deleteExportedVideo(exportedVideo);
  }
}

Future<File> _exportLivePhotoVideo(EnteFile livePhoto) async {
  final exportedVideo = await Motionphoto.getLivePhotoFile(livePhoto.localID!);
  if (exportedVideo == null || !exportedVideo.existsSync()) {
    final message =
        'missing livePhoto url for  ${livePhoto.toString()} with subType ${livePhoto.fileSubType}';
    _logger.severe(message);
    throw InvalidFileError(message, InvalidReason.livePhotoVideoMissing);
  }
  return exportedVideo;
}

Future<void> _deleteExportedVideo(File exportedVideo) async {
  try {
    await deleteFileSystemEntityIfPresent(exportedVideo);
  } catch (e, s) {
    _logger.warning('Failed to delete backup Live Photo video export', e, s);
  }
}

Future<String> _computeLivePhotoHash(
  File exportedVideo,
  String imageHash,
) async {
  final videoHash = CryptoUtil.bin2base64(
    await CryptoUtil.getHash(exportedVideo),
  );
  return '$imageHash$kLivePhotoHashSeparator$videoHash';
}

Future<File> _createLivePhotoArchiveFile(
  EnteFile livePhoto,
  File imageFile,
  File videoFile,
) async {
  final archivePath =
      '${Configuration.instance.getTempDirectory()}${const Uuid().v4()}_${livePhoto.generatedID}.elp';
  final archiveFile = File(archivePath);
  _logger.info('Creating zip for live photo from ${basename(archivePath)}');

  try {
    await createLivePhotoArchive(
      archivePath: archivePath,
      imagePath: imageFile.path,
      videoPath: videoFile.path,
    );
    return archiveFile;
  } catch (_) {
    await deleteFileSystemEntityIfPresent(archiveFile);
    rethrow;
  }
}
