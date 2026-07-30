import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import "package:ente_events/event_bus.dart";
import "package:ente_events/models/signed_in_event.dart";
import 'package:ente_network/network.dart';
import "package:locker/events/collections_updated_event.dart";
import "package:locker/events/user_details_refresh_event.dart";
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/collections/models/collection_file_item.dart';
import "package:locker/services/configuration.dart";
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/db/trash_table.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:locker/services/trash/models/trash_file.dart';
import "package:locker/utils/crypto_helper.dart";
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TrashService {
  TrashService._privateConstructor();
  static final TrashService instance = TrashService._privateConstructor();

  static const kLastTrashSyncTime = "last_trash_sync_time_locker_db";
  final _logger = Logger("TrashService");
  late SharedPreferences _prefs;
  late Dio _enteDio;
  late LockerDB _db;

  Future<void> init(SharedPreferences preferences) async {
    _prefs = preferences;
    _enteDio = Network.instance.enteDio;
    _db = LockerDB.instance;

    Bus.instance.on<SignedInEvent>().listen((event) async {
      _logger.info("User signed in, starting initial trash sync.");
      unawaited(syncTrash());
    });

    if (Configuration.instance.hasConfiguredAccount()) {
      unawaited(syncTrash());
    }
  }

  Future<void> syncTrash() async {
    final lastSyncTime = _getSyncTime();
    _logger.fine('sync trash sinceTime : $lastSyncTime');
    final diff = await getTrashFilesDiff(lastSyncTime);
    if (diff.trashedFiles.isNotEmpty) {
      _logger.fine("inserting ${diff.trashedFiles.length} items in trash");
      await _db.insertTrashFiles(diff.trashedFiles);
    }
    if (diff.deletedUploadIDs.isNotEmpty) {
      _logger.fine("discard ${diff.deletedUploadIDs.length} deleted items");
      await _db.deleteTrashFiles(diff.deletedUploadIDs);
    }
    if (diff.restoredFiles.isNotEmpty) {
      _logger.fine("discard ${diff.restoredFiles.length} restored items");
      await _db.deleteTrashFiles(
        diff.restoredFiles.map((e) => e.uploadedFileID!).toList(),
      );
    }

    if (diff.lastSyncedTimeStamp != 0) {
      await _setSyncTime(diff.lastSyncedTimeStamp);
    }
    if (diff.hasMore) {
      return syncTrash();
    }
  }

  Future<List<TrashFile>> getTrashFiles() async {
    return await _db.getTrashFiles();
  }

  Future<bool> _setSyncTime(int time) async {
    return _prefs.setInt(kLastTrashSyncTime, time);
  }

  int _getSyncTime() {
    return _prefs.getInt(kLastTrashSyncTime) ?? 0;
  }

  Future<TrashDiff> getTrashFilesDiff(int sinceTime) async {
    try {
      final response = await _enteDio.get(
        "/trash/v2/diff",
        queryParameters: {"sinceTime": sinceTime},
      );
      final List<Collection> allCollections = await CollectionService.instance
          .getCollections(includeDeleted: true);
      final Map<int, Collection> collectionMap = {
        for (final collection in allCollections) collection.id: collection,
      };
      int latestUpdatedAtTime = 0;
      final trashedFiles = <TrashFile>[];
      final deletedUploadIDs = <int>[];
      final restoredFiles = <TrashFile>[];

      final diff = response.data["diff"] as List;
      final bool hasMore = response.data["hasMore"] as bool;
      final startTime = DateTime.now();
      for (final item in diff) {
        final trash = TrashFile();
        trash.createdAt = item['createdAt'];
        trash.updateAt = item['updatedAt'];
        latestUpdatedAtTime = max(latestUpdatedAtTime, trash.updateAt);
        if (item["isDeleted"]) {
          deletedUploadIDs.add(item["file"]["id"]);
          continue;
        }

        trash.deleteBy = item['deleteBy'];
        trash.uploadedFileID = item["file"]["id"];
        trash.collectionID = item["file"]["collectionID"];
        trash.updationTime = item["file"]["updationTime"];
        trash.ownerID = item["file"]["ownerID"];
        trash.encryptedKey = item["file"]["encryptedKey"];
        trash.keyDecryptionNonce = item["file"]["keyDecryptionNonce"];
        trash.fileDecryptionHeader = item["file"]["file"]["decryptionHeader"];
        trash.thumbnailDecryptionHeader =
            item["file"]["thumbnail"]["decryptionHeader"];
        trash.metadataDecryptionHeader =
            item["file"]["metadata"]["decryptionHeader"];
        final Collection? collection = collectionMap[trash.collectionID];
        if (collection == null) {
          continue;
        }
        final collectionKey = CryptoHelper.instance.getCollectionKey(
          collection,
        );
        final key = CryptoHelper.instance.getFileKey(
          trash.encryptedKey!,
          trash.keyDecryptionNonce!,
          collectionKey,
        );
        final encodedMetadata = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(item["file"]["metadata"]["encryptedData"]),
          key,
          CryptoUtil.base642bin(trash.metadataDecryptionHeader!),
        );
        final Map<String, dynamic> metadata = jsonDecode(
          utf8.decode(encodedMetadata),
        );
        trash.applyMetadata(metadata);
        if (item["file"]['magicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptData(
            CryptoUtil.base642bin(item["file"]['magicMetadata']['data']),
            key,
            CryptoUtil.base642bin(item["file"]['magicMetadata']['header']),
          );
          trash.mMdEncodedJson = utf8.decode(utfEncodedMmd);
          trash.mMdVersion = item["file"]['magicMetadata']['version'];
        }
        if (item["file"]['pubMagicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptData(
            CryptoUtil.base642bin(item["file"]['pubMagicMetadata']['data']),
            key,
            CryptoUtil.base642bin(item["file"]['pubMagicMetadata']['header']),
          );
          trash.pubMmdEncodedJson = utf8.decode(utfEncodedMmd);
          trash.pubMmdVersion = item["file"]['pubMagicMetadata']['version'];
          trash.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
            trash.pubMmdEncodedJson!,
          );
        }
        if (item['isRestored']) {
          restoredFiles.add(trash);
          continue;
        }
        trashedFiles.add(trash);
      }

      final endTime = DateTime.now();
      _logger.info(
        "time for parsing ${diff.length}: ${Duration(microseconds: (endTime.microsecondsSinceEpoch - startTime.microsecondsSinceEpoch)).inMilliseconds}",
      );
      return TrashDiff(
        trashedFiles,
        restoredFiles,
        deletedUploadIDs,
        hasMore,
        latestUpdatedAtTime,
      );
    } catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  Future<void> deleteFromTrash(List<EnteFile> files) async {
    final params = <String, dynamic>{};
    final uniqueFileIds = files.map((e) => e.uploadedFileID!).toSet().toList();
    params["fileIDs"] = [];
    for (final fileID in uniqueFileIds) {
      params["fileIDs"].add(fileID);
    }
    await _enteDio.post("/trash/delete", data: params);
    await _db.deleteTrashFiles(uniqueFileIds);
    await _db.deleteFilesByUploadedFileIDs(uniqueFileIds);
    // no need to await on syncing trash from remote
    unawaited(syncTrash());
  }

  Future<void> emptyTrash() async {
    final params = <String, dynamic>{};
    params["lastUpdatedAt"] = _getSyncTime();
    final trashFiles = await _db.getTrashFiles();
    if (trashFiles.isEmpty) {
      _logger.info("Skipping empty trash because local trash is empty");
      return;
    }
    final fileIDs = trashFiles
        .map((trashFile) => trashFile.uploadedFileID!)
        .toList();

    await _enteDio.post("/trash/empty", data: params);

    await _db.clearTrashFilesTable();
    await _db.deleteFilesByUploadedFileIDs(fileIDs);
    unawaited(syncTrash());
    _logger.info("Successfully emptied trash");
  }

  Future<void> restore(List<EnteFile> files, Collection toCollection) async {
    final params = <String, dynamic>{};
    params["collectionID"] = toCollection.id;
    final toCollectionKey = CryptoHelper.instance.getCollectionKey(
      toCollection,
    );
    params["files"] = [];
    for (final file in files) {
      final fileKey = await CollectionService.instance.getFileKey(file);
      file.collectionID = toCollection.id;
      final encryptedKeyData = CryptoUtil.encryptSync(fileKey, toCollectionKey);
      final encryptedKey = CryptoUtil.bin2base64(
        encryptedKeyData.encryptedData!,
      );
      final keyDecryptionNonce = CryptoUtil.bin2base64(encryptedKeyData.nonce!);
      params["files"].add(
        CollectionFileItem(
          file.uploadedFileID!,
          encryptedKey,
          keyDecryptionNonce,
        ).toMap(),
      );
    }
    await _enteDio.post("/collections/restore-files", data: params);
    await _db.deleteTrashFiles(files.map((e) => e.uploadedFileID!).toList());
    // Refresh collections so restored files are immediately available in UI
    await CollectionService.instance.sync();
    Bus.instance.fire(CollectionsUpdatedEvent("file_restore"));
    Bus.instance.fire(UserDetailsRefreshEvent());
  }
}

class TrashDiff {
  final List<TrashFile> trashedFiles;
  final List<TrashFile> restoredFiles;
  final List<int> deletedUploadIDs;
  final bool hasMore;
  final int lastSyncedTimeStamp;
  TrashDiff(
    this.trashedFiles,
    this.restoredFiles,
    this.deletedUploadIDs,
    this.hasMore,
    this.lastSyncedTimeStamp,
  );
}
