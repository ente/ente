import "dart:io";

import "package:ente_network/network.dart";
import "package:flutter/foundation.dart";
import "package:locker/core/constants.dart";
import "package:logging/logging.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";

class UpdateService {
  UpdateService._privateConstructor();

  static final UpdateService instance = UpdateService._privateConstructor();
  static const String kUpdateAvailableShownTimeKey =
      "update_available_shown_time_key";
  static const String kChangeLogShownVersionKey = "update_change_log_key";
  static const int currentChangeLogVersion = 1;
  static const String _lockerIndependentPackageName =
      "io.ente.locker.independent";
  static const String _lockerIndependentPackagePrefix =
      "io.ente.locker.independent";
  static const String _lockerFDroidPackagePrefix = "io.ente.locker.fdroid";
  static const String _releaseInfoUrl = String.fromEnvironment(
    "locker.release_info_url",
    defaultValue: "https://ente.com/release-info/locker-independent.json",
  );

  final _logger = Logger("UpdateService");

  SharedPreferences? _prefs;
  PackageInfo? _packageInfo;
  LatestVersionInfo? _latestVersion;

  Future<void> init(SharedPreferences prefs, PackageInfo packageInfo) async {
    _prefs = prefs;
    _packageInfo = packageInfo;
  }

  Future<bool> shouldUpdate() async {
    if (!_isInitialized || !isIndependent()) {
      return false;
    }
    _latestVersion = null;
    try {
      _latestVersion = await _getLatestVersionInfo();
      final currentVersionCode = int.tryParse(_packageInfo!.buildNumber) ?? 0;
      return currentVersionCode < _latestVersion!.code;
    } catch (e, s) {
      _logger.severe("Failed to check for app updates", e, s);
      return false;
    }
  }

  bool shouldForceUpdate(LatestVersionInfo? info) {
    if (!_isInitialized || !isIndependent() || info == null) {
      return false;
    }
    try {
      final currentVersionCode = int.tryParse(_packageInfo!.buildNumber) ?? 0;
      return currentVersionCode < info.lastSupportedVersionCode;
    } catch (e, s) {
      _logger.severe("Failed to determine force-update status", e, s);
      return false;
    }
  }

  LatestVersionInfo? getLatestVersionInfo() {
    return _latestVersion;
  }

  Future<bool> shouldShowUpdateNotification() async {
    if (!_isInitialized || !isIndependent()) {
      return false;
    }

    final shouldUpdate = await this.shouldUpdate();
    if (!shouldUpdate || _latestVersion == null) {
      return false;
    }

    final lastNotificationShownTime =
        _prefs!.getInt(kUpdateAvailableShownTimeKey) ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    final thresholdInDays = _latestVersion!.shouldNotify ? 1 : 3;
    final hasExceededThreshold =
        (now - lastNotificationShownTime) >
        (thresholdInDays * microSecondsInDay);

    return hasExceededThreshold;
  }

  Future<void> markUpdateNotificationShown() async {
    if (!_isInitialized) return;
    await _prefs!.setInt(
      kUpdateAvailableShownTimeKey,
      DateTime.now().microsecondsSinceEpoch,
    );
  }

  Future<bool> shouldShowChangeLog() async {
    if (!_isInitialized) {
      return false;
    }
    final lastShownVersion = _prefs!.getInt(kChangeLogShownVersionKey);
    if (lastShownVersion == null) {
      await markChangeLogShown();
      return false;
    }
    return lastShownVersion < currentChangeLogVersion;
  }

  Future<void> markChangeLogShown() async {
    if (!_isInitialized) return;
    await _prefs!.setInt(kChangeLogShownVersionKey, currentChangeLogVersion);
  }

  Future<void> resetChangeLogShown() async {
    if (!_isInitialized) return;
    await _prefs!.remove(kChangeLogShownVersionKey);
  }

  bool isIndependent() {
    if (!_isInitialized) {
      return false;
    }
    if (Platform.isIOS) {
      return false;
    }
    if (kDebugMode) {
      return true;
    }
    return _packageInfo!.packageName == _lockerIndependentPackageName;
  }

  bool isIndependentFlavor() {
    if (!_isInitialized || Platform.isIOS) {
      return false;
    }
    return _packageInfo!.packageName.startsWith(
      _lockerIndependentPackagePrefix,
    );
  }

  bool isFDroidFlavor() {
    if (!_isInitialized || Platform.isIOS) {
      return false;
    }
    return _packageInfo!.packageName.startsWith(_lockerFDroidPackagePrefix);
  }

  bool isPlayStoreFlavor() {
    if (!_isInitialized || Platform.isIOS) {
      return false;
    }
    return !isIndependentFlavor() && !isFDroidFlavor();
  }

  Future<LatestVersionInfo> _getLatestVersionInfo() async {
    final response = await Network.instance.getDio().get(_releaseInfoUrl);
    final latestVersion = Map<String, dynamic>.from(
      response.data["latestVersion"],
    );
    return LatestVersionInfo.fromMap(latestVersion);
  }

  bool get _isInitialized => _prefs != null && _packageInfo != null;
}

class LatestVersionInfo {
  final String name;
  final int code;
  final List<String> changelog;
  final bool shouldForceUpdate;
  final int lastSupportedVersionCode;
  final String url;
  final int size;
  final bool shouldNotify;

  LatestVersionInfo(
    this.name,
    this.code,
    this.changelog,
    this.shouldForceUpdate,
    this.lastSupportedVersionCode,
    this.url,
    this.size,
    this.shouldNotify,
  );

  factory LatestVersionInfo.fromMap(Map<String, dynamic> map) {
    return LatestVersionInfo(
      map['name'],
      map['code'],
      List<String>.from(map['changelog']),
      map['shouldForceUpdate'],
      map['lastSupportedVersionCode'] ?? 1,
      map['url'],
      map['size'],
      map['shouldNotify'],
    );
  }
}
