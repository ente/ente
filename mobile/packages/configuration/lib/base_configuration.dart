import 'dart:io' as io;

import 'package:ente_base/models/database.dart';
import 'package:ente_base/models/key_attributes.dart';
import 'package:ente_configuration/app_identity.dart';
import 'package:ente_configuration/constants.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/endpoint_updated_event.dart';
import 'package:ente_events/models/signed_in_event.dart';
import 'package:ente_events/models/signed_out_event.dart';
import 'package:ente_logging/logging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'package:ente_configuration/app_identity.dart';

abstract class BaseConfiguration {
  static const endpoint = String.fromEnvironment(
    "endpoint",
    defaultValue: kDefaultProductionEndpoint,
  );
  static const emailKey = "email";
  static const keyAttributesKey = "key_attributes";
  static const keyKey = "key";
  static const secretKeyKey = "secret_key";
  static const tokenKey = "token";
  static const hasSecureTokenKey = "has_secure_token";
  static const encryptedTokenKey = "encrypted_token";
  static const userIDKey = "user_id";
  static const endPointKey = "endpoint";
  static const lastTempFolderClearTimeKey = "last_temp_folder_clear_time";
  static const accountSecureStorageKeys = [keyKey, secretKeyKey, tokenKey];

  final kTempFolderDeletionTimeBuffer = const Duration(days: 1).inMicroseconds;

  static final _logger = Logger("Configuration");

  String? _cachedToken;
  bool _isTokenUnavailable = false;
  late SharedPreferences _preferences;
  String? _key;
  String? _secretKey;
  late FlutterSecureStorage _secureStorage;
  late String _cacheDirectory;
  late String _tempDocumentsDirPath;
  late List<EnteBaseDatabase> _databases;

  String? _volatilePassword;

  EnteAppIdentity get appIdentity;

  List<String> get secureStorageKeys;

  String recoveryKeyToMnemonic(String recoveryKeyHex);

  List<String> get lockScreenSecureStorageKeys => const [];

  Future<void> init(List<EnteBaseDatabase> dbs) async {
    _databases = dbs;
    _tempDocumentsDirPath =
        "${p.join((await getApplicationCacheDirectory()).path, "temp")}${p.separator}";
    _preferences = await SharedPreferences.getInstance();
    _secureStorage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    // Set up folders before keys so the cache directory is initialized before
    // _setupKeys() can trigger an auto-logout whose cleanup needs it.
    await _setupFolders();
    await _setupKeys();
    _logger.info("User ID: ${getUserID()}");
  }

  Future<void> logout({bool autoLogout = false}) async {
    await _clearTempFolderOnLogout();
    _cachedToken = null;
    _isTokenUnavailable = false;
    await _preferences.clear();
    await resetSecureStorage();
    for (final key in lockScreenSecureStorageKeys) {
      await _secureStorage.delete(key: key);
    }
    for (final db in _databases) {
      await db.clearTable();
    }
    _key = null;
    _secretKey = null;
    Bus.instance.fire(SignedOutEvent());
  }

  Future<void> _clearTempFolderOnLogout() async {
    final tempDirectory = io.Directory(_tempDocumentsDirPath);
    try {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
      await tempDirectory.create(recursive: true);
      _logger.info("Cleared temp folder on logout");
    } catch (e, s) {
      _logger.warning("Failed to clear temp folder on logout", e, s);
    }
  }

  Future<void> resetSecureStorage() async {
    assert(
      secureStorageKeys.isNotEmpty,
      'secureStorageKeys must not be empty. Apps must explicitly define which keys to clear.',
    );
    for (final key in secureStorageKeys.toSet()) {
      await _secureStorage.delete(key: key);
    }
  }

  String getHttpEndpoint() {
    final savedEndpoint = _preferences.getString(endPointKey) ?? endpoint;
    if (savedEndpoint == kLegacyProductionEndpoint) {
      return kDefaultProductionEndpoint;
    }
    return savedEndpoint;
  }

  bool isEnteProduction() {
    return getHttpEndpoint() == kDefaultProductionEndpoint;
  }

  Future<void> setHttpEndpoint(String endpoint) async {
    await _preferences.setString(endPointKey, endpoint);
    Bus.instance.fire(EndpointUpdatedEvent());
  }

  String? getToken() {
    return _cachedToken;
  }

  bool isLoggedIn() {
    return getToken() != null || _isTokenUnavailable;
  }

  Future<void> setToken(String token) async {
    await _storeTokenSecurely(token);
    await _preferences.remove(tokenKey);
    _cachedToken = token;
    _isTokenUnavailable = false;
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

  Future<void> setKey(String key) async {
    _key = key;
    await _secureStorage.write(key: keyKey, value: key);
  }

  Future<void> setSecretKey(String? secretKey) async {
    _secretKey = secretKey;
    await _secureStorage.write(key: secretKeyKey, value: secretKey);
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
      CryptoUtil.base642bin(keyAttributes.recoveryKeyEncryptedWithMasterKey),
      getKey()!,
      CryptoUtil.base642bin(keyAttributes.recoveryKeyDecryptionNonce),
    );
  }

  // This directory is cleared on app start.
  String getTempDirectory() {
    return _tempDocumentsDirPath;
  }

  String getCacheDirectory() {
    return _cacheDirectory;
  }

  bool hasConfiguredAccount() {
    return getToken() != null && _key != null;
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

  Future<void> _setupKeys() async {
    _isTokenUnavailable = false;
    try {
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
          _isTokenUnavailable = true;
          await _secureStorage.read(key: keyKey);
          _isTokenUnavailable = false;
          try {
            _cachedToken = await _secureStorage.read(key: tokenKey);
          } on PlatformException catch (e, s) {
            _logger.warning("Token is unreadable in secure storage", e, s);
          }
        }
        if (_cachedToken == null) {
          _logger.warning("No token found in secure storage");
          await logout(autoLogout: true);
          return;
        }
      } else {
        await resetSecureStorage();
        return;
      }
      _key = await _secureStorage.read(key: keyKey);
      if (_key == null) {
        _logger.warning("No key found in secure storage");
        await logout(autoLogout: true);
      }
      _secretKey = await _secureStorage.read(key: secretKeyKey);
    } catch (e, s) {
      _logger.severe("Configuration init failed", e, s);
      // BadPaddingException can mean Android secure storage is inaccessible.
      // https://github.com/mogol/flutter_secure_storage/issues/541
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

  Future<void> _setupFolders() async {
    final tempDirectory = io.Directory(_tempDocumentsDirPath);
    try {
      final currentTime = DateTime.now().microsecondsSinceEpoch;
      if (tempDirectory.existsSync() &&
          (_preferences.getInt(lastTempFolderClearTimeKey) ?? 0) <
              (currentTime - kTempFolderDeletionTimeBuffer)) {
        await tempDirectory.delete(recursive: true);
        await _preferences.setInt(lastTempFolderClearTimeKey, currentTime);
        _logger.info("Cleared temp folder");
      } else {
        _logger.info("Skipping temp folder clear");
      }
    } catch (e) {
      _logger.warning(e);
    }
    tempDirectory.createSync(recursive: true);

    _cacheDirectory =
        "${p.join(p.dirname(_tempDocumentsDirPath), "cache")}${p.separator}";
    if (!io.Directory(_cacheDirectory).existsSync()) {
      io.Directory(_cacheDirectory).createSync(recursive: true);
    }
  }
}
