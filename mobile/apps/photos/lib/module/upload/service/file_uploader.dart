import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import "package:dio/dio.dart";
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import "package:path/path.dart";
import "package:permission_handler/permission_handler.dart";
import 'package:photos/core/configuration.dart';
import "package:photos/core/constants.dart";
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/core/network/network.dart";
import 'package:photos/db/files_db.dart';
import 'package:photos/db/upload_locks_db.dart';
import "package:photos/events/backup_updated_event.dart";
import "package:photos/events/file_uploaded_event.dart";
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/gateways/files/file_upload_gateway.dart";
import "package:photos/main.dart" show isProcessBg, kLastBGTaskHeartBeatTime;
import "package:photos/models/backup/backup_item.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/user_details.dart";
import "package:photos/module/metadata/exif.dart";
import 'package:photos/module/upload/model/media_upload_data.dart';
import 'package:photos/module/upload/model/upload_url.dart';
import "package:photos/module/upload/service/multipart.dart";
import 'package:photos/module/upload/service/upload_artifact_lifecycle.dart';
import 'package:photos/module/upload/service/upload_queue.dart';
import "package:photos/module/upload/upload_data.dart";
import "package:photos/module/upload/upload_metadata.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/file_magic_service.dart';
import 'package:photos/services/sync/local_sync_service.dart';
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/utils/file_key.dart";
import "package:photos/utils/network_util.dart";
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tuple/tuple.dart';
import "package:uuid/uuid.dart";

/// Coordinates encryption, transfer, persistence, and retries for file uploads.
class FileUploader {
  static const kMaximumConcurrentUploads = 4;
  static const kMaximumConcurrentVideoUploads = 2;
  static const kMaximumUploadAttempts = 4;
  static const kMaxFileSize10Gib = 10737418240;
  static const kBlockedUploadsPollFrequency = Duration(seconds: 2);
  static const kFileUploadTimeout = Duration(minutes: 50);
  static const k20MBStorageBuffer = 20 * 1024 * 1024;
  static const _lastStaleFileCleanupTime = "lastStaleFileCleanupTime";

  final _logger = Logger("FileUploader");
  final _dio = NetworkClient.instance.getDio();
  FileUploadGateway get _gateway => fileUploadGateway;
  final _queue = UploadQueue(
    (change) => Bus.instance.fire(BackupUpdatedEvent(change)),
  );
  final _uploadLocks = UploadLocksDB.instance;
  final _uploadArtifactLifecycle = UploadArtifactLifecycle(
    UploadLocksDB.instance,
    FilesDB.instance,
  );
  final kSafeBufferForLockExpiry = const Duration(hours: 4).inMicroseconds;
  final kBGTaskDeathTimeout = const Duration(seconds: 5).inMicroseconds;
  // Track used upload URLs to detect race conditions
  final Map<String, DateTime> _usedUploadURLs = {};

  Map<String, BackupItem> get allBackups => _queue.backupItems;

  /// Returns true if any file uploads are currently in progress
  bool get isUploading => _queue.isUploading;

  /// Returns true if an upload is queued, running, or waiting in background.
  bool get hasPendingUploads => _queue.hasPendingUploads;
  late ProcessType _processType;
  late SharedPreferences _prefs;
  bool _hasStartedBackgroundUploadPolling = false;

  late MultiPartUploader _multiPartUploader;
  StreamSubscription<LocalPhotosUpdatedEvent>? _localPhotosUpdatedSubscription;

  FileUploader._privateConstructor();

  static FileUploader instance = FileUploader._privateConstructor();

  Future<void> init(SharedPreferences preferences, bool isBackground) async {
    _prefs = preferences;
    _processType = isBackground
        ? ProcessType.background
        : ProcessType.foreground;
    final currentTime = DateTime.now().microsecondsSinceEpoch;
    await _uploadLocks.releaseLocksAcquiredByOwnerBefore(
      _processType.toString(),
      currentTime,
    );
    await _uploadLocks.releaseAllLocksAcquiredBefore(
      currentTime - kSafeBufferForLockExpiry,
    );
    if (!isBackground) {
      await _prefs.reload();
      final lastBGTaskHeartBeatTime =
          _prefs.getInt(kLastBGTaskHeartBeatTime) ?? 0;
      final isBGTaskDead =
          lastBGTaskHeartBeatTime < (currentTime - kBGTaskDeathTimeout);
      if (isBGTaskDead) {
        await _uploadLocks.releaseLocksAcquiredByOwnerBefore(
          ProcessType.background.toString(),
          currentTime,
        );
        _logger.info("BG task was found dead, cleared all locks");
      } else {
        _logger.info(
          "BG task is alive, not clearing locks ${DateTime.fromMicrosecondsSinceEpoch(lastBGTaskHeartBeatTime)}",
        );
      }
      if (!_hasStartedBackgroundUploadPolling) {
        _hasStartedBackgroundUploadPolling = true;
        // ignore: unawaited_futures
        _pollBackgroundUploadStatus();
      }
    }
    _multiPartUploader = MultiPartUploader(
      _dio, // legacy parameter, not used by MultiPartUploader
      _dio,
      UploadLocksDB.instance,
      flagService,
    );
    if (currentTime - (_prefs.getInt(_lastStaleFileCleanupTime) ?? 0) >
        tempDirCleanUpInterval) {
      await removeStaleFiles();
      await _prefs.setInt(_lastStaleFileCleanupTime, currentTime);
    }
    if (_localPhotosUpdatedSubscription != null) {
      await _localPhotosUpdatedSubscription!.cancel();
    }
    _localPhotosUpdatedSubscription = Bus.instance
        .on<LocalPhotosUpdatedEvent>()
        .listen((event) {
          if (event.type == EventType.deletedFromDevice ||
              event.type == EventType.deletedFromEverywhere) {
            removeFromQueueWhere(
              (file) {
                for (final updatedFile in event.updatedFiles) {
                  if (file.generatedID == updatedFile.generatedID) {
                    return true;
                  }
                }
                return false;
              },
              InvalidFileError(
                "File already deleted",
                InvalidReason.assetDeletedEvent,
              ),
            );
          }
        });
  }

