import 'dart:async';
import 'dart:collection';
import 'dart:io';
import "dart:typed_data";

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart'
    show isFileSystemPathMissing;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/cache/thumbnail_in_memory_cache.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/download/file.dart';
import "package:photos/module/download/file_url.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/utils/file_key.dart";
import 'package:video_thumbnail/video_thumbnail.dart';

final _logger = Logger("ThumbnailUtil");
final _uploadIDToDownloadItem = <int, _ThumbnailDownload>{};
final _downloadQueue = Queue<_ThumbnailDownload>();
const int _maximumConcurrentDownloads = 500;
const int _maximumThumbnailCompressionAttempts = 2;

class _ThumbnailDownload {
  final EnteFile file;
  final Completer<Uint8List> completer;
  final CancelToken cancelToken;
  int counter = 0; // number of times file download was requested

  _ThumbnailDownload(this.file, this.completer, this.cancelToken, this.counter);
}

Future<Uint8List> compressThumbnail(Uint8List thumbnail) {
  return FlutterImageCompress.compressWithList(
    thumbnail,
    minHeight: compressedThumbnailResolution,
    minWidth: compressedThumbnailResolution,
    quality: 25,
  );
}

Future<Uint8List> compressThumbnailToSizeLimit(
  Uint8List thumbnail, {
  int maxAttempts = _maximumThumbnailCompressionAttempts,
}) async {
  var result = thumbnail;
  for (
    var attempt = 0;
    result.length > thumbnailDataLimit && attempt < maxAttempts;
    attempt++
  ) {
    _logger.info("Thumbnail size ${result.length}");
    result = await compressThumbnail(result);
    _logger.info("Compressed thumbnail size ${result.length}");
  }
  return result;
}

Future<Uint8List?> getThumbnail(EnteFile file) async {
  if (file.isRemoteOnlyFile) {
    return getThumbnailFromServer(file);
  } else {
    return getThumbnailFromLocal(file, size: thumbnailLargeSize);
  }
}

void preloadThumbnail(EnteFile file) {
  if (file.isRemoteOnlyFile) {
    getThumbnailFromServer(file);
  } else {
    getThumbnailFromLocal(file);
  }
}

Future<({bool acquiredPendingRequestRef, Future<void> pendingRequest})>
preloadThumbnailWithPendingRequestRef(EnteFile file) async {
  if (!file.isRemoteOnlyFile) {
    unawaited(getThumbnailFromLocal(file));
    return (
      acquiredPendingRequestRef: false,
      pendingRequest: Future<void>.value(),
    );
  }
  final request = await _getThumbnailFromServerRequest(file);
  final pendingRequest = request.future.then<void>((_) {}, onError: (_, _) {});
  unawaited(pendingRequest);
  return (
    acquiredPendingRequestRef: request.acquiredPendingRequestRef,
    pendingRequest: pendingRequest,
  );
}

// Note: This method should only be called for files that have been uploaded
// since cachedThumbnailPath depends on the file's uploadedID
Future<File?> getThumbnailForUploadedFile(EnteFile file) async {
  final cachedThumbnail = cachedThumbnailPath(file);
  if (await cachedThumbnail.exists()) {
    _logger.info("Thumbnail already exists for ${file.uploadedFileID}");
    return cachedThumbnail;
  }
  final thumbnail = await getThumbnail(file);
  if (thumbnail != null) {
    // it might be already written to this path during `getThumbnail(file)`
    if (!await cachedThumbnail.exists()) {
      final didWrite = await _writeCachedThumbnail(
        cachedThumbnail,
        thumbnail,
        flush: true,
      );
      if (!didWrite) {
        _logger.info(
          "Thumbnail obtained but not persisted for ${file.uploadedFileID}",
        );
        return null;
      }
    }
    _logger.info("Thumbnail obtained for ${file.uploadedFileID}");
    return cachedThumbnail;
  }
  _logger.severe("Failed to get thumbnail for ${file.uploadedFileID}");
  return null;
}

Future<Uint8List> getThumbnailFromServer(EnteFile file) async {
  final request = await _getThumbnailFromServerRequest(file);
  return request.future;
}

