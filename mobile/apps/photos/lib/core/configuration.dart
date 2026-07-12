import "dart:async";
import 'dart:convert';
import "dart:io";

import 'package:backup_exclusion/backup_exclusion.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_contacts/contacts.dart';
import "package:ente_crypto/ente_crypto.dart";
import 'package:ente_lock_screen/lock_screen_host.dart';
import "package:flutter/services.dart";
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import "package:photos/app_mode.dart";
import 'package:photos/core/cache/image_cache.dart';
import 'package:photos/core/cache/thumbnail_in_memory_cache.dart';
import 'package:photos/core/cache/video_cache_manager.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/error-reporting/super_logging.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/collections_db.dart';
import 'package:photos/db/files_db.dart';
import "package:photos/db/gallery_downloads_db.dart";
import "package:photos/db/memories_db.dart";
import "package:photos/db/memory_shares_db.dart";
import "package:photos/db/ml/db.dart";
import 'package:photos/db/trash_db.dart';
import 'package:photos/db/upload_locks_db.dart';
import "package:photos/events/app_mode_changed_event.dart";
import 'package:photos/events/signed_in_event.dart';
import 'package:photos/events/user_logged_out_event.dart';
import 'package:photos/gateways/users/models/key_attributes.dart';
import 'package:photos/gateways/users/models/key_gen_result.dart';
import 'package:photos/gateways/users/models/private_key_attributes.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/module/upload/upload_artifact.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/favorites_service.dart';
import "package:photos/services/home_widget_service.dart";
import 'package:photos/services/ignored_files_service.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/similar_images_service.dart";
import "package:photos/services/memory_share_service.dart";
import "package:photos/services/notification_service.dart";
import 'package:photos/services/search_service.dart';
import 'package:photos/services/sync/sync_service.dart';
import 'package:photos/services/video_preview_service.dart';
import 'package:photos/utils/validator_util.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "package:tuple/tuple.dart";
import 'package:uuid/uuid.dart';

class Configuration implements LockScreenHost, AccountDeletionHost {
  Configuration._privateConstructor();

  static final Configuration instance = Configuration._privateConstructor();

  static const emailKey = "email";
  static const keyAttributesKey = "key_attributes";
  static const keyKey = "key";
  static const lastTempFolderClearTimeKey = "last_temp_folder_clear_time";
  static const secretKeyKey = "secret_key";
  static const tokenKey = "token";
  static const encryptedTokenKey = "encrypted_token";
  static const userIDKey = "user_id";
  static const hasMigratedSecureStorageKey = "has_migrated_secure_storage";
  static const anonymousUserIDKey = "anonymous_user_id";
  static final _logger = Logger("Configuration");

  String? _cachedToken;
  late String _documentsDirectory;
  String? _key;
  late SharedPreferences _preferences;
  String? _secretKey;
  late FlutterSecureStorage _secureStorage;
  late String _tempDocumentsDirPath;
  late String _thumbnailCacheDirectory;
  late String _personFaceThumbnailCacheDirectory;

  late String _sharedDocumentsMediaDirectory;
  String? _volatilePassword;

