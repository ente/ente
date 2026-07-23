import "dart:async";
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import "package:ente_events/event_bus.dart";
import 'package:ente_network/network.dart';
import "package:ente_sharing/collection_sharing_service.dart";
import "package:ente_sharing/models/user.dart";
import 'package:locker/core/errors.dart';
import "package:locker/events/collections_updated_event.dart";
import "package:locker/services/collections/collections_service.dart";
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/collections/models/collection_file_item.dart';
import 'package:locker/services/collections/models/collection_magic.dart';
import 'package:locker/services/collections/models/diff.dart';
import "package:locker/services/collections/models/public_url.dart";
import 'package:locker/services/configuration.dart';
import "package:locker/services/db/locker_db.dart";
import "package:locker/services/files/sync/metadata_updater_service.dart";
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:locker/services/trash/models/trash_item_request.dart';
import "package:locker/utils/crypto_helper.dart";
import 'package:logging/logging.dart';

class CollectionApiClient {
  CollectionApiClient._privateConstructor();

  static final CollectionApiClient instance =
      CollectionApiClient._privateConstructor();

  final _logger = Logger("CollectionApiClient");
  final _enteDio = Network.instance.enteDio;
  final _config = Configuration.instance;

  late LockerDB _db;

  Future<void> init() async {
    _db = LockerDB.instance;
  }

  Future<List<Collection>> getCollections(int sinceTime) async {
    try {
      final response = await _enteDio.get(
        "/collections/v2",
        queryParameters: {"sinceTime": sinceTime},
      );
      final List<Collection> collections = [];
      final c = response.data["collections"];
      for (final collectionData in c) {
        final Collection collection = await _fromRemoteCollection(
          collectionData,
        );
        collections.add(collection);
      }
      return collections;
    } catch (e, s) {
      _logger.warning(e, s);
      if (e is DioException && e.response?.statusCode == 401) {
        throw UnauthorizedError();
      }
      rethrow;
    }
  }

  Future<Diff> getFiles(Collection collection, int sinceTime) async {
    _logger.info("[Collection-${collection.id}] fetch diff since: $sinceTime");
    bool hasMore = true;
    final List<EnteFile> updatedFiles = [];
    final List<EnteFile> deletedFiles = [];
    int latestUpdatedAtTime = 0;
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    while (hasMore) {
      final diff = await _getDiff(collection.id, collectionKey, sinceTime);
      updatedFiles.addAll(diff.updatedFiles);
      deletedFiles.addAll(diff.deletedFiles);
      latestUpdatedAtTime = max(latestUpdatedAtTime, diff.latestUpdatedAtTime);
      hasMore = diff.hasMore;
    }
    final finalDiff = Diff(
      updatedFiles,
      deletedFiles,
      false,
      latestUpdatedAtTime,
    );
    _logger.info("[Collection-${collection.id}] fetched");
    return finalDiff;
  }

  Future<void> addToCollection(
    Collection collection,
    List<EnteFile> files,
  ) async {
    final pendingUpload = files.any(
      (element) => element.uploadedFileID == null,
    );
    if (pendingUpload) {
      throw ArgumentError('Can only add uploaded files');
    }
    if (files.isEmpty) {
      _logger.info("nothing to add to the collection");
      return;
    }
    final params = <String, dynamic>{};
    params["collectionID"] = collection.id;
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    params["files"] = [];
    for (final file in files) {
      final int uploadedFileID = file.uploadedFileID!;

      // Follow Photos pattern: decrypt using file's current collectionID
      final fileCurrentCollection = await CollectionService.instance
          .getCollection(file.collectionID!);
      final fileCurrentCollectionKey = CryptoHelper.instance.getCollectionKey(
        fileCurrentCollection,
      );
      final fileKey = CryptoHelper.instance.getFileKey(
        file.encryptedKey!,
        file.keyDecryptionNonce!,
        fileCurrentCollectionKey,
      );

      // Re-encrypt the file key with the destination collection's key
      final encryptedKeyData = CryptoUtil.encryptSync(fileKey, collectionKey);
      final String encryptedKey = CryptoUtil.bin2base64(
        encryptedKeyData.encryptedData!,
      );
      final String keyDecryptionNonce = CryptoUtil.bin2base64(
        encryptedKeyData.nonce!,
      );
      params["files"].add(
        CollectionFileItem(
          uploadedFileID,
          encryptedKey,
          keyDecryptionNonce,
        ).toMap(),
      );
    }
    try {
      await _enteDio.post("/collections/add-files", data: params);
    } catch (e) {
      _logger.warning('failed to add files to collection', e);
      rethrow;
    }
  }