Future<({Future<Uint8List> future, bool acquiredPendingRequestRef})>
_getThumbnailFromServerRequest(EnteFile file) async {
  final cachedThumbnail = cachedThumbnailPath(file);
  final cachedData = await _readCachedThumbnailIfPresent(cachedThumbnail, file);
  if (cachedData != null) {
    return (
      future: Future<Uint8List>.value(cachedData),
      acquiredPendingRequestRef: false,
    );
  }
  // Check if there's already in flight request for fetching thumbnail from the
  // server
  final existing = _uploadIDToDownloadItem[file.uploadedFileID];
  if (existing == null) {
    final item = _ThumbnailDownload(
      file,
      Completer<Uint8List>(),
      CancelToken(),
      1,
    );
    _uploadIDToDownloadItem[file.uploadedFileID!] = item;
    if (_downloadQueue.length >= _maximumConcurrentDownloads) {
      final oldest = _downloadQueue.removeFirst();
      _removeIfCurrent(oldest);
      oldest.cancelToken.cancel();
      if (!oldest.completer.isCompleted) {
        oldest.completer.completeError(RequestCancelledError());
      }
    }
    _downloadQueue.add(item);
    _downloadItem(item);
    return (future: item.completer.future, acquiredPendingRequestRef: true);
  } else {
    existing.counter++;
    return (future: existing.completer.future, acquiredPendingRequestRef: true);
  }
}

Future<Uint8List?> getThumbnailFromLocal(
  EnteFile file, {
  int size = thumbnailSmallSize,
  int quality = thumbnailQuality,
}) async {
  final lruCachedThumbnail = ThumbnailInMemoryLruCache.get(file, size);
  if (lruCachedThumbnail != null) {
    return lruCachedThumbnail;
  }
  if (file.isUploaded) {
    final cachedThumbnail = cachedThumbnailPath(file);
    final data = await _readCachedThumbnailIfPresent(
      cachedThumbnail,
      file,
      size: size,
    );
    if (data != null) {
      return data;
    }
  }
  if (file.isSharedMediaToAppSandbox) {
    //todo:neeraj support specifying size/quality
    return getThumbnailFromInAppCacheFile(file).then((data) {
      if (data != null) {
        ThumbnailInMemoryLruCache.put(file, data, size);
      }
      return data;
    });
  } else {
    return file.getAsset.then((asset) async {
      if (asset == null || !(await asset.exists)) {
        return null;
      }
      return asset
          .thumbnailDataWithSize(ThumbnailSize(size, size), quality: quality)
          .then((data) {
            ThumbnailInMemoryLruCache.put(file, data, size);
            return data;
          });
    });
  }
}

Future<Uint8List?> getThumbnailFromInAppCacheFile(EnteFile file) async {
  var localFile = File(getSharedMediaFilePath(file));
  if (!localFile.existsSync()) {
    return null;
  }
  if (file.fileType == FileType.video) {
    try {
      final thumbnailFilePath = await VideoThumbnail.thumbnailFile(
        video: localFile.path,
        imageFormat: ImageFormat.JPEG,
        thumbnailPath: (await getTemporaryDirectory()).path,
        maxWidth: thumbnailLargeSize,
        quality: 80,
      );
      localFile = File(thumbnailFilePath!);
    } catch (e) {
      _logger.warning('Failed to generate video thumbnail', e);
      return null;
    }
  }
  return compressThumbnailToSizeLimit(await localFile.readAsBytes());
}

void removePendingGetThumbnailRequestIfAny(EnteFile file) {
  final item = _uploadIDToDownloadItem[file.uploadedFileID];
  if (item != null) {
    item.counter--;
    if (item.counter <= 0) {
      _removeIfCurrent(item);
      item.cancelToken.cancel();
    }
  }
}

void _downloadItem(_ThumbnailDownload item) async {
  try {
    await _downloadAndDecryptThumbnail(item);
  } catch (e, s) {
    _logger.severe(
      "Failed to download thumbnail " + item.file.toString(),
      e,
      s,
    );
    if (!item.completer.isCompleted) {
      item.completer.completeError(e, s);
    }
  } finally {
    _removeIfCurrent(item);
  }
}

