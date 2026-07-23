import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/core/errors.dart';
import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/events/trigger_logout_event.dart';
import 'package:ente_auth/gateway/authenticator.dart';
import 'package:ente_auth/models/authenticator/auth_entity.dart';
import 'package:ente_auth/models/authenticator/auth_key.dart';
import 'package:ente_auth/models/authenticator/entity_result.dart';
import 'package:ente_auth/models/authenticator/local_auth_entity.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/store/offline_authenticator_db.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_in_event.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AccountMode { online, offline }

extension on AccountMode {
  bool get isOnline => this == AccountMode.online;
  bool get isOffline => this == AccountMode.offline;
}

class AuthenticatorService {
  final _logger = Logger((AuthenticatorService).toString());
  final _config = Configuration.instance;
  late SharedPreferences _prefs;
  late AuthenticatorGateway _gateway;
  late AuthenticatorDB _db;
  late OfflineAuthenticatorDB _offlineDb;
  final String _lastEntitySyncTime = "lastEntitySyncTime";
  Future<bool>? _onlineSyncInFlight;
  bool _onlineSyncRerunRequested = false;

  AuthenticatorService._privateConstructor();

  static final AuthenticatorService instance =
      AuthenticatorService._privateConstructor();

  AccountMode getAccountMode() {
    return Configuration.instance.hasOptedForOfflineMode() &&
            !Configuration.instance.hasConfiguredAccount()
        ? AccountMode.offline
        : AccountMode.online;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _db = AuthenticatorDB.instance;
    _offlineDb = OfflineAuthenticatorDB.instance;
    _gateway = AuthenticatorGateway();
    if (Configuration.instance.hasConfiguredAccount()) {
      unawaited(onlineSync());
    }
    Bus.instance.on<SignedInEvent>().listen((event) {
      unawaited(onlineSync());
    });
  }

  Future<List<EntityResult>> getEntities(AccountMode mode) async {
    final List<LocalAuthEntity> result = mode.isOnline
        ? await _db.getAll()
        : await _offlineDb.getAll();
    final List<EntityResult> entities = [];
    if (result.isEmpty) {
      return entities;
    }
    final key = await getOrCreateAuthDataKey(mode);
    for (LocalAuthEntity e in result) {
      try {
        final decryptedValue = await CryptoUtil.decryptData(
          CryptoUtil.base642bin(e.encryptedData),
          key,
          CryptoUtil.base642bin(e.header),
        );
        final hasSynced = !(e.id == null || e.shouldSync);
        entities.add(
          EntityResult(e.generatedID, utf8.decode(decryptedValue), hasSynced),
        );
      } catch (e, s) {
        _logger.severe(e, s);
      }
    }
    return entities;
  }

  Future<int> addEntry(
    String plainText,
    bool shouldSync,
    AccountMode accountMode,
  ) async {
    var key = await getOrCreateAuthDataKey(accountMode);
    final encryptedKeyData = await CryptoUtil.encryptData(
      utf8.encode(plainText),
      key,
    );
    String encryptedData = CryptoUtil.bin2base64(
      encryptedKeyData.encryptedData!,
    );
    String header = CryptoUtil.bin2base64(encryptedKeyData.header!);
    final insertedID = accountMode.isOnline
        ? await _db.insert(encryptedData, header)
        : await _offlineDb.insert(encryptedData, header);
    if (shouldSync) {
      unawaited(onlineSync());
    }
    return insertedID;
  }

  Future<void> updateEntry(
    int generatedID,
    String plainText,
    bool shouldSync,
    AccountMode accountMode,
  ) async {
    var key = await getOrCreateAuthDataKey(accountMode);
    final encryptedKeyData = await CryptoUtil.encryptData(
      utf8.encode(plainText),
      key,
    );
    String encryptedData = CryptoUtil.bin2base64(
      encryptedKeyData.encryptedData!,
    );
    String header = CryptoUtil.bin2base64(encryptedKeyData.header!);
    final int affectedRows = accountMode.isOnline
        ? await _db.updateEntry(generatedID, encryptedData, header)
        : await _offlineDb.updateEntry(generatedID, encryptedData, header);
    assert(
      affectedRows == 1,
      "updateEntry should have updated exactly one row",
    );
    if (shouldSync) {
      unawaited(onlineSync());
    }
  }

  Future<void> deleteEntry(int genID, AccountMode accountMode) async {
    LocalAuthEntity? result = accountMode.isOnline
        ? await _db.getEntryByID(genID)
        : await _offlineDb.getEntryByID(genID);
    if (result == null) {
      _logger.info("No entry found for given id");
      return;
    }
    if (result.id != null && accountMode.isOnline) {
      await _gateway.deleteEntity(result.id!);
    } else {
      debugPrint("Skipping delete since account mode is offline");
    }
    if (accountMode.isOnline) {
      await _db.deleteByIDs(generatedIDs: [genID]);
    } else {
      await _offlineDb.deleteByIDs(generatedIDs: [genID]);
    }
  }

  Future<bool> onlineSync() {
    final inFlightSync = _onlineSyncInFlight;
    if (inFlightSync != null) {
      _onlineSyncRerunRequested = true;
      return inFlightSync;
    }

    final completer = Completer<bool>();
    _onlineSyncInFlight = completer.future;
    unawaited(_runCoalescedOnlineSync(completer));
    return completer.future;
  }

