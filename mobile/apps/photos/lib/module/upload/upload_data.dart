import 'dart:async';
import "dart:io";
import 'dart:typed_data';

import 'package:ente_crypto/ente_crypto.dart';
import "package:ente_pure_utils/ente_pure_utils.dart"
    show deleteFileSystemEntityIfPresent;
import "package:exif_reader/exif_reader.dart";
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/errors.dart';
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/location/location.dart";
import 'package:photos/module/download/file.dart';
import 'package:photos/module/download/thumbnail.dart';
import 'package:photos/module/live_photo/upload.dart';
import "package:photos/module/metadata/exif.dart";
import 'package:photos/module/metadata/location.dart';
import "package:photos/module/metadata/video.dart";
import 'package:photos/module/upload/model/media_upload_data.dart';
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";
import "package:photos/utils/apple_photos_errors.dart";
import "package:photos/utils/image_util.dart";
import 'package:video_thumbnail/video_thumbnail.dart';

final _logger = Logger("UploadData");

/// Builds the source, thumbnail, hashes, and embedded metadata for an upload.
Future<MediaUploadData> getUploadDataFromEnteFile(EnteFile file) async {
  if (file.isSharedMediaToAppSandbox) {
    return await _getMediaUploadDataFromAppCache(file);
  } else {
    return await _getMediaUploadDataFromAssetFile(file);
  }
}

/// Computes only the hashes needed to decide whether a local file changed.
Future<FileHashData> getFileContentIdentity(EnteFile file) async {
  if (file.isSharedMediaToAppSandbox) {
    final sourceFile = File(getSharedMediaFilePath(file));
    if (!sourceFile.existsSync()) {
      throw InvalidFileError(
        "source missing in sandbox",
        InvalidReason.sourceFileMissing,
      );
    }
    return FileHashData(
      CryptoUtil.bin2base64(await CryptoUtil.getHash(sourceFile)),
    );
  }

  final asset = await _getAsset(file);
  final sourceFile = await _getOriginFile(asset, file);
  try {
    final sourceHash = CryptoUtil.bin2base64(
      await CryptoUtil.getHash(sourceFile),
    );
    if (file.fileType == FileType.livePhoto && Platform.isIOS) {
      final livePhoto = await getLivePhotoHashDataForComparison(
        file,
        sourceFile,
        sourceHash,
      );
      return FileHashData(livePhoto.fileHash, zipHash: livePhoto.zipHash);
    }
    return FileHashData(sourceHash);
  } finally {
    if (Platform.isIOS) {
      await deleteFileSystemEntityIfPresent(sourceFile);
    }
  }
}

Future<MediaUploadData> _getMediaUploadDataFromAssetFile(EnteFile file) async {
  File? sourceFile;
  Uint8List? thumbnailData;
  bool isDeleted;
  String? zipHash;
  String fileHash;
  Map<String, IfdTag>? exifData;
  String? cameraMake;
  String? cameraModel;

  final asset = await _getAsset(file);
  file.fileSubType = asset.subtype;
  if (file.fileType == FileType.video) {
    file.duration = asset.duration;
  }
  sourceFile = await _getOriginFile(asset, file);
  try {
    if (shouldReadExif(file)) {
      exifData = await tryExifFromFile(sourceFile);
      if (exifData != null) {
        cameraMake = extractPrintableExifValue(exifData['Image Make']);
        cameraModel = extractPrintableExifValue(exifData['Image Model']);
      }
    }
    // h4ck to fetch location data if missing (thank you Android Q+) lazily only during uploads
    await _decorateEnteFileData(file, asset, sourceFile, exifData);
    fileHash = CryptoUtil.bin2base64(await CryptoUtil.getHash(sourceFile));

    if (file.fileType == FileType.livePhoto && Platform.isIOS) {
      final livePhoto = await prepareLivePhotoForUpload(
        file,
        sourceFile,
        fileHash,
      );
      sourceFile = livePhoto.sourceFile;
      fileHash = livePhoto.fileHash;
      zipHash = livePhoto.zipHash;
    }

    thumbnailData = await _getThumbnailForUpload(asset, file);
    isDeleted = !(await asset.exists);
    int? h, w;
    if (asset.width != 0 && asset.height != 0) {
      w = asset.width;
      h = asset.height;
      if (Platform.isAndroid &&
          file.fileType == FileType.image &&
          shouldSwapDimensionsForExifOrientation(exifData)) {
        final temp = w;
        w = h;
        h = temp;
      }
    }
    int? motionPhotoStartingIndex;
    if (Platform.isAndroid && asset.type == AssetType.image) {
      try {
        final videoIndex = await getMotionVideoIndex(filePath: sourceFile.path);
        motionPhotoStartingIndex = videoIndex?.start.toInt();
      } catch (e) {
        _logger.severe('error while detecthing motion photo start index', e);
      }
    }
    return MediaUploadData(
      sourceFile: sourceFile,
      thumbnail: thumbnailData,
      isDeleted: isDeleted,
      hashData: FileHashData(fileHash, zipHash: zipHash),
      derivedMetadata: DerivedMediaMetadata(
        height: h,
        width: w,
        cameraMake: cameraMake,
        cameraModel: cameraModel,
        motionPhotoStartIndex: motionPhotoStartingIndex,
        exifData: exifData,
      ),
    );
  } catch (_) {
    if (Platform.isIOS) {
      await deleteFileSystemEntityIfPresent(sourceFile!);
    }
    rethrow;
  }
}