Future<void> _downloadAndDecryptThumbnail(_ThumbnailDownload item) async {
  final file = item.file;
  Uint8List encryptedThumbnail;
  try {
    if (CollectionsService.instance.isSharedPublicLink(file.collectionID!)) {
      final headers = CollectionsService.instance.publicCollectionHeaders(
        file.collectionID!,
      );
      encryptedThumbnail = (await NetworkClient.instance.downloadDio.get(
        FileUrl.getUrl(file.uploadedFileID!, FileUrlType.publicThumbnail),
        options: Options(headers: headers, responseType: ResponseType.bytes),
      )).data;
    } else {
      encryptedThumbnail = (await NetworkClient.instance.downloadDio.get(
        FileUrl.getUrl(file.uploadedFileID!, FileUrlType.thumbnail),
        options: Options(
          headers: {"X-Auth-Token": Configuration.instance.getToken()},
          responseType: ResponseType.bytes,
        ),
        cancelToken: item.cancelToken,
      )).data;
    }
  } catch (e) {
    if (e is DioException && CancelToken.isCancel(e)) {
      return;
    }
    rethrow;
  }
  if (!_isCurrent(item)) {
    return;
  }
  final thumbnailDecryptionKey =
      CollectionsService.instance.isSharedPublicLink(file.collectionID!)
      ? await getPublicFileKeyUsingBgWorker(file)
      : await getFileKeyUsingBgWorker(file);
  Uint8List data;
  try {
    data = await CryptoUtil.decryptChaCha(
      encryptedThumbnail,
      thumbnailDecryptionKey,
      CryptoUtil.base642bin(file.thumbnailDecryptionHeader!),
    );
  } catch (e, s) {
    _logger.severe("Failed to decrypt thumbnail ${item.file.toString()}", e, s);
    if (!item.completer.isCompleted) {
      item.completer.completeError(e, s);
    }
    return;
  }
  data = await compressThumbnailToSizeLimit(data, maxAttempts: 1);
  if (!_isCurrent(item)) {
    return;
  }
  ThumbnailInMemoryLruCache.put(item.file, data);
  final cachedThumbnail = cachedThumbnailPath(item.file);
  // data is already cached in-memory, no need to await on disk write
  unawaited(_writeCachedThumbnail(cachedThumbnail, data));
  if (!item.completer.isCompleted) {
    item.completer.complete(data);
  }
}

// A canceled download can finish after a replacement for the same file starts.
// Only the request that still owns the map entry may publish or clear state.
bool _isCurrent(_ThumbnailDownload item) =>
    identical(_uploadIDToDownloadItem[item.file.uploadedFileID], item);

void _removeIfCurrent(_ThumbnailDownload item) {
  _downloadQueue.removeWhere((queued) => identical(queued, item));
  if (_isCurrent(item)) {
    _uploadIDToDownloadItem.remove(item.file.uploadedFileID);
  }
}

Future<Uint8List?> _readCachedThumbnailIfPresent(
  File cachedThumbnail,
  EnteFile file, {
  int? size,
}) async {
  if (!await cachedThumbnail.exists()) {
    return null;
  }
  try {
    final data = await cachedThumbnail.readAsBytes();
    ThumbnailInMemoryLruCache.put(file, data, size);
    return data;
  } on FileSystemException catch (e) {
    if (isFileSystemPathMissing(e)) {
      _logger.info(
        "Thumbnail cache file missing during read; treating as cache miss: "
        "${cachedThumbnail.path}",
      );
      return null;
    }
    rethrow;
  }
}

Future<bool> _writeCachedThumbnail(
  File cachedThumbnail,
  Uint8List data, {
  bool flush = false,
}) async {
  try {
    await cachedThumbnail.writeAsBytes(data, flush: flush);
    return true;
  } on FileSystemException catch (e) {
    if (!isFileSystemPathMissing(e)) {
      rethrow;
    }
    _logger.info(
      "Thumbnail cache directory missing during write; recreating: "
      "${cachedThumbnail.parent.path}",
    );
    await cachedThumbnail.parent.create(recursive: true);
    try {
      await cachedThumbnail.writeAsBytes(data, flush: flush);
      return true;
    } on FileSystemException catch (retryError) {
      if (isFileSystemPathMissing(retryError)) {
        _logger.info(
          "Thumbnail cache path still missing after recreate; skipping write: "
          "${cachedThumbnail.path}",
        );
        return false;
      }
      rethrow;
    }
  }
}

File cachedThumbnailPath(EnteFile file) {
  final thumbnailCacheDirectory = Configuration.instance
      .getThumbnailCacheDirectory();
  final uploadedFileID = file.uploadedFileID;
  if (uploadedFileID != null && uploadedFileID != -1) {
    return File("$thumbnailCacheDirectory/$uploadedFileID");
  }

  final localID = file.localID;
  if (localID != null && localID.isNotEmpty) {
    return File(
      "$thumbnailCacheDirectory/local-${Uri.encodeComponent(localID)}",
    );
  }

  return File(
    "$thumbnailCacheDirectory/generated-${file.generatedID ?? "unknown"}",
  );
}

File cachedFaceCropPath(String faceID, bool useTempCache) {
  late final String thumbnailCacheDirectory;
  if (useTempCache) {
    thumbnailCacheDirectory = Configuration.instance
        .getThumbnailCacheDirectory();
  } else {
    thumbnailCacheDirectory = Configuration.instance
        .getPersonFaceThumbnailCacheDirectory();
  }
  return File(thumbnailCacheDirectory + "/" + faceID);
}