  Future<void> trash(List<TrashRequest> requests) async {
    final requestData = <String, dynamic>{};
    requestData["items"] = [];
    for (final request in requests) {
      requestData["items"].add(request.toJson());
    }
    final response = await _enteDio.post("/files/trash", data: requestData);
    if (response.statusCode != 200) {
      throw Exception("Failed to remove files from collection");
    }
  }

  Future<void> removeFromCollection(
    int collectionID,
    List<EnteFile> files,
  ) async {
    if (files.isEmpty) return;

    final params = <String, dynamic>{};
    params["collectionID"] = collectionID;

    const batchSize = 100;
    final batchedFiles = <List<EnteFile>>[];
    for (int i = 0; i < files.length; i += batchSize) {
      batchedFiles.add(files.sublist(i, min(i + batchSize, files.length)));
    }

    for (final batch in batchedFiles) {
      params["fileIDs"] = <int>[];
      for (final file in batch) {
        if (file.uploadedFileID != null) {
          params["fileIDs"].add(file.uploadedFileID);
        }
      }

      if (params["fileIDs"].isNotEmpty) {
        final response = await _enteDio.post(
          "/collections/v3/remove-files",
          data: params,
        );
        if (response.statusCode != 200) {
          throw Exception("Failed to remove files from collection");
        }

        await _db.deleteFilesFromCollection(
          await _db.getCollection(collectionID),
          batch,
        );
      }
    }
  }

  Future<void> rename(Collection collection, String newName) async {
    final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
    final encryptedName = CryptoUtil.encryptSync(
      utf8.encode(newName),
      collectionKey,
    );
    final params = <String, dynamic>{};
    params["collectionID"] = collection.id;
    params["encryptedName"] = CryptoUtil.bin2base64(
      encryptedName.encryptedData!,
    );
    params["nameDecryptionNonce"] = CryptoUtil.bin2base64(encryptedName.nonce!);
    try {
      await _enteDio.post("/collections/rename", data: params);
    } catch (e) {
      _logger.warning("failed to rename collection", e);
      rethrow;
    }
  }

  Future<void> leaveCollection(Collection collection) async {
    await CollectionSharingService.instance.leaveCollection(collection.id);
    await _handleCollectionDeletion(collection);
    await CollectionService.instance.sync();
  }

  Future<void> _handleCollectionDeletion(Collection collection) async {
    await _db.deleteCollection(collection);
    final deletedCollection = collection.copyWith(isDeleted: true);
    await _updateCollectionInDB(deletedCollection);
  }

  Future<void> move(
    List<EnteFile> files,
    Collection fromCollection,
    Collection toCollection,
  ) async {
    if (files.isEmpty) {
      _logger.info("No files to move");
      return;
    }

    final params = <String, dynamic>{};
    params["fromCollectionID"] = fromCollection.id;
    params["toCollectionID"] = toCollection.id;

    // Process files in batches
    const batchSize = 100;
    final batchedFiles = <List<EnteFile>>[];
    for (int i = 0; i < files.length; i += batchSize) {
      batchedFiles.add(files.sublist(i, min(i + batchSize, files.length)));
    }

    for (final batch in batchedFiles) {
      params["files"] = [];
      for (final file in batch) {
        // Follow Photos pattern: use file's collectionID to get the key
        final fileCollection = await CollectionService.instance.getCollection(
          file.collectionID!,
        );
        final fileCollectionKey = CryptoHelper.instance.getCollectionKey(
          fileCollection,
        );
        final fileKey = CryptoHelper.instance.getFileKey(
          file.encryptedKey!,
          file.keyDecryptionNonce!,
          fileCollectionKey,
        );

        // Update file's collectionID to the destination (like Photos does)
        file.collectionID = toCollection.id;

        // Re-encrypt the file key with the destination collection's key
        final destCollectionKey = CryptoHelper.instance.getCollectionKey(
          toCollection,
        );
        final encryptedKeyData = CryptoUtil.encryptSync(
          fileKey,
          destCollectionKey,
        );

        file.encryptedKey = CryptoUtil.bin2base64(
          encryptedKeyData.encryptedData!,
        );
        file.keyDecryptionNonce = CryptoUtil.bin2base64(
          encryptedKeyData.nonce!,
        );

        params["files"].add(
          CollectionFileItem(
            file.uploadedFileID!,
            file.encryptedKey!,
            file.keyDecryptionNonce!,
          ).toMap(),
        );
      }
      await _enteDio.post("/collections/move-files", data: params);
    }
  }