Future<AssetEntity> _getAsset(EnteFile file) async {
  // The timeout safeguards against
  // https://github.com/CaiJingLong/flutter_photo_manager/issues/467.
  final asset = await file.getAsset
      .timeout(const Duration(seconds: 3))
      .catchError((e) async {
        if (e is TimeoutException) {
          _logger.info("Asset fetch timed out for " + file.toString());
          return await file.getAsset;
        }
        throw e;
      });
  if (asset == null) {
    throw InvalidFileError("", InvalidReason.assetDeleted);
  }
  _assertFileType(asset, file);
  return asset;
}

Future<File> _getOriginFile(AssetEntity asset, EnteFile file) async {
  if (Platform.isIOS) {
    trackOriginFetchForUploadOrML.put(file.localID!, true);
  }
  File? sourceFile;
  try {
    sourceFile = await asset.originFile
        .timeout(const Duration(seconds: 15))
        .catchError((e) async {
          if (e is TimeoutException) {
            _logger.info("Origin file fetch timed out for " + file.tag);
            return await asset.originFile;
          }
          throw e;
        });
  } catch (e) {
    if (isPHPhotosNetworkError(e)) {
      throw InvalidFileError(
        phPhotosResourceUnavailableReason,
        InvalidReason.photosResourceUnavailable,
      );
    }
    rethrow;
  }
  if (sourceFile == null || !sourceFile.existsSync()) {
    throw InvalidFileError(
      "id: ${file.localID}",
      InvalidReason.sourceFileMissing,
    );
  }
  return sourceFile;
}

Future<Uint8List?> _getThumbnailForUpload(
  AssetEntity asset,
  EnteFile file,
) async {
  try {
    final Uint8List? thumbnailData = await asset.thumbnailDataWithSize(
      const ThumbnailSize(thumbnailLargeSize, thumbnailLargeSize),
      quality: thumbnailQuality,
    );
    if (thumbnailData == null) {
      // allow videos to be uploaded without thumbnails
      if (asset.type == AssetType.video) {
        return null;
      }
      throw InvalidFileError(
        "no thumbnail : ${file.fileType} ${file.tag}",
        InvalidReason.thumbnailMissing,
      );
    }
    return compressThumbnailToSizeLimit(thumbnailData);
  } catch (e) {
    final String errMessage =
        "thumbErr for ${file.fileType}, ${extension(file.displayName)} ${file.tag}";
    _logger.warning(errMessage, e);
    // allow videos to be uploaded without thumbnails
    if (asset.type == AssetType.video) {
      return null;
    }
    throw InvalidFileError(errMessage, InvalidReason.thumbnailMissing);
  }
}

// check if the assetType is still the same. This can happen for livePhotos
// if the user turns off the video using native photos app
void _assertFileType(AssetEntity asset, EnteFile file) {
  final assetType = fileTypeFromAsset(asset);
  if (assetType == file.fileType) {
    return;
  }
  if (Platform.isIOS || Platform.isMacOS) {
    if (assetType == FileType.image && file.fileType == FileType.livePhoto) {
      throw InvalidFileError(
        'id ${asset.id}',
        InvalidReason.livePhotoToImageTypeChanged,
      );
    } else if (assetType == FileType.livePhoto &&
        file.fileType == FileType.image) {
      throw InvalidFileError(
        'id ${asset.id}',
        InvalidReason.imageToLivePhotoTypeChanged,
      );
    }
  }
  throw InvalidFileError(
    'fileType mismatch for id ${asset.id} assetType $assetType fileType ${file.fileType}',
    InvalidReason.unknown,
  );
}

