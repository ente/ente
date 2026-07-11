import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/files_updated_event.dart';
import 'package:photos/events/force_reload_home_gallery_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/gateways/collections/models/metadata.dart";
import "package:photos/gateways/files/file_magic_gateway.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import 'package:photos/services/sync/remote_sync_service.dart';
import "package:photos/utils/file_key.dart";
import "package:synchronized/synchronized.dart";

class _PreparedMagicMetadataUpdate<T> {
  const _PreparedMagicMetadataUpdate({
    required this.file,
    required this.encodedJson,
    required this.decodedMetadata,
    required this.nextVersion,
    required this.request,
  });

  final EnteFile file;
  final String encodedJson;
  final T decodedMetadata;
  final int nextVersion;
  final UpdateMagicMetadataRequest request;
}

class FileMagicService {
  final _logger = Logger("FileMagicService");
  final _privateMetadataLock = Lock();
  final _publicMetadataLock = Lock();
  late FilesDB _filesDB;

  FileMagicGateway get _gateway => fileMagicGateway;

  FileMagicService._privateConstructor() {
    _filesDB = FilesDB.instance;
  }

  static final FileMagicService instance =
      FileMagicService._privateConstructor();

  Future<void> changeVisibility(List<EnteFile> files, int visibility) async {
    final Map<String, dynamic> update = {magicKeyVisibility: visibility};
    await _updateMagicData(files, update);
    if (visibility == visibleVisibility) {
      // Force reload home gallery to pull in the now unarchived files
      Bus.instance.fire(ForceReloadHomeGalleryEvent("unarchivedFiles"));
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          files,
          type: EventType.unarchived,
          source: "vizChange",
        ),
      );
    } else {
      Bus.instance.fire(
        LocalPhotosUpdatedEvent(
          files,
          type: EventType.archived,
          source: "vizChange",
        ),
      );
    }
  }

  Future<void> updatePublicMagicMetadata(
    List<EnteFile> files,
    Map<String, dynamic>? newMetadataUpdate, {
    Map<int, Map<String, dynamic>>? metadataUpdateMap,
  }) {
    return _publicMetadataLock.synchronized(
      () => _updatePublicMagicMetadata(
        files,
        newMetadataUpdate,
        metadataUpdateMap: metadataUpdateMap,
      ),
    );
  }

  Future<void> _updatePublicMagicMetadata(
    List<EnteFile> files,
    Map<String, dynamic>? newMetadataUpdate, {
    Map<int, Map<String, dynamic>>? metadataUpdateMap,
  }) async {
    final updates = <_PreparedMagicMetadataUpdate<PubMagicMetadata>>[];
    final int ownerID = Configuration.instance.getUserID()!;
    try {
      for (final file in files) {
        _assertCanUpdate(file, ownerID);
        final newUpdates = metadataUpdateMap != null
            ? metadataUpdateMap[file.uploadedFileID]
            : newMetadataUpdate;
        assert(
          newUpdates != null && newUpdates.isNotEmpty,
          "can not apply empty updates",
        );
        final int currentVersion = file.pubMmdVersion == 0
            ? 1
            : file.pubMmdVersion;
        updates.add(
          await _prepareUpdate(
            file: file,
            encodedJson: file.pubMmdEncodedJson,
            currentVersion: currentVersion,
            newMetadata: newUpdates!,
            decode: PubMagicMetadata.fromJson,
          ),
        );
      }

      await _gateway.updatePublicMagicMetadata(
        updates.map((update) => update.request).toList(),
      );
      // Remote has accepted these versions; commit the same state locally.
      for (final update in updates) {
        update.file
          ..pubMmdEncodedJson = update.encodedJson
          ..pubMagicMetadata = update.decodedMetadata
          ..pubMmdVersion = update.nextVersion;
      }
      // update the state of the selected file. Same file in other collection
      // should be eventually synced after remote sync has completed
      await _filesDB.insertMultiple(files);
      RemoteSyncService.instance.sync(silently: true).ignore();
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 409) {
        RemoteSyncService.instance.sync(silently: true).ignore();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to sync magic metadata", e, s);
      rethrow;
    }
  }

  Future<void> _updateMagicData(
    List<EnteFile> files,
    Map<String, dynamic> newMetadataUpdate,
  ) {
    return _privateMetadataLock.synchronized(
      () => _updatePrivateMagicMetadata(files, newMetadataUpdate),
    );
  }

  Future<void> _updatePrivateMagicMetadata(
    List<EnteFile> files,
    Map<String, dynamic> newMetadataUpdate,
  ) async {
    final int ownerID = Configuration.instance.getUserID()!;
    final batchedFiles = files.chunks(batchSize);
    try {
      for (final batch in batchedFiles) {
        final updates = <_PreparedMagicMetadataUpdate<MagicMetadata>>[];
        for (final file in batch) {
          _assertCanUpdate(file, ownerID);
          updates.add(
            await _prepareUpdate(
              file: file,
              encodedJson: file.mMdEncodedJson,
              currentVersion: file.mMdVersion,
              newMetadata: newMetadataUpdate,
              decode: MagicMetadata.fromJson,
            ),
          );
        }

        await _gateway.updateMagicMetadata(
          updates.map((update) => update.request).toList(),
        );
        // Each batch is committed locally only after its remote transaction.
        for (final update in updates) {
          update.file
            ..mMdEncodedJson = update.encodedJson
            ..magicMetadata = update.decodedMetadata
            ..mMdVersion = update.nextVersion;
        }
        await _filesDB.insertMultiple(batch);
      }

      // update the state of the selected file. Same file in other collection
      // should be eventually synced after remote sync has completed
      RemoteSyncService.instance.sync(silently: true).ignore();
    } on DioException catch (e) {
      if (e.response != null && e.response!.statusCode == 409) {
        RemoteSyncService.instance.sync(silently: true).ignore();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to sync magic metadata", e, s);
      rethrow;
    }
  }

  void _assertCanUpdate(EnteFile file, int ownerID) {
    if (file.uploadedFileID == null) {
      throw AssertionError("operation is only supported on backed up files");
    } else if (file.ownerID != ownerID) {
      throw AssertionError("cannot modify memories not owned by you");
    }
  }

  Future<_PreparedMagicMetadataUpdate<T>> _prepareUpdate<T>({
    required EnteFile file,
    required String? encodedJson,
    required int currentVersion,
    required Map<String, dynamic> newMetadata,
    required T Function(dynamic json) decode,
  }) async {
    final Map<String, dynamic> jsonToUpdate = jsonDecode(encodedJson ?? '{}');
    jsonToUpdate.addAll(newMetadata);
    final updatedJson = jsonEncode(jsonToUpdate);
    final encryptedMMd = await CryptoUtil.encryptChaCha(
      utf8.encode(updatedJson),
      getFileKey(file),
    );
    return _PreparedMagicMetadataUpdate(
      file: file,
      encodedJson: updatedJson,
      decodedMetadata: decode(jsonToUpdate),
      nextVersion: currentVersion + 1,
      request: UpdateMagicMetadataRequest(
        id: file.uploadedFileID!,
        magicMetadata: MetadataRequest(
          version: currentVersion,
          count: jsonToUpdate.length,
          data: CryptoUtil.bin2base64(encryptedMMd.encryptedData!),
          header: CryptoUtil.bin2base64(encryptedMMd.header!),
        ),
      ),
    );
  }
}
