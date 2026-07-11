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

final _logger = Logger('LivePhotoUpload');

/// Uploads may prepare several files concurrently. Keep this per-file pipeline
/// sequential to limit duplicate reads and I/O pressure. If Live Photo imports
/// become a bottleneck, profile the shared worker queue before parallelizing it.
Future<LivePhotoUploadData> prepareLivePhotoForUpload(
  EnteFile file,
  File imageFile,
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
    // photo_manager can return the same iOS temp copy to concurrent upload or
    // hash-check paths, where cleanup may have already run.
    await deleteFileSystemEntityIfPresent(imageFile);
    final zipHash = CryptoUtil.bin2base64(
      await CryptoUtil.getHash(archiveFile),
    );
    return (sourceFile: archiveFile, fileHash: fileHash, zipHash: zipHash);
  } catch (_) {
    await deleteFileSystemEntityIfPresent(archiveFile);
    rethrow;
  }
}