Future<void> _decorateEnteFileData(
  EnteFile file,
  AssetEntity asset,
  File sourceFile,
  Map<String, IfdTag>? exifData,
) async {
  // h4ck to fetch location data if missing (thank you Android Q+) lazily only during uploads
  if (file.location == null ||
      (file.location!.latitude == 0 && file.location!.longitude == 0)) {
    final latLong = await asset.latlngAsync();
    file.location = Location(
      latitude: latLong.latitude,
      longitude: latLong.longitude,
    );
  }
  await updateLocationFromEmbeddedMetadata(file, sourceFile, exifData);
  if (Platform.isIOS) {
    final originalTitle = await asset.titleAsync;
    if (originalTitle.isNotEmpty) {
      file.title = originalTitle;
      return;
    }
  }
  if (file.title == null || file.title!.isEmpty) {
    _logger.warning("Title was missing ${file.tag}");
    file.title = await asset.titleAsync;
  }
}

Future<MediaUploadData> _getMediaUploadDataFromAppCache(EnteFile file) async {
  File sourceFile;
  Uint8List? thumbnailData;
  Map<String, IfdTag>? exifData;
  String? cameraMake;
  String? cameraModel;
  const bool isDeleted = false;
  final localPath = getSharedMediaFilePath(file);
  sourceFile = File(localPath);
  if (!sourceFile.existsSync()) {
    _logger.warning("File doesn't exist in app sandbox");
    throw InvalidFileError(
      "source missing in sandbox",
      InvalidReason.sourceFileMissing,
    );
  }
  thumbnailData = await _getAppCacheThumbnailForUpload(file);
  final fileHash = CryptoUtil.bin2base64(await CryptoUtil.getHash(sourceFile));
  ({int width, int height})? dimensions;
  if (file.fileType == FileType.image) {
    dimensions = await getImageDimensions(imagePath: localPath);
    exifData = await tryExifFromFile(sourceFile);
    if (exifData != null) {
      cameraMake = extractPrintableExifValue(exifData['Image Make']);
      cameraModel = extractPrintableExifValue(exifData['Image Model']);
      if (!file.hasLocation) {
        final exifLocation = locationFromExif(exifData);
        if (Location.isValidLocation(exifLocation)) {
          file.location = exifLocation;
        }
      }
    }
  } else if (thumbnailData != null) {
    // The thumbnail null check ensures that video thumbnail generation worked.
    // Use it without a max dimension to obtain the video's aspect ratio.
    final thumbnailFilePath = await VideoThumbnail.thumbnailFile(
      video: localPath,
      imageFormat: ImageFormat.JPEG,
      thumbnailPath: (await getTemporaryDirectory()).path,
      quality: 10,
    );
    dimensions = await getImageDimensions(imagePath: thumbnailFilePath);
  }

  if (!file.hasLocation && file.isVideo && Platform.isAndroid) {
    final FFProbeProps? props = await getVideoProps(sourceFile);
    if (props?.location != null) {
      file.location = props!.location;
    }
  }
  return MediaUploadData(
    sourceFile: sourceFile,
    thumbnail: thumbnailData,
    isDeleted: isDeleted,
    hashData: FileHashData(fileHash),
    derivedMetadata: DerivedMediaMetadata(
      height: dimensions?.height,
      width: dimensions?.width,
      cameraMake: cameraMake,
      cameraModel: cameraModel,
      exifData: exifData,
    ),
  );
}

Future<Uint8List?> _getAppCacheThumbnailForUpload(EnteFile file) async {
  try {
    return await getThumbnailFromInAppCacheFile(file);
  } catch (e, s) {
    _logger.warning("failed to generate thumbnail", e, s);
    throw InvalidFileError(
      "thumbnail failed for appCache fileType: ${file.fileType.toString()}",
      InvalidReason.thumbnailMissing,
    );
  }
}