  Future<void> init(SharedPreferences preferences) async {
    try {
      _preferences = preferences;
      _secureStorage = const FlutterSecureStorage(
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      _documentsDirectory = (await getApplicationDocumentsDirectory()).path;
      final appSupportDirectory = await getApplicationSupportDirectory();
      // Exclude Documents (SQLite, thumbnails, decrypted media) and Application Support (ML models) from backups since they’re server-derivable or must remain within the device’s E2EE boundary.
      await excludeFromBackup(_documentsDirectory);
      await excludeFromBackup(appSupportDirectory.path);
      _tempDocumentsDirPath = _documentsDirectory + "/temp/";
      final tempDocumentsDir = Directory(_tempDocumentsDirPath);
      await _cleanUpStaleFiles(tempDocumentsDir);
      tempDocumentsDir.createSync(recursive: true);
      final tempDirectoryPath = (await getTemporaryDirectory()).path;
      _thumbnailCacheDirectory = tempDirectoryPath + "/thumbnail-cache";
      Directory(_thumbnailCacheDirectory).createSync(recursive: true);
      _personFaceThumbnailCacheDirectory =
          _documentsDirectory + "/person-face-thumbnail-cache";
      Directory(_personFaceThumbnailCacheDirectory).createSync(recursive: true);
      _sharedDocumentsMediaDirectory =
          _documentsDirectory + "/ente-shared-media";
      Directory(_sharedDocumentsMediaDirectory).createSync(recursive: true);
      if (!_preferences.containsKey(tokenKey)) {
        _logger.info(
          "(for debugging) Token not found, deleting all secure storage data",
        );
        await _secureStorage.deleteAll();
      } else {
        _logger.info(
          "(for debugging) Token found, loading secure storage data",
        );
        _key = await _secureStorage.read(key: keyKey);
        _logger.info(
          "(for debugging) Key loaded from secure storage, is null: ${_key == null}",
        );
        _secretKey = await _secureStorage.read(key: secretKeyKey);
        _logger.info(
          "(for debugging) Secret Key loaded from secure storage, is null: ${_secretKey == null}",
        );
        if (_key == null) {
          await logout(autoLogout: true);
        }
        await _migrateSecurityStorageToFirstUnlock();
      }
      SuperLogging.setUserID(await _getOrCreateAnonymousUserID()).ignore();
      _logger.info('User ID: ${getUserID()}');
    } catch (e, s) {
      _logger.severe("Configuration init failed", e, s);
      /*
      Check if it's a known is related to reading secret from secure storage
      on android https://github.com/mogol/flutter_secure_storage/issues/541
       */
      if (e is PlatformException) {
        final PlatformException error = e;
        final bool isBadPaddingError =
            error.toString().contains('BadPaddingException') ||
            (error.message ?? '').contains('BadPaddingException');
        if (isBadPaddingError) {
          await logout(autoLogout: true);
          return;
        }
      } else {
        rethrow;
      }
    }
  }

  // _cleanUpStaleFiles deletes all files in the temp directory that are older
  // than kTempFolderDeletionTimeBuffer except the the temp encrypted files for upload.
  // Those file are deleted by file uploader after the upload is complete or those
  // files are not being used / tracked.
  Future<void> _cleanUpStaleFiles(Directory tempDocumentsDir) async {
    try {
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      if (tempDocumentsDir.existsSync() &&
          (_preferences.getInt(lastTempFolderClearTimeKey) ?? 0) <
              (currentTime - tempDirCleanUpInterval)) {
        int skippedTempUploadFiles = 0;
        final files = tempDocumentsDir.listSync();
        for (final file in files) {
          if (file is File) {
            if (isUploadTempArtifactPath(file.path)) {
              skippedTempUploadFiles++;
              continue;
            }
            _logger.info("Deleting file: ${file.path}");
            await file.delete();
          } else if (file is Directory) {
            await file.delete(recursive: true);
          }
        }
        await _preferences.setInt(lastTempFolderClearTimeKey, currentTime);
        _logger.info(
          "Cleared temp folder except $skippedTempUploadFiles upload files",
        );
      } else {
        _logger.info("Skipping temp folder clear");
      }
    } catch (e) {
      _logger.warning(e);
    }
  }

  @override
  Future<void> logout({bool autoLogout = false}) async {
    _logger.info("Logging out, autoLogout: $autoLogout");
    if (!autoLogout) {
      if (flagService.stopStreamProcess) {
        VideoPreviewService.instance.stop('logout');
      }
      if (SyncService.instance.isSyncInProgress()) {
        SyncService.instance.stopSync();
        try {
          await SyncService.instance.existingSync().timeout(
            const Duration(seconds: 5),
          );
        } catch (e) {
          // ignore
        }
      }
    }

    // Clear preferences and secure storage
    await _preferences.clear();
    await _secureStorage.deleteAll();
    _key = null;
    _cachedToken = null;
    _secretKey = null;
    _volatilePassword = null;

    // Clear all scheduled notifications (ritual reminders, memories, etc.)
    await NotificationService.instance.clearAllScheduledNotifications(
      logLines: false,
    );

    // Clear all database tables
    await FilesDB.instance.clearTable();
    await GalleryDownloadsDB.instance.clearTable();
    await CollectionsDB.instance.clearTable();
    await MemoriesDB.instance.clearTable();
    await MemorySharesDB.instance.clearTable();
    await MLDataDB.instance.clearTable();
    await UploadLocksDB.instance.clearTable();
    await TrashDB.instance.clearTable();
    await ContactsDatabase().clearTable();

    // Clear all in-memory caches
    ThumbnailInMemoryLruCache.clearAll();
    FileLruCache.clearAll();

    // Clear image cache
    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      _logger.warning("Failed to clear image cache", e);
    }

    // Clear video cache
    try {
      await VideoCacheManager.instance.emptyCache();
    } catch (e) {
      _logger.warning("Failed to clear video cache", e);
    }

    // Clear all service caches
    await SimilarImagesService.instance.clearCache();
    await IgnoredFilesService.instance.reset();
    unawaited(HomeWidgetService.instance.clearWidget(autoLogout));
    MemoryShareService.instance.clearCache();

    // Clear additional caches (safe to call even if not initialized)
    try {
      await magicCacheService.clearMagicCache();
    } catch (e) {
      _logger.info("MagicCacheService not initialized or failed to clear", e);
    }

    try {
      await memoriesCacheService.clearMemoriesCache();
    } catch (e) {
      _logger.info(
        "MemoriesCacheService not initialized or failed to clear",
        e,
      );
    }

    // Reset Ente Rewind caches and services
    try {
      wrappedService.resetForLogout();
    } catch (e) {
      _logger.info("WrappedService not initialized or failed to reset", e);
    }
    try {
      await wrappedCacheService.clearAll();
    } catch (e) {
      _logger.info("WrappedCacheService not initialized or failed to clear", e);
    }

    if (!autoLogout) {
      // Following services won't be initialized if it's the case of autoLogout
      FileUploader.instance.clearCachedUploadURLs();
      CollectionsService.instance.clearCache();
      FavoritesService.instance.clearCache();
      SearchService.instance.clearCache();
      PersonService.instance.clearCache();
      try {
        smartAlbumsService.clearCache();
      } catch (e) {
        _logger.info("SmartAlbumsService not initialized", e);
      }
      try {
        billingService.clearCache();
      } catch (e) {
        _logger.info("BillingService not initialized", e);
      }
      Bus.instance.fire(UserLoggedOutEvent());
    } else {
      await _preferences.setBool("auto_logout", true);
    }
  }