  // upload future will return null as File when the file entry is deleted
  // locally because it's already present in the destination collection.
  Future<EnteFile> upload(EnteFile file, int collectionID) {
    if (file.localID == null || file.localID!.isEmpty) {
      return Future.error(Exception("file's localID can not be null or empty"));
    }
    final request = _queue.add(file, collectionID);
    if (request.disposition == UploadQueueDisposition.added) {
      _pollQueue();
      return request.item.completer.future;
    }
    // If the file exists in the queue for a matching collectionID,
    // return the existing future
    if (request.disposition == UploadQueueDisposition.sameCollection) {
      return request.item.completer.future;
    }
    debugPrint(
      "Wait on another upload on same local ID to finish before "
      "adding it to new collection",
    );
    // Else wait for the existing upload to complete,
    // and add it to the relevant collection
    return request.item.completer.future.then((uploadedFile) {
      // If the fileUploader completer returned null,
      _logger.info(
        "original upload completer resolved, try adding the file to another "
        "collection",
      );

      return CollectionsService.instance
          .addOrCopyToCollection(collectionID, [uploadedFile])
          .then((aVoid) {
            return uploadedFile;
          });
    });
  }

  int getCurrentSessionUploadCount() {
    return _queue.sessionUploadCount;
  }

  void clearQueue(final Error reason) {
    _queue.clear(reason);
  }

  void clearCachedUploadURLs() {
    _usedUploadURLs.clear();
  }