  Future<void> _runCoalescedOnlineSync(Completer<bool> completer) async {
    bool lastResult = false;
    try {
      while (true) {
        _onlineSyncRerunRequested = false;
        lastResult = await _onlineSyncOnce();
        if (!_onlineSyncRerunRequested) {
          break;
        }
        _logger.info("Sync rerun requested while syncing; running again");
      }
    } catch (e, s) {
      _logger.severe("Unexpected failure while coalescing syncs", e, s);
      lastResult = false;
    } finally {
      _onlineSyncInFlight = null;
      if (!completer.isCompleted) {
        completer.complete(lastResult);
      }
    }
  }

  Future<bool> _onlineSyncOnce() async {
    try {
      if (getAccountMode().isOffline) {
        debugPrint("Skipping sync since account mode is offline");
        return false;
      }
      _logger.info("Sync");
      await _remoteToLocalSync();
      _logger.info("remote fetch completed");
      await _localToRemoteSync();
      _logger.info("local push completed");
      Bus.instance.fire(CodesUpdatedEvent());
      return true;
    } on UnauthorizedError {
      if ((await _db.removeSyncedData()) > 0) {
        Bus.instance.fire(CodesUpdatedEvent());
      }
      debugPrint("Firing logout event");

      Bus.instance.fire(TriggerLogoutEvent());
      return false;
    } catch (e) {
      _logger.severe("Failed to sync with remote", e);
      return false;
    }
  }

  Future<void> _remoteToLocalSync() async {
    _logger.info('Initiating remote to local sync');
    final int lastSyncTime = _prefs.getInt(_lastEntitySyncTime) ?? 0;
    _logger.info("Current sync is $lastSyncTime");
    const int fetchLimit = 500;
    late final List<AuthEntity> result;
    late final int? epochTimeInMicroseconds;
    (result, epochTimeInMicroseconds) = await _gateway.getDiff(
      lastSyncTime,
      limit: fetchLimit,
    );
    PreferenceService.instance.computeAndStoreTimeOffset(
      epochTimeInMicroseconds,
    );

    _logger.info("${result.length} entries fetched from remote");
    if (result.isEmpty) {
      return;
    }
    final maxSyncTime = result.map((e) => e.updatedAt).reduce(max);
    List<String> deletedIDs = result
        .where((element) => element.isDeleted)
        .map((e) => e.id)
        .toList();
    _logger.info("${deletedIDs.length} entries deleted");
    result.removeWhere((element) => element.isDeleted);
    await _db.insertOrReplace(result);
    if (deletedIDs.isNotEmpty) {
      await _db.deleteByIDs(ids: deletedIDs);
    }
    await _prefs.setInt(_lastEntitySyncTime, maxSyncTime);
    _logger.info("Setting synctime to $maxSyncTime");
    if (result.length == fetchLimit) {
      _logger.info("Diff limit reached, pulling again");
      await _remoteToLocalSync();
    }
  }

  Future<void> _localToRemoteSync() async {
    _logger.info('Initiating local to remote sync');
    final List<LocalAuthEntity> result = await _db.getAll();
    final List<LocalAuthEntity> pendingUpdate = result
        .where((element) => element.shouldSync || element.id == null)
        .toList();
    _logger.info("${pendingUpdate.length} entries to be updated at remote");
    for (LocalAuthEntity entity in pendingUpdate) {
      if (entity.id == null) {
        _logger.info("Adding new entry");
        final authEntity = await _gateway.createEntity(
          entity.encryptedData,
          entity.header,
        );
        await _db.updateLocalEntity(
          entity.copyWith(id: authEntity.id, shouldSync: false),
        );
      } else {
        _logger.info("Updating entry");
        await _gateway.updateEntity(
          entity.id!,
          entity.encryptedData,
          entity.header,
        );
        await _db.updateLocalEntity(entity.copyWith(shouldSync: false));
      }
    }
    if (pendingUpdate.isNotEmpty) {
      _logger.info("Initiating remote sync since local entries were pushed");
      await _remoteToLocalSync();
    }
  }

  Future<Uint8List> getOrCreateAuthDataKey(AccountMode mode) async {
    if (mode.isOffline) {
      return _config.getOfflineSecretKey()!;
    }
    if (_config.getAuthSecretKey() != null) {
      return _config.getAuthSecretKey()!;
    }
    try {
      final AuthKey response = await _gateway.getKey();
      final authKey = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(response.encryptedKey),
        _config.getKey()!,
        CryptoUtil.base642bin(response.header),
      );
      await _config.setAuthSecretKey(CryptoUtil.bin2base64(authKey));
      return authKey;
    } on AuthenticatorKeyNotFound catch (e) {
      _logger.info("AuthenticatorKeyNotFound generating key ${e.stackTrace}");
      final key = CryptoUtil.generateKey();
      final encryptedKeyData = CryptoUtil.encryptSync(key, _config.getKey()!);
      await _gateway.createKey(
        CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
        CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      );
      await _config.setAuthSecretKey(CryptoUtil.bin2base64(key));
      return key;
    } catch (e, s) {
      _logger.severe("Failed to getOrCreateAuthDataKey", e, s);
      rethrow;
    }
  }
}