  Future<void> trashCollection(
    Collection collection, {
    bool keepFiles = false,
    bool skipEventFiring = false,
  }) async {
    try {
      await _enteDio.delete(
        "/collections/v3/${collection.id}"
        "?keepFiles=${keepFiles ? "True" : "False"}"
        "&collectionID=${collection.id}",
      );
      if (skipEventFiring) {
        await _db.deleteCollection(collection);
        final deletedCollection = collection.copyWith(isDeleted: true);
        await _updateCollectionInDB(deletedCollection);
      } else {
        await _handleCollectionDeletion(collection);
      }
    } catch (e) {
      _logger.severe('failed to trash collection', e);
      rethrow;
    }
  }

  Future<Diff> _getDiff(
    int collectionID,
    Uint8List collectionKey,
    int sinceTime,
  ) async {
    try {
      final response = await _enteDio.get(
        "/collections/v2/diff",
        queryParameters: {"collectionID": collectionID, "sinceTime": sinceTime},
      );
      int latestUpdatedAtTime = 0;
      final diff = response.data["diff"] as List;
      final bool hasMore = response.data["hasMore"] as bool;
      final startTime = DateTime.now();
      final deletedFiles = <EnteFile>[];
      final updatedFiles = <EnteFile>[];

      for (final item in diff) {
        final file = EnteFile();
        file.uploadedFileID = item["id"];
        file.collectionID = item["collectionID"];
        file.updationTime = item["updationTime"];
        latestUpdatedAtTime = max(latestUpdatedAtTime, file.updationTime!);
        if (item["isDeleted"]) {
          deletedFiles.add(file);
          continue;
        }
        file.ownerID = item["ownerID"];
        file.fileDecryptionHeader = item["file"]["decryptionHeader"];
        file.thumbnailDecryptionHeader = item["thumbnail"]["decryptionHeader"];
        file.metadataDecryptionHeader = item["metadata"]["decryptionHeader"];
        if (item["info"] != null) {
          file.fileSize = item["info"]["fileSize"];
        }
        file.encryptedKey = item["encryptedKey"];
        file.keyDecryptionNonce = item["keyDecryptionNonce"];
        final fileKey = CryptoHelper.instance.getFileKey(
          file.encryptedKey!,
          file.keyDecryptionNonce!,
          collectionKey,
        );
        final encodedMetadata = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(item["metadata"]["encryptedData"]),
          fileKey,
          CryptoUtil.base642bin(file.metadataDecryptionHeader!),
        );
        final Map<String, dynamic> metadata = jsonDecode(
          utf8.decode(encodedMetadata),
        );
        file.applyMetadata(metadata);
        if (item['magicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptData(
            CryptoUtil.base642bin(item['magicMetadata']['data']),
            fileKey,
            CryptoUtil.base642bin(item['magicMetadata']['header']),
          );
          file.mMdEncodedJson = utf8.decode(utfEncodedMmd);
          file.mMdVersion = item['magicMetadata']['version'];
          file.magicMetadata = MagicMetadata.fromEncodedJson(
            file.mMdEncodedJson!,
          );
        }
        if (item['pubMagicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptData(
            CryptoUtil.base642bin(item['pubMagicMetadata']['data']),
            fileKey,
            CryptoUtil.base642bin(item['pubMagicMetadata']['header']),
          );
          file.pubMmdEncodedJson = utf8.decode(utfEncodedMmd);
          file.pubMmdVersion = item['pubMagicMetadata']['version'];
          file.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
            file.pubMmdEncodedJson!,
          );
        }
        updatedFiles.add(file);
      }
      _logger.info(
        '[Collection-$collectionID] parsed ${diff.length} '
        'diff items ( ${updatedFiles.length} updated) in ${DateTime.now().difference(startTime).inMilliseconds}ms',
      );
      return Diff(updatedFiles, deletedFiles, hasMore, latestUpdatedAtTime);
    } catch (e, s) {
      _logger.severe(e, s);
      rethrow;
    }
  }

  Future<Collection> _fromRemoteCollection(
    Map<String, dynamic> collectionData,
  ) async {
    final Collection collection = Collection.fromMap(collectionData);
    if (!collection.isDeleted) {
      final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
      if (collectionData['magicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(collectionData['magicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(collectionData['magicMetadata']['header']),
        );
        collection.mMdEncodedJson = utf8.decode(utfEncodedMmd);
        collection.mMdVersion = collectionData['magicMetadata']['version'];
        collection.magicMetadata = CollectionMagicMetadata.fromEncodedJson(
          collection.mMdEncodedJson ?? '{}',
        );
      }

      if (collectionData['pubMagicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(collectionData['pubMagicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(collectionData['pubMagicMetadata']['header']),
        );
        collection.mMdPubEncodedJson = utf8.decode(utfEncodedMmd);
        collection.mMbPubVersion =
            collectionData['pubMagicMetadata']['version'];
        collection.pubMagicMetadata =
            CollectionPubMagicMetadata.fromEncodedJson(
              collection.mMdPubEncodedJson ?? '{}',
            );
      }
      if (collectionData['sharedMagicMetadata'] != null) {
        final utfEncodedMmd = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(collectionData['sharedMagicMetadata']['data']),
          collectionKey,
          CryptoUtil.base642bin(
            collectionData['sharedMagicMetadata']['header'],
          ),
        );
        collection.sharedMmdJson = utf8.decode(utfEncodedMmd);
        collection.sharedMmdVersion =
            collectionData['sharedMagicMetadata']['version'];
        collection.sharedMagicMetadata = ShareeMagicMetadata.fromEncodedJson(
          collection.sharedMmdJson ?? '{}',
        );
      }
    }
    collection.setName(_getDecryptedCollectionName(collection));
    return collection;
  }

  String _getDecryptedCollectionName(Collection collection) {
    if (collection.isDeleted) {
      return "Deleted Collection";
    }
    if (collection.encryptedName != null &&
        collection.encryptedName!.isNotEmpty) {
      try {
        final collectionKey = CryptoHelper.instance.getCollectionKey(
          collection,
        );
        final result = CryptoUtil.decryptSync(
          CryptoUtil.base642bin(collection.encryptedName!),
          collectionKey,
          CryptoUtil.base642bin(collection.nameDecryptionNonce!),
        );
        return utf8.decode(result);
      } catch (e, s) {
        _logger.severe(
          "failed to decrypt collection name: ${collection.id}",
          e,
          s,
        );
      }
    }
    return collection.name ?? "Untitled";
  }

  Future<Collection> create(String name, CollectionType type) async {
    final collectionKey = CryptoUtil.generateKey();
    final encryptedKeyData = CryptoUtil.encryptSync(
      collectionKey,
      _config.getKey()!,
    );
    final encryptedName = CryptoUtil.encryptSync(
      utf8.encode(name),
      collectionKey,
    );
    final request = CreateRequest(
      encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
      keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      encryptedName: CryptoUtil.bin2base64(encryptedName.encryptedData!),
      nameDecryptionNonce: CryptoUtil.bin2base64(encryptedName.nonce!),
      type: type,
      attributes: CollectionAttributes(),
    );
    return _enteDio.post("/collections", data: request.toJson()).then((
      response,
    ) async {
      final collectionData = response.data["collection"];
      final collection = await _fromRemoteCollection(collectionData);
      return collection;
    });
  }

  Future<void> createShareUrl(
    Collection collection, {
    bool enableCollect = false,
  }) async {
    final response = await CollectionSharingService.instance.createShareUrl(
      collection.id,
      enableCollect,
    );

    collection.publicURLs.add(PublicURL.fromMap(response.data["result"]));
    await _updateCollectionInDB(collection);
    _logger.info("Firing CollectionsUpdatedEvent: share_url_created");
    Bus.instance.fire(CollectionsUpdatedEvent("share_url_created"));
    unawaited(CollectionService.instance.sync());
  }

  Future<void> disableShareUrl(Collection collection) async {
    await CollectionSharingService.instance.disableShareUrl(collection.id);
    collection.publicURLs.clear();
    await _updateCollectionInDB(collection);
    _logger.info("Firing CollectionsUpdatedEvent: share_url_disabled");
    Bus.instance.fire(CollectionsUpdatedEvent("share_url_disabled"));
    unawaited(CollectionService.instance.sync());
  }

  Future<void> updateShareUrl(
    Collection collection,
    Map<String, dynamic> prop,
  ) async {
    prop.putIfAbsent('collectionID', () => collection.id);

    final response = await CollectionSharingService.instance.updateShareUrl(
      collection.id,
      prop,
    );
    // remove existing url information
    collection.publicURLs.clear();
    collection.publicURLs.add(PublicURL.fromMap(response.data["result"]));
    await _updateCollectionInDB(collection);
    _logger.info("Firing CollectionsUpdatedEvent: share_url_updated");
    Bus.instance.fire(CollectionsUpdatedEvent("share_url_updated"));
    unawaited(CollectionService.instance.sync());
  }

  Future<List<User>> share(
    int collectionID,
    String email,
    String publicKey,
    CollectionParticipantRole role,
  ) async {
    final collectionKey = CollectionService.instance.getCollectionKey(
      collectionID,
    );
    final encryptedKey = CryptoUtil.sealSync(
      collectionKey,
      CryptoUtil.base642bin(publicKey),
    );

    final sharees = await CollectionSharingService.instance.share(
      collectionID,
      email,
      publicKey,
      role.toStringVal(),
      collectionKey,
      encryptedKey,
    );

    final collection = CollectionService.instance.getFromCache(collectionID);
    final updatedCollection = collection!.copyWith(sharees: sharees);
    await _updateCollectionInDB(updatedCollection);
    Bus.instance.fire(CollectionsUpdatedEvent("email_share_added"));
    unawaited(CollectionService.instance.sync());
    return sharees;
  }

  Future<List<User>> unshare(int collectionID, String email) async {
    final sharees = await CollectionSharingService.instance.unshare(
      collectionID,
      email,
    );
    final collection = CollectionService.instance.getFromCache(collectionID);
    final updatedCollection = collection!.copyWith(sharees: sharees);
    await _updateCollectionInDB(updatedCollection);
    Bus.instance.fire(CollectionsUpdatedEvent("email_share_removed"));
    unawaited(CollectionService.instance.sync());
    return sharees;
  }

  Future<void> _updateCollectionInDB(Collection collection) async {
    await _db.updateCollections([collection]);
    CollectionService.instance.updateCollectionCache(collection);
  }
}

