import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/network/network.dart';
import "package:photos/services/language_service.dart";
import 'package:photos/services/notification_service.dart';
import 'package:photos/ui/notification/update/change_log_strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ChangeLogAction { skip, consumeWithoutShowing, show }

class UpdateService {
  static const kUpdateAvailableShownTimeKey = "update_available_shown_time_key";
  static const _updateNotificationsEnabledKey = "update_notifications_enabled";
  static const changeLogVersionKey = "update_change_log_key";
  static const currentChangeLogVersion = 59;

  LatestVersionInfo? _latestVersion;
  final _logger = Logger("UpdateService");
  final PackageInfo _packageInfo;
  final SharedPreferences _prefs;

  UpdateService(SharedPreferences prefs, PackageInfo packageInfo)
    : _prefs = prefs,
      _packageInfo = packageInfo {
    debugPrint("UpdateService constructor");
  }

  Future<bool> shouldShowChangeLog() async {
    final lastShownAtVersion = _prefs.getInt(changeLogVersionKey);
    if (lastShownAtVersion == null) {
      // Fresh installs have no earlier version whose changelog should be shown.
      await hideChangeLog();
      return false;
    }
    return lastShownAtVersion < currentChangeLogVersion;
  }

  Future<ChangeLogAction> getChangeLogAction({
    required Locale locale,
    required bool isLocalGallery,
    required bool isSignedIn,
  }) async {
    if (!await shouldShowChangeLog()) {
      return ChangeLogAction.skip;
    }

    if (!(isLocalGallery || isSignedIn)) {
      return ChangeLogAction.skip;
    }

    return ChangeLogStrings.hasContentForLocale(
          locale,
          isLocalGallery: isLocalGallery,
        )
        ? ChangeLogAction.show
        : ChangeLogAction.consumeWithoutShowing;
  }

  Future<bool> hideChangeLog() async {
    return _prefs.setInt(changeLogVersionKey, currentChangeLogVersion);
  }

  Future<bool> shouldUpdate() async {
    _latestVersion = null;
    if (!isIndependent()) {
      return false;
    }
    try {
      _latestVersion = await _getLatestVersionInfo();
      final currentVersionCode = int.parse(_packageInfo.buildNumber);
      return currentVersionCode < _latestVersion!.code;
    } catch (e) {
      _logger.severe(e);
      return false;
    }
  }

  bool shouldForceUpdate(LatestVersionInfo info) {
    if (!isIndependent()) {
      return false;
    }
    try {
      final currentVersionCode = int.parse(_packageInfo.buildNumber);
      return currentVersionCode < info.lastSupportedVersionCode;
    } catch (e) {
      _logger.severe(e);
      return false;
    }
  }

  LatestVersionInfo? getLatestVersionInfo() {
    return _latestVersion;
  }

  bool get updateNotificationsEnabled =>
      _prefs.getBool(_updateNotificationsEnabledKey) ?? true;

  Future<void> setUpdateNotificationsEnabled(bool enabled) async {
    await _prefs.setBool(_updateNotificationsEnabledKey, enabled);
  }

  Future<bool> shouldShowUpdateNotification() async {
    final shouldUpdate = await this.shouldUpdate();

    if (!shouldUpdate || _latestVersion == null) {
      return false;
    }
    if (shouldForceUpdate(_latestVersion!)) {
      return true;
    }
    if (!updateNotificationsEnabled) {
      return false;
    }

    final lastNotificationShownTime =
        _prefs.getInt(kUpdateAvailableShownTimeKey) ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    final hasBeenThresholdDaysSinceLastNotification =
        (now - lastNotificationShownTime) >
        ((_latestVersion!.shouldNotify ? 1 : 3) * microSecondsInDay);

    return hasBeenThresholdDaysSinceLastNotification;
  }

  Future<void> showUpdateNotification() async {
    if (await shouldShowUpdateNotification()) {
      final s = await LanguageService.locals;
      // ignore: unawaited_futures
      NotificationService.instance.showNotification(
        s.updateAvailable,
        s.clickToInstallOurBestVersionYet,
      );
      await resetUpdateAvailableShownTime();
    } else {
      _logger.info("Debouncing notification");
    }
  }

  Future<void> resetUpdateAvailableShownTime() {
    return _prefs.setInt(
      kUpdateAvailableShownTimeKey,
      DateTime.now().microsecondsSinceEpoch,
    );
  }

  Future<LatestVersionInfo> _getLatestVersionInfo() async {
    final response = await NetworkClient.instance.getDio().get(
      "https://ente.com/release-info/independent.json",
    );
    return LatestVersionInfo.fromMap(response.data["latestVersion"]);
  }

  bool isIndependent() {
    if (Platform.isIOS) {
      return false;
    }
    if (!kDebugMode &&
        _packageInfo.packageName != "io.ente.photos.independent") {
      return false;
    }
    return true;
  }

  bool isIndependentFlavor() {
    if (Platform.isIOS) {
      return false;
    }
    return _packageInfo.packageName.startsWith("io.ente.photos.independent");
  }

  bool isFDroidFlavor() {
    if (Platform.isIOS) {
      return false;
    }
    return _packageInfo.packageName.startsWith("io.ente.photos.fdroid");
  }

  bool isPlayStoreFlavor() {
    if (Platform.isIOS) {
      return false;
    }
    return !isIndependentFlavor() && !isFDroidFlavor();
  }
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