  bool showAutoLogoutDialog() {
    return _preferences.containsKey("auto_logout");
  }

  Future<bool> clearAutoLogoutFlag() {
    return _preferences.remove("auto_logout");
  }

  Future<KeyGenResult> generateKey(String password) async {
    // Create a master key
    final masterKey = CryptoUtil.generateKey();

    // Create a recovery key
    final recoveryKey = CryptoUtil.generateKey();

    // Encrypt master key and recovery key with each other
    final encryptedMasterKey = CryptoUtil.encryptSync(masterKey, recoveryKey);
    final encryptedRecoveryKey = CryptoUtil.encryptSync(recoveryKey, masterKey);

    // Derive a key from the password that will be used to encrypt and
    // decrypt the master key
    final kekSalt = CryptoUtil.getSaltToDeriveKey();
    final derivedKeyResult = await CryptoUtil.deriveSensitiveKey(
      utf8.encode(password),
      kekSalt,
    );
    final loginKey = await CryptoUtil.deriveLoginKey(derivedKeyResult.key);

    // Encrypt the key with this derived key
    final encryptedKeyData = CryptoUtil.encryptSync(
      masterKey,
      derivedKeyResult.key,
    );

    // Generate a public-private keypair and encrypt the latter
    final keyPair = await CryptoUtil.generateKeyPair();
    final encryptedSecretKeyData = CryptoUtil.encryptSync(
      keyPair.sk,
      masterKey,
    );

    final attributes = KeyAttributes(
      CryptoUtil.bin2base64(kekSalt),
      CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
      CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      CryptoUtil.bin2base64(keyPair.pk),
      CryptoUtil.bin2base64(encryptedSecretKeyData.encryptedData!),
      CryptoUtil.bin2base64(encryptedSecretKeyData.nonce!),
      derivedKeyResult.memLimit,
      derivedKeyResult.opsLimit,
      CryptoUtil.bin2base64(encryptedMasterKey.encryptedData!),
      CryptoUtil.bin2base64(encryptedMasterKey.nonce!),
      CryptoUtil.bin2base64(encryptedRecoveryKey.encryptedData!),
      CryptoUtil.bin2base64(encryptedRecoveryKey.nonce!),
    );
    final privateAttributes = PrivateKeyAttributes(
      CryptoUtil.bin2base64(masterKey),
      CryptoUtil.bin2hex(recoveryKey),
      CryptoUtil.bin2base64(keyPair.sk),
    );
    return KeyGenResult(attributes, privateAttributes, loginKey);
  }