class CreateRequest {
  String encryptedKey;
  String keyDecryptionNonce;
  String encryptedName;
  String nameDecryptionNonce;
  CollectionType type;
  CollectionAttributes? attributes;
  MetadataRequest? magicMetadata;

  CreateRequest({
    required this.encryptedKey,
    required this.keyDecryptionNonce,
    required this.encryptedName,
    required this.nameDecryptionNonce,
    required this.type,
    this.attributes,
    this.magicMetadata,
  });

  CreateRequest copyWith({
    String? encryptedKey,
    String? keyDecryptionNonce,
    String? encryptedName,
    String? nameDecryptionNonce,
    CollectionType? type,
    CollectionAttributes? attributes,
    MetadataRequest? magicMetadata,
  }) => CreateRequest(
    encryptedKey: encryptedKey ?? this.encryptedKey,
    keyDecryptionNonce: keyDecryptionNonce ?? this.keyDecryptionNonce,
    encryptedName: encryptedName ?? this.encryptedName,
    nameDecryptionNonce: nameDecryptionNonce ?? this.nameDecryptionNonce,
    type: type ?? this.type,
    attributes: attributes ?? this.attributes,
    magicMetadata: magicMetadata ?? this.magicMetadata,
  );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['encryptedKey'] = encryptedKey;
    map['keyDecryptionNonce'] = keyDecryptionNonce;
    map['encryptedName'] = encryptedName;
    map['nameDecryptionNonce'] = nameDecryptionNonce;
    map['type'] = typeToString(type);
    if (attributes != null) {
      map['attributes'] = attributes!.toMap();
    }
    if (magicMetadata != null) {
      map['magicMetadata'] = magicMetadata!.toJson();
    }
    return map;
  }
}
