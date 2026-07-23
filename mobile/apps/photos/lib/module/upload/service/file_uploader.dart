import 'dart:async';
import 'dart:convert';
import 'dart:io';

import "package:dio/dio.dart";
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
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
import "package:photos/gateways/files/file_upload_gateway.dart";
import "package:photos/main.dart" show isProcessBg, kLastBGTaskHeartBeatTime;
import "package:photos/models/backup/backup_item.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/models/user_details.dart";
import "package:photos/module/metadata/exif.dart";
import 'package:photos/module/upload/model/media_upload_data.dart';
import "package:photos/module/upload/service/existing_upload_resolver.dart";
import "package:photos/module/upload/service/multipart.dart";
import 'package:photos/module/upload/service/upload_artifact_lifecycle.dart';
import 'package:photos/module/upload/service/upload_queue.dart';
import 'package:photos/module/upload/service/upload_transport.dart';
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
import "package:uuid/uuid.dart";

/// Coordinates encryption, transfer, persistence, and retries for file uploads.
class FileUploader {
  static const kMaximumConcurrentUploads = 4;
  static const kMaximumConcurrentVideoUploads = 2;
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
  final _existingUploadResolver = ExistingUploadResolver.forApp();
  final kSafeBufferForLockExpiry = const Duration(hours: 4).inMicroseconds;
  final kBGTaskDeathTimeout = const Duration(seconds: 5).inMicroseconds;
  Map<String, BackupItem> get allBackups => _queue.backupItems;

  /// Returns true if any file uploads are currently in progress
  bool get isUploading => _queue.isUploading;

  /// Returns true if an upload is queued, running, or waiting in background.
  bool get hasPendingUploads => _queue.hasPendingUploads;
  late ProcessType _processType;
  late SharedPreferences _prefs;
  bool _hasStartedBackgroundUploadPolling = false;

  late MultiPartUploader _multiPartUploader;
  UploadTransport? _uploadTransport;
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
    _uploadTransport ??= UploadTransport(
      _dio,
      _gateway,
      shouldUseUploadProxy: () =>
          !flagService.disableCFWorker &&
          (localSettings.cfUploadProxyEnabled ??
              flagService.cloudflareUploadWorker) &&
          endpointConfig.isProduction,
      clearQueue: clearQueue,
    );
    _multiPartUploader = MultiPartUploader(
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
            final deletedGeneratedIDs = event.updatedFiles
                .map((file) => file.generatedID)
                .toSet();
            removeFromQueueWhere(
              (file) => deletedGeneratedIDs.contains(file.generatedID),
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
    } catch (e, s) {
      final lockInfo = await _uploadLocks.getLockData(lockKey);
      _logger.warning(
        "Upload lock acquisition failed for ${file.tag}: "
        "targetCollectionID=$collectionID, requestOwner=$_processType, "
        "forcedUpload=$forcedUpload, lock=$lockInfo",
        e,
        s,
      );
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
        .getEncryptedFileName(lockKey, mediaUploadData.fileHash, collectionID);
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
              mediaUploadData.fileHash,
              collectionID,
              existingMultipartEncFileName,
            )
          : null;
      if (isUpdatedFile) {
        key = getFileKey(file);
      } else {
        key = multiPartFileEncResult?.key;
        final mappedFile = await _existingUploadResolver.resolve(
          fileHash: mediaUploadData.fileHash,
          fileToUpload: file,
          targetCollectionID: collectionID,
          ownerID: Configuration.instance.getUserID(),
        );
        if (mappedFile != null) {
          debugPrint(
            "File success mapped to existing uploaded ${file.toString()}",
          );
          // treat as completed so _onUploadDone clears the source export
          uploadCompleted = true;
          return mappedFile;
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
        final singlePartFileMd5 = fileMd5 ??= await computeMd5(
          encryptedFilePath,
        );
        thumbnailObjectKey = await _uploadTransport!.uploadSinglePart(
          encryptedThumbnailFile,
          encThumbSize,
          contentMd5: thumbnailMd5,
        );
        fileObjectKey = await _uploadTransport!.uploadSinglePart(
          encryptedFile,
          encFileSize,
          contentMd5: singlePartFileMd5,
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
            mediaUploadData.fileHash,
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
            mediaUploadData.fileHash,
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
        thumbnailObjectKey = await _uploadTransport!.uploadSinglePart(
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
      final commitData = UploadCommitData(
        fileObjectKey: fileObjectKey,
        fileDecryptionHeader: fileDecryptionHeader,
        fileSize: encFileSize,
        thumbnailObjectKey: thumbnailObjectKey,
        thumbnailDecryptionHeader: thumbnailDecryptionHeader,
        thumbnailSize: encThumbSize,
        encryptedMetadata: encryptedMetadata,
        metadataDecryptionHeader: metadataDecryptionHeader,
      );
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
        remoteFile = await _uploadTransport!.updateFile(
          file: file,
          data: commitData,
        );
        // Update across all collections
        await FilesDB.instance.updateUploadedFileAcrossCollections(remoteFile);
        // The update response does not carry public magic metadata, so derived values
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

        remoteFile = await _uploadTransport!.createFile(
          file: file,
          collectionID: collectionID,
          encryptedKey: encryptedKey,
          keyDecryptionNonce: keyDecryptionNonce,
          data: commitData,
          pubMagicMetadata: preparedPublicMetadata?.request.toJson(),
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

  // _pollBackgroundUploadStatus polls the background uploads to check if the
  // upload is completed or failed.
  Future<void> _pollBackgroundUploadStatus() async {
    final blockedUploads = _queue.backgroundItems;
    for (final upload in blockedUploads) {
      try {
        final file = upload.file;
        final isStillLocked = await _uploadLocks.isLocked(
          file.localID!,
          ProcessType.background.toString(),
        );
        if (!isStillLocked) {
          final dbFile = await FilesDB.instance.getFile(file.generatedID!);
          final persistedState =
              "targetCollectionID=${upload.collectionID}, "
              "backgroundLockPresent=false, "
              "persistedFile=${dbFile != null}, "
              "uploadedFileID=${dbFile?.uploadedFileID}, "
              "updationTime=${dbFile?.updationTime}, "
              "persistedCollectionID=${dbFile?.collectionID}";
          if (dbFile?.uploadedFileID != null) {
            _logger.info(
              "Background upload success detected ${file.tag}: "
              "$persistedState",
            );
            _queue.complete(upload, dbFile!);
          } else {
            _logger.warning(
              "Background upload failure detected ${file.tag}: "
              "$persistedState",
            );
            // The upload status is marked as in background, but the file is not locked
            // by the background process. Release any lock taken by the foreground process
            // and complete the completer with error.
            final releasedForegroundLocks = await _uploadLocks.releaseLock(
              file.localID!,
              ProcessType.foreground.toString(),
            );
            if (releasedForegroundLocks > 0) {
              _logger.warning(
                "Released a foreground upload lock while reconciling "
                "${file.tag}: targetCollectionID=${upload.collectionID}",
              );
            }
            _queue.fail(upload, SilentlyCancelUploadsError());
          }
        }
      } catch (e, s) {
        _logger.severe(
          "Background upload status polling stopped while checking "
          "${upload.file.tag}: targetCollectionID=${upload.collectionID}",
          e,
          s,
        );
        rethrow;
      }
    }
    Future.delayed(kBlockedUploadsPollFrequency, () async {
      await _pollBackgroundUploadStatus();
    });
  }
}

enum ProcessType { background, foreground }
