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

typedef LivePhotoUploadData = ({
  File sourceFile,
  String fileHash,
  String zipHash,
});

typedef LivePhotoHashData = ({String fileHash, String? zipHash});

typedef _LivePhotoVideoData = ({File file, String fileHash});

final _logger = Logger('LivePhotoUpload');

/// Uploads may prepare several files concurrently. Keep this per-file pipeline
/// sequential to limit duplicate reads and I/O pressure. If Live Photo imports
/// become a bottleneck, profile the shared worker queue before parallelizing it.
Future<LivePhotoUploadData> prepareLivePhotoForUpload(
  EnteFile file,
  File imageFile,
  String imageHash,
) async {
  final videoData = await _getLivePhotoVideoData(file, imageHash);
  final archiveFile = await _createLivePhotoArchiveFile(
    file,
    imageFile,
    videoData.file,
  );
  try {
    // photo_manager can return the same iOS temp copy to concurrent upload or
    // hash-check paths, where cleanup may have already run.
    await deleteFileSystemEntityIfPresent(imageFile);
    final zipHash = CryptoUtil.bin2base64(
      await CryptoUtil.getHash(archiveFile),
    );
    return (
      sourceFile: archiveFile,
      fileHash: videoData.fileHash,
      zipHash: zipHash,
    );
  } catch (_) {
    await deleteFileSystemEntityIfPresent(archiveFile);
    rethrow;
  }
}

/// Computes the modern component hash first and creates the legacy ZIP only
/// when it is still needed to compare an older stored hash.
Future<LivePhotoHashData> getLivePhotoHashDataForComparison(
  EnteFile file,
  File imageFile,
  String imageHash,
) async {
  final videoData = await _getLivePhotoVideoData(file, imageHash);
  final storedHash = file.hash;
  if (storedHash == null ||
      storedHash == videoData.fileHash ||
      storedHash.contains(kLivePhotoHashSeparator)) {
    return (fileHash: videoData.fileHash, zipHash: null);
  }
  final archiveFile = await _createLivePhotoArchiveFile(
    file,
    imageFile,
    videoData.file,
  );
  try {
    return (
      fileHash: videoData.fileHash,
      zipHash: CryptoUtil.bin2base64(await CryptoUtil.getHash(archiveFile)),
    );
  } finally {
    await deleteFileSystemEntityIfPresent(archiveFile);
  }
}

Future<_LivePhotoVideoData> _getLivePhotoVideoData(
  EnteFile file,
  String imageHash,
) async {
  final videoFile = await Motionphoto.getLivePhotoFile(file.localID!);
  if (videoFile == null || !videoFile.existsSync()) {
    final message =
        'missing livePhoto url for  ${file.toString()} with subType ${file.fileSubType}';
    _logger.severe(message);
    throw InvalidFileError(message, InvalidReason.livePhotoVideoMissing);
  }

  final videoHash = CryptoUtil.bin2base64(await CryptoUtil.getHash(videoFile));
  final fileHash = '$imageHash$kLivePhotoHashSeparator$videoHash';
  return (file: videoFile, fileHash: fileHash);
}

Future<File> _createLivePhotoArchiveFile(
  EnteFile file,
  File imageFile,
  File videoFile,
) async {
  final archivePath =
      '${Configuration.instance.getTempDirectory()}${const Uuid().v4()}_${file.generatedID}.elp';
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