  /// Validates that the user can upload before starting expensive encryption.
  /// Throws on 402 (no subscription) or 426 (storage exceeded).
  Future<void> validateUploadEligibility() async {
    try {
      await _gateway.validateUploadEligibility();
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        final error = NoActiveSubscriptionError();
        clearQueue(error);
        throw error;
      } else if (e.response?.statusCode == 426) {
        final error = StorageLimitExceededError();
        clearQueue(error);
        throw error;
      }
      rethrow;
    }
  }

  void removeFromQueueWhere(
    final bool Function(EnteFile) fn,
    final Error reason,
  ) {
    final removedCount = _queue.removeWhere(fn, reason);
    _logger.info('number of entries removed from queue $removedCount');
  }

  void _pollQueue() {
    if (SyncService.instance.shouldStopSync()) {
      clearQueue(SyncStopRequestedError());
      return;
    }
    final pendingItem = _queue.startNext(
      maximumConcurrentUploads: kMaximumConcurrentUploads,
      maximumConcurrentVideoUploads: kMaximumConcurrentVideoUploads,
    );
    if (pendingItem != null) {
      _encryptAndUploadFileToCollection(pendingItem);
    }
  }

  Future<EnteFile?> _encryptAndUploadFileToCollection(
    UploadQueueItem item, {
    bool forcedUpload = false,
  }) async {
    final file = item.file;
    final collectionID = item.collectionID;
    try {
      final uploadedFile = await _tryToUpload(file, collectionID, forcedUpload)
          .timeout(
            kFileUploadTimeout,
            onTimeout: () {
              final message = "Upload timed out for file " + file.toString();
              throw TimeoutException(message);
            },
          );
      _queue.complete(item, uploadedFile);
      return uploadedFile;
    } catch (e) {
      if (e is LockAlreadyAcquiredError) {
        return _queue.moveToBackground(item);
      } else {
        _queue.fail(item, e);
        return null;
      }
    } finally {
      _queue.finishAttempt(item);
      _pollQueue();
    }
  }

  Future<void> removeStaleFiles() =>
      _uploadArtifactLifecycle.removeStaleFiles();

  Future<void> checkNetworkForUpload({bool isForceUpload = false}) async {
    // Note: We don't support force uploading currently. During force upload,
    // network check is skipped completely
    if (isForceUpload) {
      return;
    }
    final canUploadUnderCurrentNetworkConditions = await canUseHighBandwidth();

    if (!canUploadUnderCurrentNetworkConditions) {
      throw WiFiUnavailableError();
    }
  }

  Future<void> verifyMediaLocationAccess() async {
    if (Platform.isAndroid) {
      final bool hasPermission = await Permission.accessMediaLocation.isGranted;
      if (!hasPermission) {
        // In background isolate, we can't request permissions (no UI available)
        // Throw an error to properly handle this scenario
        if (isProcessBg) {
          _logger.severe(
            "Media location access not granted in background isolate - cannot request permission",
          );
          throw NoMediaLocationAccessError();
        }
        // Only request permission in foreground
        final permissionStatus = await Permission.accessMediaLocation.request();
        if (!permissionStatus.isGranted) {
          _logger.severe(
            "Media location access denied with permission status: ${permissionStatus.name}",
          );
          throw NoMediaLocationAccessError();
        }
      }
    }
  }

  Future<EnteFile> forceUpload(EnteFile file, int collectionID) {
    return _uploadArtifactLifecycle.runForceUpload(() async {
      final localID = file.localID!;
      final backupOwner = _queue.backupOwner(localID);
      if (backupOwner != null) {
        _queue.markBackupUploading(backupOwner, localID);
      }
      try {
        final result = await _tryToUpload(file, collectionID, true);
        if (backupOwner != null) {
          _queue.markBackupUploaded(backupOwner, localID);
        }
        return result;
      } catch (error) {
        if (backupOwner != null) {
          _queue.markBackupForRetry(backupOwner, localID, error);
        }
        rethrow;
      }
    });
  }

  Future<EnteFile> _tryToUpload(
    EnteFile file,
    int collectionID,
    bool forcedUpload,
  ) async {
    await checkNetworkForUpload(isForceUpload: forcedUpload);
    if (!forcedUpload) {
      final fileOnDisk = await FilesDB.instance.getFile(file.generatedID!);
      final wasAlreadyUploaded =
          fileOnDisk != null &&
          fileOnDisk.uploadedFileID != null &&
          (fileOnDisk.updationTime ?? -1) != -1 &&
          (fileOnDisk.collectionID ?? -1) == collectionID;
      if (wasAlreadyUploaded) {
        _logger.info("File is already uploaded ${fileOnDisk.tag}");
        return fileOnDisk;
      }
    }

    if ((file.localID ?? '') == '') {
      _logger.severe('Trying to upload file with missing localID');
      return file;
    }
    if (!CollectionsService.instance.allowUpload(collectionID)) {
      _logger.warning('Upload not allowed for collection $collectionID');
      if (!file.isUploaded && file.generatedID != null) {
        _logger.info("Deleting file entry for " + file.toString());
        await FilesDB.instance.deleteByGeneratedID(file.generatedID!);
      }
      return file;
    }

    final String lockKey = file.localID!;
    bool isMultipartUpload = false;

    try {
      await _uploadLocks.acquireLock(
        lockKey,
        _processType.toString(),
        DateTime.now().microsecondsSinceEpoch,
      );
    } catch (e) {
      final lockInfo = await _uploadLocks.getLockData(lockKey);
      _logger.warning("Lock was already taken ($lockInfo) for " + file.tag);
      throw LockAlreadyAcquiredError();
    }

    MediaUploadData? mediaUploadData;
    try {
      mediaUploadData = await getUploadDataFromEnteFile(file);
    } catch (e) {
      // This additional try catch block is added because for resumable upload,
      // we need to compute the hash before the next step. Previously, this
      // was done in during the upload itself.
      if (e is InvalidFileError) {
        _logger.severe("File upload ignored for " + file.toString(), e);
        await _onInvalidFileError(file, e);
      }
      await _uploadLocks.releaseLock(lockKey, _processType.toString());
      rethrow;
    }

    final String? existingMultipartEncFileName = await _uploadLocks
        .getEncryptedFileName(
          lockKey,
          mediaUploadData.hashData.fileHash,
          collectionID,
        );
    final sourceLength = await mediaUploadData.sourceFile.length();
    final bool hasExistingMultiPart = existingMultipartEncFileName != null;
    final tempDirectory = Configuration.instance.getTempDirectory();
    final String uniqueID =
        '${const Uuid().v4().toString()}_${file.generatedID}';

    final encryptedFilePath = hasExistingMultiPart
        ? '$tempDirectory$existingMultipartEncFileName'
        : '$tempDirectory$uploadTempFilePrefix${uniqueID}_file.encrypted';
    final encryptedThumbnailPath =
        '$tempDirectory$uploadTempFilePrefix${uniqueID}_thumb.encrypted';
    late final int encFileSize;
    late final int encThumbSize;

    var uploadCompleted = false;
    // This flag is used to decide whether to clear the iOS origin file cache
    // or not.
    var uploadHardFailure = false;

    try {
      final bool isUpdatedFile =
          file.uploadedFileID != null && file.updationTime == -1;
      _logger.info(
        'starting ${forcedUpload ? 'forced' : ''} '
        '${isUpdatedFile ? 're-upload' : 'upload'} of ${file.toString()}',
      );

      Uint8List? key;
      final FileEncryptResult? multiPartFileEncResult = hasExistingMultiPart
          ? await _multiPartUploader.getEncryptionResult(
              lockKey,
              mediaUploadData.hashData.fileHash,
              collectionID,
              existingMultipartEncFileName,
            )
          : null;
      if (isUpdatedFile) {
        key = getFileKey(file);
      } else {
        key = multiPartFileEncResult?.key;
        // check if the file is already uploaded and can be mapped to existing
        // uploaded file. If map is found, it also returns the corresponding
        // mapped or update file entry.
        final result = await _mapToExistingUploadWithSameHash(
          mediaUploadData,
          file,
          collectionID,
        );
        final isMappedToExistingUpload = result.item1;
        if (isMappedToExistingUpload) {
          debugPrint(
            "File success mapped to existing uploaded ${file.toString()}",
          );
          // treat as completed so _onUploadDone clears the source export
          uploadCompleted = true;
          // return the mapped file
          return result.item2;
        }
      }

      final encryptedFileExists = File(encryptedFilePath).existsSync();

      // If the multipart entry exists but the encrypted file doesn't, it means
      // that we'll have to re-upload as the nonce is lost
      if (hasExistingMultiPart) {
        if (!encryptedFileExists) {
          throw MultiPartFileMissingError(
            'multiPartResume: encryptedFile missing',
          );
        }
        final bool updateWithDiffKey =
            isUpdatedFile &&
            multiPartFileEncResult != null &&
            !listEquals(key, multiPartFileEncResult.key);
        if (updateWithDiffKey) {
          throw MultiPartError('multiPart update resumed with differentKey');
        }
      } else if (encryptedFileExists) {
        // otherwise just delete the file for singlepart upload
        _logger.severe('File exists without multipart entry, deleting file');
        await File(encryptedFilePath).delete();
      }
      await _checkIfWithinStorageLimit(mediaUploadData.sourceFile);
      final encryptedFile = File(encryptedFilePath);

      // Calculate the number of parts to determine if we need MD5
      // Use source length to estimate encrypted size for part count decision
      final estimatedEncSize = CryptoUtil.estimateEncryptedSize(sourceLength);
      final estimatedCount = _multiPartUploader.calculatePartCount(
        estimatedEncSize,
      );

      FileEncryptResult? fileAttributes = multiPartFileEncResult;
      String? fileMd5 = fileAttributes?.fileMd5;
      List<String>? partMd5s = fileAttributes?.partMd5s;

      if (fileAttributes == null) {
        final result = await CryptoUtil.encryptFileWithMD5(
          mediaUploadData.sourceFile.path,
          encryptedFilePath,
          key: key,
          multiPartChunkSizeInBytes: (estimatedCount > 1)
              ? _multiPartUploader.multipartPartSizeForUpload
              : null,
        );
        fileAttributes = result;
        fileMd5 = result.fileMd5;
        partMd5s = result.partMd5s;
      }

      late final Uint8List? thumbnailData;
      if (mediaUploadData.thumbnail == null &&
          file.fileType == FileType.video) {
        thumbnailData = base64Decode(blackThumbnailBase64);
      } else {
        thumbnailData = mediaUploadData.thumbnail;
      }
      encFileSize = await encryptedFile.length();
      if (!CryptoUtil.validateStreamEncryptionSizes(
        sourceLength,
        encFileSize,
      )) {
        throw EncSizeMismatchError("source $sourceLength, enc $encFileSize");
      }

      final EncryptionResult encryptedThumbnailData =
          await CryptoUtil.encryptChaCha(thumbnailData!, fileAttributes.key);
      if (File(encryptedThumbnailPath).existsSync()) {
        await File(encryptedThumbnailPath).delete();
      }
      final encryptedThumbnailFile = File(encryptedThumbnailPath);
      await encryptedThumbnailFile.writeAsBytes(
        encryptedThumbnailData.encryptedData!,
      );
      encThumbSize = await encryptedThumbnailFile.length();
      final thumbnailMd5 = await computeMd5(encryptedThumbnailPath);

      // Calculate the number of parts for the file.
      final count = _multiPartUploader.calculatePartCount(encFileSize);

      late String fileObjectKey;
      late String thumbnailObjectKey;

      if (count <= 1) {
        fileMd5 ??= await computeMd5(encryptedFilePath);
        final thumbnailUploadURL = await _getUploadURL(
          contentLength: encThumbSize,
          contentMd5: thumbnailMd5,
        );
        thumbnailObjectKey = await _putFile(
          thumbnailUploadURL,
          encryptedThumbnailFile,
          encThumbSize,
          contentMd5: thumbnailMd5,
        );
        final fileUploadURL = await _getUploadURL(
          contentLength: encFileSize,
          contentMd5: fileMd5,
        );
        fileObjectKey = await _putFile(
          fileUploadURL,
          encryptedFile,
          encFileSize,
          contentMd5: fileMd5,
        );
      } else {
        isMultipartUpload = true;
        _logger.info(
          "Init multipartUpload $hasExistingMultiPart, isUpdate $isUpdatedFile",
        );
        if (hasExistingMultiPart) {
          fileObjectKey = await _multiPartUploader.putExistingMultipartFile(
            encryptedFile,
            lockKey,
            mediaUploadData.hashData.fileHash,
            collectionID,
            existingMultipartEncFileName,
          );
        } else {
          if (partMd5s == null || partMd5s.isEmpty) {
            throw MultiPartError("Missing part MD5s for multipart upload");
          }
          final multipartPartLength =
              fileAttributes.partSize ??
              _multiPartUploader.multipartPartSizeForUpload;
          final fileUploadURLs = await _multiPartUploader
              .getMultipartUploadURLs(
                count: count,
                contentLength: encFileSize,
                partLength: multipartPartLength,
                partMd5s: partMd5s,
              );
          final encFileName = encryptedFile.path.split('/').last;
          await _multiPartUploader.createTableEntry(
            lockKey,
            mediaUploadData.hashData.fileHash,
            collectionID,
            fileUploadURLs,
            encFileName,
            encFileSize,
            fileAttributes.key,
            fileAttributes.header,
            fileMd5: fileMd5,
            partMd5s: partMd5s,
          );
          fileObjectKey = await _multiPartUploader.putMultipartFile(
            fileUploadURLs,
            encryptedFile,
            encFileSize,
            fileMd5: fileMd5,
            partMd5s: partMd5s,
          );
        }
        // in case of multipart, upload the thumbnail towards the end to avoid
        // re-uploading the thumbnail in case of failure.
        // In regular upload, always upload the thumbnail first to keep existing behaviour
        //
        final thumbnailUploadURL = await _getUploadURL(
          contentLength: encThumbSize,
          contentMd5: thumbnailMd5,
        );
        thumbnailObjectKey = await _putFile(
          thumbnailUploadURL,
          encryptedThumbnailFile,
          encThumbSize,
          contentMd5: thumbnailMd5,
        );
      }
      final exifData = mediaUploadData.derivedMetadata.exifData;
      final ParsedExifDateTime? exifTime = exifData != null
          ? await tryParseExifDateTime(null, exifData)
          : null;
      file.metadataVersion = EnteFile.kCurrentMetadataVersion;
      final preparedMetadata = await prepareUploadMetadata(
        file,
        mediaUploadData,
        exifTime,
      );

      final encryptedMetadataResult = await CryptoUtil.encryptChaCha(
        utf8.encode(jsonEncode(preparedMetadata.canonicalMetadata)),
        fileAttributes.key,
      );
      final fileDecryptionHeader = CryptoUtil.bin2base64(fileAttributes.header);
      final thumbnailDecryptionHeader = CryptoUtil.bin2base64(
        encryptedThumbnailData.header!,
      );
      final encryptedMetadata = CryptoUtil.bin2base64(
        encryptedMetadataResult.encryptedData!,
      );
      final metadataDecryptionHeader = CryptoUtil.bin2base64(
        encryptedMetadataResult.header!,
      );
      if (SyncService.instance.shouldStopSync()) {
        throw SyncStopRequestedError();
      }
      final stillLocked = await _uploadLocks.isLocked(
        lockKey,
        _processType.toString(),
      );
      if (!stillLocked) {
        _logger.warning('file ${file.tag} report paused is missing');
        throw LockFreedError();
      }

      final pubMetadata = preparedMetadata.publicMetadata;
      EnteFile remoteFile;
      if (isUpdatedFile) {
        // Verify that the encrypted file can be decrypted before uploading
        // For updates, we need to verify with the existing file key
        await CryptoUtil.decryptVerify(
          encryptedFilePath,
          fileDecryptionHeader,
          file.encryptedKey!,
          file.keyDecryptionNonce!,
          CollectionsService.instance.getCollectionKey(collectionID),
          chunkLimit: 1, // Verify at least first chunk
        );
        remoteFile = await _updateFile(
          file,
          fileObjectKey,
          fileDecryptionHeader,
          encFileSize,
          thumbnailObjectKey,
          thumbnailDecryptionHeader,
          encThumbSize,
          encryptedMetadata,
          metadataDecryptionHeader,
        );
        // Update across all collections
        await FilesDB.instance.updateUploadedFileAcrossCollections(remoteFile);
        // _updateFile does not carry public magic metadata, so derived values
        // (width/height, mediaType, exif, camera) that change when the file is
        // edited would stay stale. Refresh them here. updatePublicMagicMetadata
        // merges into the existing pub mmd, preserving user-editable keys
        // (editedTime/editedName/caption).
        if (pubMetadata.isNotEmpty) {
          try {
            await FileMagicService.instance.updatePublicMagicMetadata([
              remoteFile,
            ], pubMetadata);
          } catch (e, s) {
            _logger.warning(
              "Failed to refresh public metadata on re-upload of ${file.tag}",
              e,
              s,
            );
          }
        }
      } else {
        final encryptedFileKeyData = CryptoUtil.encryptSync(
          fileAttributes.key,
          CollectionsService.instance.getCollectionKey(collectionID),
        );
        final encryptedKey = CryptoUtil.bin2base64(
          encryptedFileKeyData.encryptedData!,
        );
        final keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedFileKeyData.nonce!,
        );
        PreparedPublicMetadata? preparedPublicMetadata;
        if (pubMetadata.isNotEmpty) {
          preparedPublicMetadata = await preparePublicMetadata(
            file,
            pubMetadata,
            fileAttributes.key,
          );
        }
        await CryptoUtil.decryptVerify(
          encryptedFilePath,
          fileDecryptionHeader,
          encryptedKey,
          keyDecryptionNonce,
          CollectionsService.instance.getCollectionKey(collectionID),
          chunkLimit: 1, // Verify at least first chunk
        );

        remoteFile = await _uploadFile(
          file,
          collectionID,
          encryptedKey,
          keyDecryptionNonce,
          fileAttributes,
          fileObjectKey,
          fileDecryptionHeader,
          encFileSize,
          thumbnailObjectKey,
          thumbnailDecryptionHeader,
          encThumbSize,
          encryptedMetadata,
          metadataDecryptionHeader,
          pubMetadata: preparedPublicMetadata?.request,
        );
        if (preparedPublicMetadata != null) {
          remoteFile
            ..pubMmdEncodedJson = preparedPublicMetadata.encodedJson
            ..pubMmdVersion = preparedPublicMetadata.version
            ..pubMagicMetadata = preparedPublicMetadata.decodedMetadata;
        }
        if (mediaUploadData.isDeleted) {
          _logger.info("File found to be deleted");
          remoteFile.localID = null;
        }
        await FilesDB.instance.update(remoteFile);
      }
      await UploadLocksDB.instance.deleteMultipartTrack(lockKey);

      Bus.instance.fire(
        LocalPhotosUpdatedEvent([remoteFile], source: "uploadCompleted"),
      );
      _logger.info("File upload complete for " + remoteFile.toString());
      uploadCompleted = true;
      Bus.instance.fire(FileUploadedEvent(remoteFile));
      return remoteFile;
    } catch (e, s) {
      if (!(e is NoActiveSubscriptionError ||
          e is StorageLimitExceededError ||
          e is WiFiUnavailableError ||
          e is SilentlyCancelUploadsError ||
          e is InvalidFileError ||
          e is FileTooLargeForPlanError)) {
        _logger.severe("File upload failed for " + file.toString(), e, s);
      }
      if (e is InvalidFileError) {
        _logger.severe("File upload ignored for " + file.toString(), e);
        await _onInvalidFileError(file, e);
      }
      if ((e is StorageLimitExceededError ||
          e is FileTooLargeForPlanError ||
          e is NoActiveSubscriptionError ||
          e is InvalidFileError)) {
        // file upload can not be retried in such cases without user intervention
        uploadHardFailure = true;
      }
      if ((isMultipartUpload || hasExistingMultiPart) &&
          isPutOrMultiPartError(e)) {
        await UploadLocksDB.instance.deleteMultipartTrack(lockKey);
      }
      rethrow;
    } finally {
      await _onUploadDone(
        mediaUploadData,
        uploadCompleted,
        uploadHardFailure,
        file,
        encryptedFilePath,
        encryptedThumbnailPath,
        lockKey: lockKey,
        isMultiPartUpload: isMultipartUpload,
      );
    }
  }

  bool isPutOrMultiPartError(Object e) {
    if (e is MultiPartFileMissingError ||
        e is MultiPartError ||
        e is BadMD5DigestError) {
      return true;
    }
    if (e is DioException) {
      return e.requestOptions.path.contains("/files") ||
          e.requestOptions.path.contains("/files/update");
    }
    return false;
  }

  /*
  _mapToExistingUpload links the fileToUpload with the existing uploaded
  files. if the link is successful, it returns true otherwise false.
  When false, we should go ahead and re-upload or update the file.
  It performs following checks:
    a) Target file with same localID and destination collection exists. Delete the
     fileToUpload entry. If target file is sandbox file, then we skip localID match
     check.
    b) Uploaded file in any collection but with missing localID.
     Update the localID for uploadedFile and delete the fileToUpload entry
    c) A uploaded file exist with same localID but in a different collection.
    Add a symlink in the destination collection and update the fileToUpload.
    If target file is sandbox file, then we skip localID match
     check.
    d) File already exists but different localID. Re-upload
    In case the existing files already have local identifier, which is
    different from the {fileToUpload}, then most probably device has
    duplicate files.
  */
  Future<Tuple2<bool, EnteFile>> _mapToExistingUploadWithSameHash(
    MediaUploadData mediaUploadData,
    EnteFile fileToUpload,
    int toCollectionID,
  ) async {
    if (fileToUpload.uploadedFileID != null) {
      // ideally this should never happen, but because the code below this case
      // can do unexpected mapping, we are adding this additional check
      _logger.severe('Critical: file is already uploaded, skipped mapping');
      return Tuple2(false, fileToUpload);
    }
    final bool isSandBoxFile = fileToUpload.isSharedMediaToAppSandbox;

    final List<EnteFile> existingUploadedFiles = await FilesDB.instance
        .getUploadedFilesWithHashes(
          mediaUploadData.hashData,
          fileToUpload.fileType,
          Configuration.instance.getUserID()!,
        );
    if (existingUploadedFiles.isEmpty) {
      // continueUploading this file
      return Tuple2(false, fileToUpload);
    }

    // case a
    final EnteFile? sameLocalSameCollection = existingUploadedFiles
        .firstWhereOrNull(
          (e) =>
              e.collectionID == toCollectionID &&
              (e.localID == fileToUpload.localID || isSandBoxFile),
        );
    if (sameLocalSameCollection != null) {
      _logger.info(
        "sameLocalSameCollection: toUpload  ${fileToUpload.tag} "
        "existing: ${sameLocalSameCollection.tag} $isSandBoxFile",
      );
      // should delete the fileToUploadEntry
      if (fileToUpload.generatedID != null) {
        await FilesDB.instance.deleteByGeneratedID(fileToUpload.generatedID!);
      }

      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          [fileToUpload],
          type: EventType.deletedFromEverywhere,
          source: "sameLocalSameCollection", //
        ),
      );
      return Tuple2(true, sameLocalSameCollection);
    }

    // case b
    final EnteFile? fileMissingLocal = existingUploadedFiles.firstWhereOrNull(
      (e) => e.localID == null,
    );
    if (fileMissingLocal != null) {
      // update the local id of the existing file and delete the fileToUpload
      // entry
      _logger.info(
        "fileMissingLocal: \n toUpload  ${fileToUpload.tag} "
        "\n existing: ${fileMissingLocal.tag}",
      );
      fileMissingLocal.localID = fileToUpload.localID;
      // set localID for the given uploadedID across collections
      await FilesDB.instance.updateLocalIDForUploaded(
        fileMissingLocal.uploadedFileID!,
        fileToUpload.localID!,
      );
      // For files selected from device, during collaborative upload, we don't
      // insert entries in the FilesDB. So, we don't need to delete the entry
      if (fileToUpload.generatedID != null) {
        await FilesDB.instance.deleteByGeneratedID(fileToUpload.generatedID!);
      }
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          [fileToUpload],
          source: "fileMissingLocal",
          type: EventType.deletedFromEverywhere, //
        ),
      );
      return Tuple2(true, fileMissingLocal);
    }

    // case c
    final EnteFile? fileExistsButDifferentCollection = existingUploadedFiles
        .firstWhereOrNull(
          (e) =>
              e.collectionID != toCollectionID &&
              (e.localID == fileToUpload.localID || isSandBoxFile),
        );
    if (fileExistsButDifferentCollection != null) {
      _logger.info(
        "fileExistsButDifferentCollection: toUpload  ${fileToUpload.tag} "
        "existing: ${fileExistsButDifferentCollection.tag} $isSandBoxFile",
      );
      final linkedFile = await CollectionsService.instance
          .linkLocalFileToExistingUploadedFileInAnotherCollection(
            toCollectionID,
            localFileToUpload: fileToUpload,
            existingUploadedFile: fileExistsButDifferentCollection,
          );
      return Tuple2(true, linkedFile);
    }
    final Set<String> matchLocalIDs = existingUploadedFiles
        .where((e) => e.localID != null)
        .map((e) => e.localID!)
        .toSet();
    _logger.info(
      "Found hashMatch but probably with diff localIDs "
      "$matchLocalIDs",
    );
    // case d
    return Tuple2(false, fileToUpload);
  }

  Future<void> _onUploadDone(
    MediaUploadData? mediaUploadData,
    bool uploadCompleted,
    bool uploadHardFailure,
    EnteFile file,
    String encryptedFilePath,
    String encryptedThumbnailPath, {
    required String lockKey,
    bool isMultiPartUpload = false,
  }) async {
    if (mediaUploadData != null) {
      // delete the file from app's internal cache if it was copied to app
      // for upload. On iOS, only remove the file from photo_manager/app cache
      // when upload is either completed or cannot be retried automatically.
      // Shared Media should only be cleared when the upload
      // succeeds.
      // A Live Photo source is an app-created archive, and each retry rebuilds
      // it, so it must be removed after every attempt.
      if ((Platform.isIOS &&
              (file.fileType == FileType.livePhoto ||
                  uploadCompleted ||
                  uploadHardFailure)) ||
          (uploadCompleted && file.isSharedMediaToAppSandbox)) {
        await deleteFileSystemEntityIfPresent(mediaUploadData.sourceFile);
      }
    }
    if (File(encryptedFilePath).existsSync()) {
      if (isMultiPartUpload && !uploadCompleted) {
        _logger.info(
          "skip delete for multipart encrypted file $encryptedFilePath",
        );
      } else {
        await File(encryptedFilePath).delete();
      }
    }
    if (File(encryptedThumbnailPath).existsSync()) {
      await File(encryptedThumbnailPath).delete();
    }
    await _uploadLocks.releaseLock(lockKey, _processType.toString());
  }

  /*
  _checkIfWithinStorageLimit verifies if the file size for encryption and upload
   is within the storage limit. It throws StorageLimitExceededError if the limit
    is exceeded. This check is best effort and may not be completely accurate
    due to UserDetail cache. It prevents infinite loops when clients attempt to
    upload files that exceed the server's storage limit + buffer.
    Note: Local storageBuffer is 20MB, server storageBuffer is 50MB, and an
    additional 30MB is reserved for thumbnails and encryption overhead.
   */
  Future<void> _checkIfWithinStorageLimit(File fileToBeUploaded) async {
    try {
      final UserDetails? userDetails = UserService.instance
          .getCachedUserDetails();
      if (userDetails == null) {
        return;
      }
      // add k20MBStorageBuffer to the free storage
      final num freeStorage = userDetails.getFreeStorage() + k20MBStorageBuffer;
      final int fileSize = await fileToBeUploaded.length();
      if (fileSize > freeStorage) {
        _logger.warning(
          'Storage limit exceeded fileSize $fileSize and '
          'freeStorage $freeStorage',
        );
        throw StorageLimitExceededError();
      }
      final estimatedEncryptedSize = CryptoUtil.estimateEncryptedSize(fileSize);
      if (estimatedEncryptedSize > kMaxFileSize10Gib) {
        _logger.warning(
          'Encrypted file size exceeds 10GiB sourceSize $fileSize '
          'estimatedEncryptedSize $estimatedEncryptedSize',
        );
        throw InvalidFileError(
          'encrypted file size above 10GiB',
          InvalidReason.tooLargeFile,
        );
      }
    } catch (e) {
      if (e is StorageLimitExceededError || e is InvalidFileError) {
        rethrow;
      } else {
        _logger.severe('Error checking storage limit', e);
      }
    }
  }

  Future _onInvalidFileError(EnteFile file, InvalidFileError e) async {
    try {
      final bool canIgnoreFile =
          file.localID != null &&
          file.deviceFolder != null &&
          file.title != null &&
          !file.isSharedMediaToAppSandbox;
      // If the file is not uploaded yet and either it can not be ignored or the
      // err is related to live photo media, delete the local entry
      final bool deleteEntry =
          !file.isUploaded && (!canIgnoreFile || e.reason.isLivePhotoErr);

      if (e.reason != InvalidReason.thumbnailMissing || !canIgnoreFile) {
        _logger.severe(
          "Invalid file, localDelete: $deleteEntry, ignored: $canIgnoreFile",
          e,
        );
      }
      if (deleteEntry) {
        await FilesDB.instance.deleteLocalFile(file);
      }
      if (canIgnoreFile) {
        await LocalSyncService.instance.ignoreUpload(file, e);
      }
    } catch (e, s) {
      _logger.severe("Failed to handle invalid file error", e, s);
    }
  }

  Future<EnteFile> _uploadFile(
    EnteFile file,
    int collectionID,
    String encryptedKey,
    String keyDecryptionNonce,
    FileEncryptResult fileAttributes,
    String fileObjectKey,
    String fileDecryptionHeader,
    int fileSize,
    String thumbnailObjectKey,
    String thumbnailDecryptionHeader,
    int thumbnailSize,
    String encryptedMetadata,
    String metadataDecryptionHeader, {
    MetadataRequest? pubMetadata,
    int attempt = 1,
  }) async {
    try {
      final data = await _gateway.createFile(
        collectionID: collectionID,
        encryptedKey: encryptedKey,
        keyDecryptionNonce: keyDecryptionNonce,
        fileObjectKey: fileObjectKey,
        fileDecryptionHeader: fileDecryptionHeader,
        fileSize: fileSize,
        thumbnailObjectKey: thumbnailObjectKey,
        thumbnailDecryptionHeader: thumbnailDecryptionHeader,
        thumbnailSize: thumbnailSize,
        encryptedMetadata: encryptedMetadata,
        metadataDecryptionHeader: metadataDecryptionHeader,
        pubMagicMetadata: pubMetadata?.toJson(),
      );
      file.uploadedFileID = data["id"];
      file.collectionID = collectionID;
      file.updationTime = data["updationTime"];
      file.ownerID = data["ownerID"];
      file.encryptedKey = encryptedKey;
      file.keyDecryptionNonce = keyDecryptionNonce;
      file.fileDecryptionHeader = fileDecryptionHeader;
      file.thumbnailDecryptionHeader = thumbnailDecryptionHeader;
      file.metadataDecryptionHeader = metadataDecryptionHeader;
      return file;
    } on DioException catch (e) {
      final int statusCode = e.response?.statusCode ?? -1;
      if (statusCode == 413) {
        throw FileTooLargeForPlanError();
      } else if (statusCode == 426) {
        _onStorageLimitExceeded();
      } else if (attempt < kMaximumUploadAttempts && statusCode == -1) {
        // retry when DioException contains no response/status code
        _logger.info(
          "Upload file (${file.tag}) failed, will retry in 3 seconds",
        );
        await Future.delayed(const Duration(seconds: 3));
        return _uploadFile(
          file,
          collectionID,
          encryptedKey,
          keyDecryptionNonce,
          fileAttributes,
          fileObjectKey,
          fileDecryptionHeader,
          fileSize,
          thumbnailObjectKey,
          thumbnailDecryptionHeader,
          thumbnailSize,
          encryptedMetadata,
          metadataDecryptionHeader,
          attempt: attempt + 1,
          pubMetadata: pubMetadata,
        );
      } else {
        _logger.severe("Failed to upload file ${file.tag}", e);
      }
      rethrow;
    }
  }

  Future<EnteFile> _updateFile(
    EnteFile file,
    String fileObjectKey,
    String fileDecryptionHeader,
    int fileSize,
    String thumbnailObjectKey,
    String thumbnailDecryptionHeader,
    int thumbnailSize,
    String encryptedMetadata,
    String metadataDecryptionHeader, {
    int attempt = 1,
  }) async {
    try {
      final data = await _gateway.updateFile(
        fileID: file.uploadedFileID!,
        fileObjectKey: fileObjectKey,
        fileDecryptionHeader: fileDecryptionHeader,
        fileSize: fileSize,
        thumbnailObjectKey: thumbnailObjectKey,
        thumbnailDecryptionHeader: thumbnailDecryptionHeader,
        thumbnailSize: thumbnailSize,
        encryptedMetadata: encryptedMetadata,
        metadataDecryptionHeader: metadataDecryptionHeader,
      );
      file.uploadedFileID = data["id"];
      file.updationTime = data["updationTime"];
      file.fileDecryptionHeader = fileDecryptionHeader;
      file.thumbnailDecryptionHeader = thumbnailDecryptionHeader;
      file.metadataDecryptionHeader = metadataDecryptionHeader;
      return file;
    } on DioException catch (e) {
      final int statusCode = e.response?.statusCode ?? -1;
      if (statusCode == 426) {
        _onStorageLimitExceeded();
      } else if (attempt < kMaximumUploadAttempts && statusCode == -1) {
        _logger.info(
          "Update file (${file.tag}) failed, will retry in 3 seconds",
        );
        await Future.delayed(const Duration(seconds: 3));
        return _updateFile(
          file,
          fileObjectKey,
          fileDecryptionHeader,
          fileSize,
          thumbnailObjectKey,
          thumbnailDecryptionHeader,
          thumbnailSize,
          encryptedMetadata,
          metadataDecryptionHeader,
          attempt: attempt + 1,
        );
      } else {
        _logger.severe("Failed to update file ${file.tag}", e);
      }
      rethrow;
    }
  }

  Future<UploadURL> _getUploadURL({
    required int contentLength,
    required String contentMd5,
  }) async {
    final uploadURL = await _requestChecksumProtectedUploadURL(
      contentLength: contentLength,
      contentMd5: contentMd5,
    );
    return _registerUploadURLUsage(uploadURL);
  }

  Future<UploadURL> _requestChecksumProtectedUploadURL({
    required int contentLength,
    required String contentMd5,
  }) async {
    if (contentMd5.isEmpty) {
      throw StateError("Missing MD5 for checksum-protected upload URL");
    }
    try {
      return await _gateway.getUploadUrl(
        contentLength: contentLength,
        contentMd5: contentMd5,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        final error = NoActiveSubscriptionError();
        clearQueue(error);
        throw error;
      } else if (e.response?.statusCode == 426) {
        final error = StorageLimitExceededError();
        clearQueue(error);
        throw error;
      }
      rethrow;
    }
  }

  UploadURL _registerUploadURLUsage(UploadURL uploadURL) {
    // Atomic check-and-set to prevent race conditions in parallel uploads
    final now = DateTime.now();
    final existingTimestamp = _usedUploadURLs.putIfAbsent(
      uploadURL.url,
      () => now,
    );

    if (existingTimestamp != now) {
      throw DuplicateUploadURLError(
        firstUsedAt: existingTimestamp,
        duplicateUsedAt: now,
      );
    }
    // Clean up old entries to prevent memory growth (only when > 5000 entries)
    if (_usedUploadURLs.length > 5000) {
      final oneHourAgo = now.subtract(const Duration(hours: 1));
      _usedUploadURLs.removeWhere((key, value) => value.isBefore(oneHourAgo));
      _logger.info(
        "Cleaned up used upload URLs, remaining: ${_usedUploadURLs.length}",
      );
    }

    return uploadURL;
  }

  bool get _shouldUseCFUploadProxy =>
      !flagService.disableCFWorker &&
      (localSettings.cfUploadProxyEnabled ??
          flagService.cloudflareUploadWorker) &&
      endpointConfig.isProduction;

  void _onStorageLimitExceeded() {
    clearQueue(StorageLimitExceededError());
    throw StorageLimitExceededError();
  }

  Future<String> _putFile(
    UploadURL uploadURL,
    File file,
    int fileSize, {
    required String contentMd5,
    int attempt = 1,
  }) async {
    if (contentMd5.isEmpty) {
      throw StateError("Missing MD5 for checksum-protected upload");
    }
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final fileName = basename(file.path);
    int bytesSent = 0;
    try {
      final useUploadProxy = _shouldUseCFUploadProxy;
      final Map<String, dynamic> headers = {
        Headers.contentLengthHeader: fileSize,
      };
      if (useUploadProxy) {
        headers["UPLOAD-URL"] = uploadURL.url;
      }
      headers[useUploadProxy ? 'CONTENT-MD5' : 'Content-MD5'] = contentMd5;

      await _dio.put(
        useUploadProxy ? "$kUploadProxyEndpoint/file-upload" : uploadURL.url,
        data: file.openRead(),
        options: Options(headers: headers),
        onSendProgress: (sent, total) {
          bytesSent = sent;
        },
      );
      _logger.info(
        "Uploaded object $fileName of size: ${formatBytes(fileSize)} at speed: ${(fileSize / (DateTime.now().millisecondsSinceEpoch - startTime)).toStringAsFixed(2)} KB/s",
      );

      return uploadURL.objectKey;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400 &&
              e.response?.data.toString().contains('BadDigest') == true ||
          e.response?.data.toString().contains('InvalidDigest') == true) {
        final String recomputedMd5 = await computeMd5(file.path);
        throw BadMD5DigestError(
          "Failed ${e.response?.data}, sent: $contentMd5, computed: $recomputedMd5",
        );
      } else if (e.message?.startsWith("HttpException: Content size") ??
          false) {
        rethrow;
      } else if (attempt < kMaximumUploadAttempts) {
        _logger.info(
          "Upload failed for $fileName after sending ${formatBytes(bytesSent)} of ${formatBytes(fileSize)}, retrying attempt ${attempt + 1}",
        );
        final newUploadURL = await _getUploadURL(
          contentLength: fileSize,
          contentMd5: contentMd5,
        );
        return _putFile(
          newUploadURL,
          file,
          fileSize,
          contentMd5: contentMd5,
          attempt: attempt + 1,
        );
      } else {
        _logger.info(
          "Failed to upload file ${basename(file.path)} after $attempt attempts",
          e,
        );
        rethrow;
      }
    }
  }

  // _pollBackgroundUploadStatus polls the background uploads to check if the
  // upload is completed or failed.
  Future<void> _pollBackgroundUploadStatus() async {
    final blockedUploads = _queue.backgroundItems;
    for (final upload in blockedUploads) {
      final file = upload.file;
      final isStillLocked = await _uploadLocks.isLocked(
        file.localID!,
        ProcessType.background.toString(),
      );
      if (!isStillLocked) {
        final dbFile = await FilesDB.instance.getFile(upload.file.generatedID!);
        if (dbFile?.uploadedFileID != null) {
          _logger.info("Background upload success detected ${upload.file.tag}");
          _queue.complete(upload, dbFile!);
        } else {
          _logger.info("Background upload failure detected ${upload.file.tag}");
          // The upload status is marked as in background, but the file is not locked
          // by the background process. Release any lock taken by the foreground process
          // and complete the completer with error.
          await _uploadLocks.releaseLock(
            file.localID!,
            ProcessType.foreground.toString(),
          );
          _queue.fail(upload, SilentlyCancelUploadsError());
        }
      }
    }
    Future.delayed(kBlockedUploadsPollFrequency, () async {
      await _pollBackgroundUploadStatus();
    });
  }
}

enum ProcessType { background, foreground }
