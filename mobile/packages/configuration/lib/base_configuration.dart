import 'dart:convert';
import 'dart:io' as io;

import 'package:bip39/bip39.dart' as bip39;
import 'package:ente_base/models/database.dart';
import 'package:ente_base/models/key_attributes.dart';
import 'package:ente_base/models/key_gen_result.dart';
import 'package:ente_base/models/private_key_attributes.dart';
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
import 'package:tuple/tuple.dart';

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
  static const encryptedTokenKey = "encrypted_token";
  static const userIDKey = "user_id";
  static const endPointKey = "endpoint";
  static const lastTempFolderClearTimeKey = "last_temp_folder_clear_time";
  static const accountSecureStorageKeys = [keyKey, secretKeyKey];

  final kTempFolderDeletionTimeBuffer = const Duration(days: 1).inMicroseconds;

  static final _logger = Logger("Configuration");

  String? _cachedToken;
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

  Future<void> init(List<EnteBaseDatabase> dbs) async {
    _databases = dbs;
    _tempDocumentsDirPath =
        "${p.join((await getTemporaryDirectory()).path, "temp")}${p.separator}";
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
    await _preferences.clear();
    await resetSecureStorage();
    for (final db in _databases) {
      await db.clearTable();
    }
    _key = null;
    _cachedToken = null;
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
    final keyPair = CryptoUtil.generateKeyPair();
    final encryptedSecretKeyData = CryptoUtil.encryptSync(
      keyPair.secretKey,
      masterKey,
    );

    final attributes = KeyAttributes(
      CryptoUtil.bin2base64(kekSalt),
      CryptoUtil.bin2base64(encryptedKeyData.encryptedData!),
      CryptoUtil.bin2base64(encryptedKeyData.nonce!),
      CryptoUtil.bin2base64(keyPair.publicKey),
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
      CryptoUtil.bin2base64(keyPair.secretKey),
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
    _logger.info('Start decryptAndSaveSecrets');
    keyEncryptionKey ??= await CryptoUtil.deriveKey(
      utf8.encode(password),
      CryptoUtil.base642bin(attributes.kekSalt),
      attributes.memLimit,
      attributes.opsLimit,
    );

    _logger.info('user-key done');
    Uint8List key;
    try {
      key = CryptoUtil.decryptSync(
        CryptoUtil.base642bin(attributes.encryptedKey),
        keyEncryptionKey,
        CryptoUtil.base642bin(attributes.keyDecryptionNonce),
      );
    } catch (e) {
      _logger.severe('master-key failed, incorrect password?', e);
      throw Exception("Incorrect password");
    }
    _logger.info("master-key done");
    await setKey(CryptoUtil.bin2base64(key));
    final secretKey = CryptoUtil.decryptSync(
      CryptoUtil.base642bin(attributes.encryptedSecretKey),
      key,
      CryptoUtil.base642bin(attributes.secretKeyDecryptionNonce),
    );
    _logger.info("secret-key done");
    await setSecretKey(CryptoUtil.bin2base64(secretKey));
    final token = CryptoUtil.openSealSync(
      CryptoUtil.base642bin(getEncryptedToken()!),
      CryptoUtil.base642bin(attributes.publicKey),
      secretKey,
    );
    _logger.info('appToken done');
    await setToken(CryptoUtil.bin2base64(token, urlSafe: true));
    return keyEncryptionKey;
  }

  Future<void> recover(String recoveryKey) async {
    // check if user has entered mnemonic code
    if (recoveryKey.contains(' ')) {
      final split = recoveryKey.split(' ');
      if (split.length != mnemonicKeyWordCount) {
        String wordThatIsFollowedByEmptySpaceInSplit = '';
        for (int i = 0; i < split.length; i++) {
          final String word = split[i];
          if (word.isEmpty) {
            wordThatIsFollowedByEmptySpaceInSplit =
                '\n\nExtra space after word at position $i';
            break;
          }
        }
        throw AssertionError(
          '\nRecovery code should have $mnemonicKeyWordCount words, '
          'found ${split.length} words instead.$wordThatIsFollowedByEmptySpaceInSplit',
        );
      }
      recoveryKey = bip39.mnemonicToEntropy(recoveryKey);
    }
    final attributes = getKeyAttributes();
    Uint8List masterKey;
    try {
      masterKey = await CryptoUtil.decrypt(
        CryptoUtil.base642bin(attributes!.masterKeyEncryptedWithRecoveryKey),
        CryptoUtil.hex2bin(recoveryKey),
        CryptoUtil.base642bin(attributes.masterKeyDecryptionNonce),
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

  String getHttpEndpoint() {
    final savedEndpoint = _preferences.getString(endPointKey) ?? endpoint;
    if (savedEndpoint == kLegacyProductionEndpoint) {
      return kDefaultProductionEndpoint;
    }
    return savedEndpoint;
  }

  // isEnteProduction checks if the current endpoint is the default production
  // endpoint. This is used to determine if the app is in production mode or
  // not. The default production endpoint is set in the environment variable
  bool isEnteProduction() {
    return getHttpEndpoint() == kDefaultProductionEndpoint;
  }

  Future<void> setHttpEndpoint(String endpoint) async {
    await _preferences.setString(endPointKey, endpoint);
    Bus.instance.fire(EndpointUpdatedEvent());
  }

  String? getToken() {
    _cachedToken ??= _preferences.getString(tokenKey);
    return _cachedToken;
  }

  bool isLoggedIn() {
    return getToken() != null;
  }

  Future<void> setToken(String token) async {
    _cachedToken = token;
    await _preferences.setString(tokenKey, token);
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

  String decryptDeleteChallenge(String encryptedChallenge) {
    final challenge = CryptoUtil.openSealSync(
      CryptoUtil.base642bin(encryptedChallenge),
      CryptoUtil.base642bin(getKeyAttributes()!.publicKey),
      getSecretKey()!,
    );
    return utf8.decode(challenge);
  }

  Uint8List getRecoveryKey() {
    final keyAttributes = getKeyAttributes()!;
    return CryptoUtil.decryptSync(
      CryptoUtil.base642bin(keyAttributes.recoveryKeyEncryptedWithMasterKey),
      getKey()!,
      CryptoUtil.base642bin(keyAttributes.recoveryKeyDecryptionNonce),
    );
  }

  // Caution: This directory is cleared on app start
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
    try {
      if (!_preferences.containsKey(tokenKey)) {
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
