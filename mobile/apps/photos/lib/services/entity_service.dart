import 'dart:async';
import 'dart:convert';
import 'dart:math';

import "package:crypto/crypto.dart";
import "package:ente_crypto/ente_crypto.dart";
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import "package:photos/db/entities_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/gateways/entity/entity_gateway.dart";
import "package:photos/gateways/entity/models/data.dart";
import "package:photos/gateways/entity/models/key.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/utils/gzip.dart";
import 'package:shared_preferences/shared_preferences.dart';

class EntityService {
  static const int fetchLimit = 500;
  final _logger = Logger((EntityService).toString());
  final SharedPreferences _prefs;
  final EntityGateway _gateway;
  final _config = Configuration.instance;
  late final FilesDB _db = FilesDB.instance;

  EntityService(this._prefs, this._gateway) {
    debugPrint("EntityService constructor");
  }

  String _getEntityKeyPrefix(EntityType type) {
    return "entity_key_" + type.name;
  }

  String _getEntityHeaderPrefix(EntityType type) {
    return "entity_key_header_" + type.name;
  }

  String _getEntityLastSyncTimePrefix(EntityType type) {
    return "entity_last_sync_time_" + type.name;
  }

  Future<List<LocalEntityData>> getCertainEntities(
    EntityType type,
    List<String> ids,
  ) async {
    return await _db.getCertainEntities(type, ids);
  }

  Future<List<LocalEntityData>> getEntities(EntityType type) async {
    return await _db.getEntities(type);
  }

  Future<LocalEntityData?> getEntity(EntityType type, String id) async {
    return await _db.getEntity(type, id);
  }

  Future<LocalEntityData> addOrUpdate(
    EntityType type,
    Map<String, dynamic> jsonMap, {
    String? id,
    bool addWithCustomID = false,
  }) async {
    final String plainText = jsonEncode(jsonMap);
    final key = await getOrCreateEntityKey(type);
    late String encryptedData, header;
    if (type.isZipped) {
      final ChaChaEncryptionResult result = await gzipAndEncryptJson(
        jsonMap,
        key,
      );
      encryptedData = result.encData;
      header = result.header;
    } else {
      final encryptedKeyData = await CryptoUtil.encryptChaCha(
        utf8.encode(plainText),
        key,
      );
      encryptedData = CryptoUtil.bin2base64(encryptedKeyData.encryptedData!);
      header = CryptoUtil.bin2base64(encryptedKeyData.header!);
    }
    debugPrint(
      " ${id == null ? 'Adding' : 'Updating'} entity of type: " + type.name,
    );

    final EntityData data = id == null || addWithCustomID
        ? await _gateway.createEntity(type, id, encryptedData, header)
        : await _gateway.updateEntity(type, id, encryptedData, header);
    final localData = LocalEntityData(
      id: data.id,
      type: type,
      data: plainText,
      ownerID: data.userID,
      updatedAt: data.updatedAt,
    );

    await _db.upsertEntities([localData]);
    syncEntities().ignore();
    return localData;
  }

  Future<void> deleteEntry(String id) async {
    await _gateway.deleteEntity(id);
    await _db.deleteEntities([id]);
  }

  Future<void> syncEntities() async {
    try {
      await _remoteToLocalSync(EntityType.location);
      await _remoteToLocalSync(EntityType.cgroup);
      await _remoteToLocalSync(EntityType.smartAlbum);
    } catch (e) {
      _logger.severe("Failed to sync entities", e);
    }
  }

  Future<int> syncEntity(EntityType type) async {
    try {
      return _remoteToLocalSync(type);
    } catch (e) {
      _logger.severe("Failed to sync entities", e);
      return -1;
    }
  }

  int lastSyncTime(EntityType type) {
    return _prefs.getInt(_getEntityLastSyncTimePrefix(type)) ?? 0;
  }

