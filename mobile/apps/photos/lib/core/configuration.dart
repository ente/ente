import "dart:async";
import "dart:io";

import 'package:backup_exclusion/backup_exclusion.dart';
import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_contacts/contacts.dart';
import "package:ente_crypto/ente_crypto.dart";
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
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
import "package:photos/db/social_db.dart";
import 'package:photos/db/trash_db.dart';
import 'package:photos/db/upload_locks_db.dart';
import "package:photos/events/app_mode_changed_event.dart";
import 'package:photos/events/signed_in_event.dart';
import 'package:photos/events/user_logged_out_event.dart';
import 'package:photos/gateways/users/models/key_attributes.dart';
import 'package:photos/module/upload/upload_artifact.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/authenticated_session.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/favorites_service.dart';
import "package:photos/services/home_widget_service.dart";
import 'package:photos/services/ignored_files_service.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/machine_learning/similar_images_service.dart";
import "package:photos/services/memory_share_service.dart";
import 'package:photos/services/notification_key_service.dart';
import "package:photos/services/notification_service.dart";
import 'package:photos/services/photos_contacts_service.dart';
import 'package:photos/services/search_service.dart';
import 'package:photos/services/sync/sync_service.dart';
import 'package:photos/services/video_preview_service.dart';
import 'package:photos/src/rust/third_party/ente_frb_lib/account_deletion.dart'
    as account_deletion;
import 'package:shared_preferences/shared_preferences.dart';
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
  static const hasSecureTokenKey = "has_secure_token";
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
      // Exclude Documents (SQLite, thumbnails, decrypted media) and Application
      // Support (ML models) from backups. They are server-derivable or must
      // remain within the device's E2EE boundary.
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
      _cachedToken = _preferences.getString(tokenKey);
      if (_cachedToken != null) {
        try {
          final storedToken = _preferences.containsKey(hasSecureTokenKey)
              ? await _secureStorage.read(key: tokenKey)
              : null;
          if (storedToken == _cachedToken) {
            await _preferences.remove(tokenKey);
          } else {
            await _storeTokenSecurely(_cachedToken!);
          }
        } catch (e, s) {
          _logger.warning("Failed to move token to secure storage", e, s);
        }
      } else if (_preferences.containsKey(hasSecureTokenKey)) {
        try {
          _cachedToken = await _secureStorage.read(key: tokenKey);
        } on PlatformException catch (e, s) {
          _logger.warning("Failed to read token from secure storage", e, s);
          await _secureStorage.read(key: keyKey);
          try {
            _cachedToken = await _secureStorage.read(key: tokenKey);
          } on PlatformException catch (e, s) {
            _logger.warning("Token is unreadable in secure storage", e, s);
          }
        }
        if (_cachedToken == null) {
          _logger.warning("No token found in secure storage");
          await logout(autoLogout: true);
        }
      }
      if (_cachedToken == null) {
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
      // BadPaddingException can mean Android secure storage is inaccessible.
      // https://github.com/mogol/flutter_secure_storage/issues/541
      if (e is PlatformException) {
        final PlatformException error = e;
        if (error.code == 'notification_key_store') {
          rethrow;
        }
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

  // Leave upload artifacts for FileUploader to resume or delete.
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
    MLService.instance.stopActiveRun(MlStopReason.logout);
    if (!autoLogout) {
      VideoPreviewService.instance.stop('logout');
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

    if (Platform.isIOS) {
      try {
        await NotificationKeyService.setNotificationPrivateKey(null);
      } on PlatformException catch (e, s) {
        if (e.code != 'notification_key_store') rethrow;
        _logger.warning("Could not delete notification key", e, s);
      }
    }
    await _clearTempFolderOnLogout();

    _cachedToken = null;
    await _preferences.clear();
    await _secureStorage.deleteAll();
    _key = null;
    _secretKey = null;
    _volatilePassword = null;
    clearAuthenticatedSession();

    await NotificationService.instance.clearAllScheduledNotifications(
      logLines: false,
    );

    await FilesDB.instance.clearTable();
    await GalleryDownloadsDB.instance.clearTable();
    await CollectionsDB.instance.clearTable();
    await MemoriesDB.instance.clearTable();
    await MemorySharesDB.instance.clearTable();
    await MLDataDB.instance.clearTable();
    await UploadLocksDB.instance.clearTable();
    await TrashDB.instance.clearTable();
    try {
      await PhotosContactsService.instance.close().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      _logger.warning("Failed to close contacts service", e);
    }
    await ContactsDatabase().clearTable();
    await SocialDB.instance.clearAllData();

    ThumbnailInMemoryLruCache.clearAll();
    FileLruCache.clearAll();

    try {
      await DefaultCacheManager().emptyCache();
    } catch (e) {
      _logger.warning("Failed to clear image cache", e);
    }

    try {
      await VideoCacheManager.instance.emptyCache();
    } catch (e) {
      _logger.warning("Failed to clear video cache", e);
    }

    await SimilarImagesService.instance.clearCache();
    await IgnoredFilesService.instance.reset();
    unawaited(HomeWidgetService.instance.clearWidget(autoLogout));
    MemoryShareService.instance.clearCache();

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
      // Auto logout can run before these services are initialized.
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

  Future<void> _clearTempFolderOnLogout() async {
    try {
      await deleteDirectoryContents(_tempDocumentsDirPath);
      await Directory(_tempDocumentsDirPath).create(recursive: true);
      _logger.info("Cleared temp folder on logout");
    } catch (e, s) {
      _logger.warning("Failed to clear temp folder on logout", e, s);
    }
  }

  bool showAutoLogoutDialog() {
    return _preferences.containsKey("auto_logout");
  }

  Future<bool> clearAutoLogoutFlag() {
    return _preferences.remove("auto_logout");
  }

  Future<KeyAttributes> createNewRecoveryKey() async {
    final masterKey = getKey()!;
    final existingAttributes = getKeyAttributes();

    final recoveryKey = CryptoUtil.generateKey();
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

  String? getToken() {
    return _cachedToken;
  }

  @override
  bool isLoggedIn() {
    return getToken() != null;
  }

  Future<void> setToken(String token) async {
    await _storeTokenSecurely(token);
    await _preferences.remove(tokenKey);
    _cachedToken = token;
    await localSettings.setAppMode(AppMode.enteGallery);
    Bus.instance.fire(AppModeChangedEvent());
    Bus.instance.fire(SignedInEvent());
  }

  Future<void> _storeTokenSecurely(String token) async {
    await _secureStorage.write(key: tokenKey, value: token);
    if (await _secureStorage.read(key: tokenKey) != token) {
      throw StateError("Token was not saved to secure storage");
    }
    await _preferences.setBool(hasSecureTokenKey, true);
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
  Future<AccountDeletionSummary?> getDeletionSummary() =>
      account_deletion.getDeletionSummary(session: authenticatedSession());

  @override
  Future<String> getDeleteChallenge() =>
      account_deletion.getDeleteChallenge(session: authenticatedSession());

  @override
  Future<void> deleteAccount({
    required String encryptedChallenge,
    required String reason,
    String? feedback,
  }) => account_deletion.deleteAccount(
    session: authenticatedSession(),
    encryptedChallenge: encryptedChallenge,
    reason: reason,
    feedback: feedback,
  );

  Future<void> setKey(String? key) async {
    _key = key;
    if (key == null) {
      await _secureStorage.delete(key: keyKey);
    } else {
      await _secureStorage.write(key: keyKey, value: key);
    }
  }

  Future<void> setSecretKey(String? secretKey) async {
    _secretKey = secretKey;
    if (secretKey == null) {
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
