import 'dart:async';
import 'dart:typed_data';

import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_auth/core/app_wide_preferences.dart';
import 'package:ente_base/models/database.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Configuration extends BaseConfiguration
    implements LockScreenHost, AccountDeletionHost {
  Configuration._privateConstructor();

  static final Configuration instance = Configuration._privateConstructor();
  @override
  EnteAppIdentity get appIdentity => const EnteAppIdentity(
    app: "auth",
    clientPackageName: "io.ente.auth",
    passkeyRedirectUrl: "enteauth://passkey",
    referralSourcePrefix: "auth",
  );

  static const authSecretKeyKey = "auth_secret_key";
  static const offlineAuthSecretKey = "offline_auth_secret_key";
  static const hasOptedForOfflineModeKey = "has_opted_for_offline_mode";
  static const autoBackupPasswordKey = "autoBackupPassword";

  late SharedPreferences _preferences;
  String? _authSecretKey;
  String? _offlineAuthKey;
  late FlutterSecureStorage _secureStorage;

  @override
  Future<void> init(List<EnteBaseDatabase> dbs, {String scope = ""}) async {
    await super.init(dbs, scope: scope);
    _preferences = await SharedPreferences.getInstance();
    _secureStorage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
      ),
    );
    sqfliteFfiInit();
    await _initOfflineAccount();
    await _initOnlineAccount();
  }

  @override
  Future<void> setScope(String scope) async {
    if (scope == this.scope) return;
    _authSecretKey = null;
    _offlineAuthKey = null;
    await super.setScope(scope);
    await _initOfflineAccount();
    await _initOnlineAccount();
  }

  Future<void> _initOfflineAccount() async {
    _offlineAuthKey = await _secureStorage.read(
      key: scopedKey(offlineAuthSecretKey),
    );
  }

  Future<void> _initOnlineAccount() async {
    if (hasConfiguredAccount()) {
      _authSecretKey = await _secureStorage.read(
        key: scopedKey(authSecretKeyKey),
      );
    }
  }

  @override
  // This includes both base keys (key, secretKey) and auth-specific keys.
  List<String> get secureStorageKeys => [
    ...BaseConfiguration.accountSecureStorageKeys,
    authSecretKeyKey,
    // Note: offlineAuthSecretKey is intentionally not included here
    // as it persists across logouts for offline mode
  ];

  @override
  // The pre-existing profile stores its keys unprefixed, so its logout clears
  // preferences wholesale. These must survive it: other profiles' data, the
  // profile registry, the app wide lock screen state, and every app wide
  // setting (theme, language, local backup configuration) which is likewise
  // stored unprefixed and would otherwise be reset for the surviving profile.
  List<String> get logoutPreservedKeyPrefixes => const [
    "acct_",
    "profiles",
    "ls_",
    "should_show_lock_screen",
    ...kAppWidePreferenceKeys,
  ];

  // Only for prefixed scopes: the unprefixed profile's entries are cleared by
  // logout() via resetSecureStorage(), which keeps its offline key.
  Future<void> clearSecureStorageForScope(String scope) async {
    if (scope.isEmpty) {
      return;
    }
    final keys = {
      ...secureStorageKeys,
      offlineAuthSecretKey,
      autoBackupPasswordKey,
    };
    for (final key in keys) {
      await _secureStorage.delete(key: "$scope$key");
    }
  }

  @override
  Future<void> logout({bool autoLogout = false}) async {
    _authSecretKey = null;
    await super.logout();
  }

  Future<void> setAuthSecretKey(String? authSecretKey) async {
    _authSecretKey = authSecretKey;
    await _secureStorage.write(
      key: scopedKey(authSecretKeyKey),
      value: authSecretKey,
    );
  }

  Uint8List? getAuthSecretKey() {
    return _authSecretKey == null
        ? null
        : CryptoUtil.base642bin(_authSecretKey!);
  }

  Uint8List? getOfflineSecretKey() {
    return _offlineAuthKey == null
        ? null
        : CryptoUtil.base642bin(_offlineAuthKey!);
  }

  bool hasOptedForOfflineMode() {
    return _preferences.getBool(scopedKey(hasOptedForOfflineModeKey)) ?? false;
  }

  Future<void> optForOfflineMode() async {
    final key = scopedKey(offlineAuthSecretKey);
    if ((await _secureStorage.containsKey(key: key))) {
      _offlineAuthKey = await _secureStorage.read(key: key);
    } else {
      _offlineAuthKey = CryptoUtil.bin2base64(CryptoUtil.generateKey());
      await _secureStorage.write(key: key, value: _offlineAuthKey);
    }
    await _preferences.setBool(scopedKey(hasOptedForOfflineModeKey), true);
  }

  // Unlike logout(), which preserves the offline key, this is for a profile
  // being removed outright.
  Future<void> clearOfflineAccount() async {
    _offlineAuthKey = null;
    await _secureStorage.delete(key: scopedKey(offlineAuthSecretKey));
    await _preferences.remove(scopedKey(hasOptedForOfflineModeKey));
  }

  // Backup password methods
  Future<String?> getBackupPassword() async {
    return _secureStorage.read(key: scopedKey(autoBackupPasswordKey));
  }

  Future<void> setBackupPassword(String password) async {
    await _secureStorage.write(
      key: scopedKey(autoBackupPasswordKey),
      value: password,
    );
  }

  Future<void> clearBackupPassword() async {
    await _secureStorage.delete(key: scopedKey(autoBackupPasswordKey));
  }
}