  Future<Tuple2<KeyAttributes, Uint8List>> getAttributesForNewPassword(
    String password,
  ) async {
    // Get master key
    final masterKey = getKey();

    // Derive a key from the password that will be used to encrypt and
    // decrypt the master key
    final kekSalt = CryptoUtil.getSaltToDeriveKey();
    final derivedKeyResult = await CryptoUtil.deriveSensitiveKey(
      utf8.encode(password),
      kekSalt,
    );
    final loginKey = await CryptoUtil.deriveLoginKey(derivedKeyResult.key);

    // Encrypt the key with this derived key
    final encryptedKeyData = CryptoUtil.encryptSync(
      masterKey!,
      derivedKeyResult.key,
    );

    final existingAttributes = getKeyAttributes();

    final updatedAttributes = existingAttributes!.copyWith(
      kekSalt: CryptoUtil.bin2base64(kekSalt),
      encryptedKey: CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
      keyDecryptionNonce: CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      memLimit: derivedKeyResult.memLimit,
      opsLimit: derivedKeyResult.opsLimit,
    );
    return Tuple2(updatedAttributes, loginKey);
  }

  // decryptSecretsAndGetLoginKey decrypts the master key and recovery key
  // with the given password and save them in local secure storage.
  // This method also returns the keyEncKey that can be used for performing
  // SRP setup for existing users.
  Future<Uint8List> decryptSecretsAndGetKeyEncKey(
    String password,
    KeyAttributes attributes, {
    Uint8List? keyEncryptionKey,
  }) async {
    validatePreVerificationStateCheck(
      attributes,
      password,
      getEncryptedToken(),
    );
    // Derive key-encryption-key from the entered password and existing
    // mem and ops limits
    keyEncryptionKey ??= await CryptoUtil.deriveKey(
      utf8.encode(password),
      CryptoUtil.base642bin(attributes.kekSalt),
      attributes.memLimit!,
      attributes.opsLimit!,
    );

    Uint8List key;
    try {
      // Decrypt the master key with the derived key
      key = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(attributes.encryptedKey),
        keyEncryptionKey,
        CryptoUtil.base642bin(attributes.keyDecryptionNonce),
      );
    } catch (e) {
      _logger.severe('master-key decryption failed', e);
      throw Exception("Incorrect password");
    }
    await setKey(CryptoUtil.bin2base64(key));
    final secretKey = CryptoUtil.decryptSync(
      CryptoUtil.base642bin(attributes.encryptedSecretKey),
      key,
      CryptoUtil.base642bin(attributes.secretKeyDecryptionNonce),
    );
    await setSecretKey(CryptoUtil.bin2base64(secretKey));
    final token = CryptoUtil.openSealSync(
      CryptoUtil.base642bin(getEncryptedToken()!),
      CryptoUtil.base642bin(attributes.publicKey),
      secretKey,
    );
    await setToken(CryptoUtil.bin2base64(token, urlSafe: true));
    return keyEncryptionKey;
  }

  Future<KeyAttributes> createNewRecoveryKey() async {
    final masterKey = getKey()!;
    final existingAttributes = getKeyAttributes();

    // Create a recovery key
    final recoveryKey = CryptoUtil.generateKey();

    // Encrypt master key and recovery key with each other
    final encryptedMasterKey = CryptoUtil.encryptSync(masterKey, recoveryKey);
    final encryptedRecoveryKey = CryptoUtil.encryptSync(recoveryKey, masterKey);

    return existingAttributes!.copyWith(
      masterKeyEncryptedWithRecoveryKey: CryptoUtil.bin2base64(
        encryptedMasterKey.encryptedData!,
      ),
      masterKeyDecryptionNonce: CryptoUtil.bin2base64(
        encryptedMasterKey.nonce!,
      ),
      recoveryKeyEncryptedWithMasterKey: CryptoUtil.bin2base64(
        encryptedRecoveryKey.encryptedData!,
      ),
      recoveryKeyDecryptionNonce: CryptoUtil.bin2base64(
        encryptedRecoveryKey.nonce!,
      ),
    );
  }

  Future<void> recover(String recoveryKey) async {
    // Legacy users will have recoveryKey in the form of a hex string, while
    // newer users will have it as a mnemonic code
    if (recoveryKey.contains(' ')) {
      // Check if user has entered a mnemonic code
      if (recoveryKey.split(' ').length != mnemonicKeyWordCount) {
        throw AssertionError(
          'recovery code should have $mnemonicKeyWordCount words',
        );
      }
      // Convert mnemonic code to hex
      recoveryKey = bip39.mnemonicToEntropy(recoveryKey);
    }
    final attributes = getKeyAttributes();
    Uint8List masterKey;
    try {
      // Decrypt the master key that was earlier encrypted with the recovery key
      masterKey = await CryptoUtil.decrypt(
        CryptoUtil.base642bin(attributes!.masterKeyEncryptedWithRecoveryKey!),
        CryptoUtil.hex2bin(recoveryKey),
        CryptoUtil.base642bin(attributes.masterKeyDecryptionNonce!),
      );
    } catch (e) {
      _logger.severe(e);
      rethrow;
    }
    await setKey(CryptoUtil.bin2base64(masterKey));
    final secretKey = CryptoUtil.decryptSync(
      CryptoUtil.base642bin(attributes.encryptedSecretKey),
      masterKey,
      CryptoUtil.base642bin(attributes.secretKeyDecryptionNonce),
    );
    await setSecretKey(CryptoUtil.bin2base64(secretKey));
    final token = CryptoUtil.openSealSync(
      CryptoUtil.base642bin(getEncryptedToken()!),
      CryptoUtil.base642bin(attributes.publicKey),
      secretKey,
    );
    await setToken(CryptoUtil.bin2base64(token, urlSafe: true));
  }

  String? getToken() {
    _cachedToken ??= _preferences.getString(tokenKey);
    return _cachedToken;
  }

  @override
  bool isLoggedIn() {
    return getToken() != null;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _preferences.setString(tokenKey, token);
    await localSettings.setAppMode(AppMode.enteGallery);
    Bus.instance.fire(AppModeChangedEvent());
    Bus.instance.fire(SignedInEvent());
  }

  Future<void> setEncryptedToken(String encryptedToken) async {
    await _preferences.setString(encryptedTokenKey, encryptedToken);
  }

  String? getEncryptedToken() {
    return _preferences.getString(encryptedTokenKey);
  }

  String? getEmail() {
    return _preferences.getString(emailKey);
  }

  Future<void> setEmail(String email) async {
    await _preferences.setString(emailKey, email);
  }

  int? getUserID() {
    return _preferences.getInt(userIDKey);
  }

  Future<void> setUserID(int userID) async {
    await _preferences.setInt(userIDKey, userID);
  }

  Future<void> setKeyAttributes(KeyAttributes attributes) async {
    await _preferences.setString(keyAttributesKey, attributes.toJson());
  }

  KeyAttributes? getKeyAttributes() {
    final jsonValue = _preferences.getString(keyAttributesKey);
    if (jsonValue == null) {
      return null;
    } else {
      return KeyAttributes.fromJson(jsonValue);
    }
  }

  @override
  String decryptDeleteChallenge(String encryptedChallenge) {
    final challenge = CryptoUtil.openSealSync(
      CryptoUtil.base642bin(encryptedChallenge),
      CryptoUtil.base642bin(getKeyAttributes()!.publicKey),
      getSecretKey()!,
    );
    return utf8.decode(challenge);
  }

  Future<void> setKey(String? key) async {
    _key = key;
    if (key == null) {
      // Used to clear key from secure storage
      await _secureStorage.delete(key: keyKey);
    } else {
      await _secureStorage.write(key: keyKey, value: key);
    }
  }

  Future<void> setSecretKey(String? secretKey) async {
    _secretKey = secretKey;
    if (secretKey == null) {
      // Used to clear secret key from secure storage
      await _secureStorage.delete(key: secretKeyKey);
    } else {
      await _secureStorage.write(key: secretKeyKey, value: secretKey);
    }
  }

  Uint8List? getKey() {
    return _key == null ? null : CryptoUtil.base642bin(_key!);
  }

  Uint8List? getSecretKey() {
    return _secretKey == null ? null : CryptoUtil.base642bin(_secretKey!);
  }

  Uint8List getRecoveryKey() {
    final keyAttributes = getKeyAttributes()!;
    return CryptoUtil.decryptSync(
      CryptoUtil.base642bin(keyAttributes.recoveryKeyEncryptedWithMasterKey!),
      getKey()!,
      CryptoUtil.base642bin(keyAttributes.recoveryKeyDecryptionNonce!),
    );
  }

  // Caution: This directory is cleared on app start
  String getTempDirectory() {
    return _tempDocumentsDirPath;
  }

  String getThumbnailCacheDirectory() {
    return _thumbnailCacheDirectory;
  }

  String getPersonFaceThumbnailCacheDirectory() {
    return _personFaceThumbnailCacheDirectory;
  }

  String getSharedMediaDirectory() {
    return _sharedDocumentsMediaDirectory;
  }

  bool hasConfiguredAccount() {
    return isLoggedIn() && _key != null;
  }

  void setVolatilePassword(String volatilePassword) {
    _volatilePassword = volatilePassword;
  }

  void resetVolatilePassword() {
    _volatilePassword = null;
  }

  String? getVolatilePassword() {
    return _volatilePassword;
  }

  Future<void> _migrateSecurityStorageToFirstUnlock() async {
    _logger.info(
      "(for debugging) Migrating secure storage to first unlock if needed",
    );
    final hasMigratedSecureStorage =
        _preferences.getBool(hasMigratedSecureStorageKey) ?? false;
    if (!hasMigratedSecureStorage && _key != null && _secretKey != null) {
      _logger.info("(for debugging) Migrating secure storage to first unlock");
      await _secureStorage.write(key: keyKey, value: _key);
      await _secureStorage.write(key: secretKeyKey, value: _secretKey);
      await _preferences.setBool(hasMigratedSecureStorageKey, true);
    }
    _logger.info("(for debugging) Migration check complete");
  }

  Future<String> _getOrCreateAnonymousUserID() async {
    if (!_preferences.containsKey(anonymousUserIDKey)) {
      //ignore: prefer_const_constructors
      await _preferences.setString(anonymousUserIDKey, Uuid().v4());
    }
    return _preferences.getString(anonymousUserIDKey)!;
  }
}