  Future<int> _remoteToLocalSync(
    EntityType type, {
    int prevFetchCount = 0,
  }) async {
    final int lastSyncTime =
        _prefs.getInt(_getEntityLastSyncTimePrefix(type)) ?? 0;
    final List<EntityData> result = await _gateway.getDiff(
      type,
      lastSyncTime,
      limit: fetchLimit,
    );
    if (result.isEmpty) {
      return prevFetchCount;
    }
    final bool hasMoreItems = result.length == fetchLimit;
    _logger.info("${result.length} entries of type $type fetched");
    final maxSyncTime = result.map((e) => e.updatedAt).reduce(max);
    final List<String> deletedIDs = result
        .where((element) => element.isDeleted)
        .map((e) => e.id)
        .toList();
    if (deletedIDs.isNotEmpty) {
      _logger.info("${deletedIDs.length} entries of type $type deleted");
      await _db.deleteEntities(deletedIDs);
    }
    result.removeWhere((element) => element.isDeleted);
    if (result.isNotEmpty) {
      final entityKey = await getOrCreateEntityKey(type);
      final List<LocalEntityData> entities = [];
      for (EntityData e in result) {
        try {
          late String plainText;
          if (type.isZipped) {
            final jsonMap = await decryptAndUnzipJson(
              entityKey,
              encryptedData: e.encryptedData!,
              header: e.header!,
            );
            plainText = jsonEncode(jsonMap);
          } else {
            final Uint8List decryptedValue = await CryptoUtil.decryptChaCha(
              CryptoUtil.base642bin(e.encryptedData!),
              entityKey,
              CryptoUtil.base642bin(e.header!),
            );
            plainText = utf8.decode(decryptedValue);
          }
          entities.add(
            LocalEntityData(
              id: e.id,
              type: type,
              data: plainText,
              ownerID: e.userID,
              updatedAt: e.updatedAt,
            ),
          );
        } catch (e, s) {
          _logger.severe("Failed to decrypted data for key $type", e, s);
          rethrow;
        }
      }
      if (entities.isNotEmpty) {
        await _db.upsertEntities(entities);
      }
    }
    await _prefs.setInt(_getEntityLastSyncTimePrefix(type), maxSyncTime);
    if (hasMoreItems) {
      _logger.info("Diff limit reached, pulling again");
      await _remoteToLocalSync(
        type,
        prevFetchCount: prevFetchCount + result.length,
      );
    }
    return prevFetchCount + result.length;
  }

  Future<Uint8List> getOrCreateEntityKey(EntityType type) async {
    late String encryptedKey;
    late String header;
    try {
      if (_prefs.containsKey(_getEntityKeyPrefix(type)) &&
          _prefs.containsKey(_getEntityHeaderPrefix(type))) {
        encryptedKey = _prefs.getString(_getEntityKeyPrefix(type))!;
        header = _prefs.getString(_getEntityHeaderPrefix(type))!;
      } else {
        final EntityKey response = await _gateway.getKey(type);
        encryptedKey = response.encryptedKey;
        header = response.header;
        await _prefs.setString(_getEntityKeyPrefix(type), encryptedKey);
        await _prefs.setString(_getEntityHeaderPrefix(type), header);
      }
      final entityKey = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(encryptedKey),
        _config.getKey()!,
        CryptoUtil.base642bin(header),
      );
      return entityKey;
    } on EntityKeyNotFound {
      _logger.info("EntityKeyNotFound generating key for type $type");
      final key = CryptoUtil.generateKey();
      final encryptedKeyData = CryptoUtil.encryptSync(key, _config.getKey()!);
      encryptedKey = CryptoUtil.bin2base64(encryptedKeyData.encryptedData!);
      header = CryptoUtil.bin2base64(encryptedKeyData.nonce!);
      await _gateway.createKey(type, encryptedKey, header);
      await _prefs.setString(_getEntityKeyPrefix(type), encryptedKey);
      await _prefs.setString(_getEntityHeaderPrefix(type), header);
      return key;
    } catch (e, s) {
      _logger.severe("Failed to getOrCreateKey for type $type", e, s);
      rethrow;
    }
  }

  Future<String?> getPreHashForEntities(
    EntityType type,
    List<String> ids,
  ) async {
    return await _db.getPreHashForEntities(type, ids);
  }

  Future<String> getHashForIds(List<String> personIds) async {
    final preHash = await getPreHashForEntities(EntityType.cgroup, personIds);

    if (preHash == null) {
      return "";
    }

    final hash = md5.convert(utf8.encode(preHash)).toString().substring(0, 10);
    return hash;
  }

  Future<Map<String, int>> getUpdatedAts(
    EntityType type,
    List<String> personIds,
  ) async {
    return await _db.getUpdatedAts(type, personIds);
  }
}
