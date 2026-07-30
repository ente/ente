import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:ente_events/event_bus.dart";
import "package:ente_events/models/signed_out_event.dart";
import "package:ente_lock_screen/lock_screen_host.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_screen_cover/ente_screen_cover.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:local_auth/local_auth.dart";
import "package:shared_preferences/shared_preferences.dart";

class LockScreenSettings {
  LockScreenSettings._privateConstructor();

  static final LockScreenSettings instance =
      LockScreenSettings._privateConstructor();
  static const password = "ls_password";
  static const pin = "ls_pin";
  static const saltKey = "ls_salt";
  static const keyInvalidAttempts = "ls_invalid_attempts";
  static const lastInvalidAttemptTime = "ls_last_invalid_attempt_time";
  static const autoLockTime = "ls_auto_lock_time";
  static const keyHideAppContent = "ls_hide_app_content";
  static const keyAppLockSet = "ls_is_app_lock_set";
  static const keyHasMigratedLockScreenChanges =
      "ls_has_migrated_lock_screen_changes";
  static const keyShowOfflineModeWarning = "ls_show_offline_mode_warning";
  static const keyShouldShowLockScreen = "should_show_lock_screen";
  static const String kIsLightMode = "is_light_mode";

  final List<Duration> autoLockDurations = const [
    Duration(milliseconds: 650),
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 30),
  ];

  late LockScreenHost _config;
  late SharedPreferences _preferences;
  late FlutterSecureStorage _secureStorage;
  bool _useLegacyHashFallback = false;
  bool _hideAppContentDefault = false;
  String _appLogoAsset = 'assets/svg/app-logo.svg';
  double? _appLogoHeight;

  Future<void> init(
    LockScreenHost config, {
    bool hasOptedForOfflineMode = false,
    bool useLegacyHashFallback = false,
    bool hideAppContentDefault = false,
    String appLogoAsset = 'assets/svg/app-logo.svg',
    double? appLogoHeight,
  }) async {
    _config = config;
    _useLegacyHashFallback = useLegacyHashFallback;
    _hideAppContentDefault = hideAppContentDefault;
    _appLogoAsset = appLogoAsset;
    _appLogoHeight = appLogoHeight;
    _secureStorage = const FlutterSecureStorage();
    _preferences = await SharedPreferences.getInstance();

    ///Workaround for privacyScreen not working when app is killed and opened.
    await setHideAppContent(getShouldHideAppContent());

    /// Function to Check if the migration for lock screen changes has
    /// already been done by checking a stored boolean value.
    await runLockScreenChangesMigration();

    await _clearLsDataInKeychainIfFreshInstall(hasOptedForOfflineMode);

    Bus.instance.on<SignedOutEvent>().listen((event) {
      removePinAndPassword();
    });
  }

  Future<void> setOfflineModeWarningStatus(bool value) async {
    await _preferences.setBool(keyShowOfflineModeWarning, value);
  }

  bool getOfflineModeWarningStatus() {
    return _preferences.getBool(keyShowOfflineModeWarning) ?? true;
  }

  Future<void> runLockScreenChangesMigration() async {
    if (_preferences.getBool(keyHasMigratedLockScreenChanges) != null) {
      return;
    }

    final bool passwordEnabled = await isPasswordSet();
    final bool pinEnabled = await isPinSet();
    final bool systemLockEnabled = shouldShowSystemLockScreen();

    if (passwordEnabled || pinEnabled || systemLockEnabled) {
      await setAppLockEnabled(true);
    }

    await _preferences.setBool(keyHasMigratedLockScreenChanges, true);
  }

  Future<void> setLightMode(bool isLightMode) async {
    if (isLightMode != (_preferences.getBool(kIsLightMode) ?? true)) {
      await _preferences.setBool(kIsLightMode, isLightMode);
    }
  }

  Future<void> setHideAppContent(
    bool hideContent, {
    bool persist = true,
  }) async {
    if (PlatformDetector.isDesktop()) return;
    !hideContent ? EnteScreenCover.disable() : await EnteScreenCover.enable();
    if (persist) {
      await _preferences.setBool(keyHideAppContent, hideContent);
    }
  }

  bool getShouldHideAppContent() {
    return _preferences.getBool(keyHideAppContent) ?? _hideAppContentDefault;
  }

  Future<void> setAutoLockTime(Duration duration) async {
    await _preferences.setInt(autoLockTime, duration.inMilliseconds);
  }

  int getAutoLockTime() {
    return _preferences.getInt(autoLockTime) ?? 5000;
  }

  Future<void> setLastInvalidAttemptTime(int time) async {
    await _preferences.setInt(lastInvalidAttemptTime, time);
  }

  int getlastInvalidAttemptTime() {
    return _preferences.getInt(lastInvalidAttemptTime) ?? 0;
  }

  int getInvalidAttemptCount() {
    return _preferences.getInt(keyInvalidAttempts) ?? 0;
  }

  Future<void> setInvalidAttemptCount(int count) async {
    await _preferences.setInt(keyInvalidAttempts, count);
  }

  Future<void> setAppLockEnabled(bool value) async {
    await _preferences.setBool(keyAppLockSet, value);
  }

  bool getIsAppLockSet() {
    return _preferences.getBool(keyAppLockSet) ?? false;
  }

  static Uint8List _generateSalt() {
    return CryptoUtil.getSaltToDeriveKey();
  }

  Future<void> setPin(String userPin) async {
    await _secureStorage.delete(key: saltKey);
    final salt = _generateSalt();

    final hash = CryptoUtil.cryptoPwHash(
      utf8.encode(userPin),
      salt,
      CryptoUtil.pwhashMemLimitInteractive,
      CryptoUtil.pwhashOpsLimitSensitive,
    );
    final String saltPin = base64Encode(salt);
    final String hashedPin = base64Encode(hash);

    await _secureStorage.write(key: saltKey, value: saltPin);
    await _secureStorage.write(key: pin, value: hashedPin);
    await _secureStorage.delete(key: password);

    return;
  }

  Future<Uint8List?> getSalt() async {
    final String? salt = await _secureStorage.read(key: saltKey);
    if (salt == null) return null;
    return base64Decode(salt);
  }

  Future<String?> getPin() async {
    return _secureStorage.read(key: pin);
  }

  Future<void> setPassword(String pass) async {
    await _secureStorage.delete(key: saltKey);
    final salt = _generateSalt();

    final hash = CryptoUtil.cryptoPwHash(
      utf8.encode(pass),
      salt,
      CryptoUtil.pwhashMemLimitInteractive,
      CryptoUtil.pwhashOpsLimitSensitive,
    );

    await _secureStorage.write(key: saltKey, value: base64Encode(salt));
    await _secureStorage.write(key: password, value: base64Encode(hash));
    await _secureStorage.delete(key: pin);

    return;
  }

  Future<String?> getPassword() async {
    return _secureStorage.read(key: password);
  }

  bool get useLegacyHashFallback => _useLegacyHashFallback;

  String get appLogoAsset => _appLogoAsset;

  double? get appLogoHeight => _appLogoHeight;

  /// Verifies that the hash of [text] matches [storedHash].
  Future<bool> verify({
    required String text,
    required String? storedHash,
  }) async {
    if (storedHash == null) return false;
    final Uint8List? salt = await getSalt();
    if (salt == null) return false;
    final hash = base64Encode(
      CryptoUtil.cryptoPwHash(
        utf8.encode(text),
        salt,
        CryptoUtil.pwhashMemLimitInteractive,
        CryptoUtil.pwhashOpsLimitSensitive,
      ),
    );
    return hash == storedHash;
  }

  /// Like [verify], but for secrets created by photos' lock screen.
  ///
  /// On a miss it retries with photos' legacy (Interactive ops) parameters and,
  /// on a hit, upgrades the stored hash to the current parameters under
  /// [storageKey]. The re-store is best-effort, so a correct secret is never
  /// rejected.
  Future<bool> verifyWithLegacyFallback({
    required String text,
    required String? storedHash,
    required String storageKey,
  }) async {
    if (await verify(text: text, storedHash: storedHash)) return true;
    if (storedHash == null) return false;
    final Uint8List? salt = await getSalt();
    if (salt == null) return false;
    final secret = utf8.encode(text);

    final legacy = base64Encode(
      CryptoUtil.cryptoPwHash(
        secret,
        salt,
        CryptoUtil.pwhashMemLimitInteractive,
        CryptoUtil.pwhashOpsLimitInteractive,
      ),
    );
    if (legacy != storedHash) return false;

    final upgraded = base64Encode(
      CryptoUtil.cryptoPwHash(
        secret,
        salt,
        CryptoUtil.pwhashMemLimitInteractive,
        CryptoUtil.pwhashOpsLimitSensitive,
      ),
    );
    try {
      await _secureStorage.write(key: storageKey, value: upgraded);
    } catch (_) {}
    return true;
  }

  Future<void> removePinAndPassword() async {
    await _secureStorage.delete(key: saltKey);
    await _secureStorage.delete(key: pin);
    await _secureStorage.delete(key: password);
  }

  Future<bool> isPinSet() async {
    return await _secureStorage.containsKey(key: pin);
  }

  Future<bool> isPasswordSet() async {
    return await _secureStorage.containsKey(key: password);
  }

  Future<bool> shouldShowLockScreen() async {
    final bool isPin = await isPinSet();
    final bool isPass = await isPasswordSet();
    return isPin || isPass || shouldShowSystemLockScreen();
  }

  bool shouldShowSystemLockScreen() {
    if (_preferences.containsKey(keyShouldShowLockScreen)) {
      return _preferences.getBool(keyShouldShowLockScreen)!;
    } else {
      return false;
    }
  }

  Future<void> setSystemLockScreen(bool value) {
    return _preferences.setBool(keyShouldShowLockScreen, value);
  }

  // If the app was uninstalled (without logging out if it was used with
  // backups), keychain items of the app persist in the keychain. To avoid using
  // old keychain items, we delete them on reinstall.
  Future<void> _clearLsDataInKeychainIfFreshInstall(
    bool hasOptedForOfflineMode,
  ) async {
    if ((Platform.isIOS || Platform.isMacOS) &&
        !_config.isLoggedIn() &&
        !hasOptedForOfflineMode) {
      await _secureStorage.delete(key: password);
      await _secureStorage.delete(key: pin);
      await _secureStorage.delete(key: saltKey);
    }
  }

  Future<bool> isDeviceSupported() async {
    return await LocalAuthentication().isDeviceSupported();
  }
}
