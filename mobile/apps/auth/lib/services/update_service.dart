import 'dart:async';
import 'dart:io';

import 'package:ente_auth/core/constants.dart';
import 'package:ente_auth/services/notification_service.dart';
import 'package:ente_network/network.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/services.dart' show appFlavor;
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UpdateService {
  UpdateService._privateConstructor();

  static final UpdateService instance = UpdateService._privateConstructor();
  static const kUpdateAvailableShownTimeKey = "update_available_shown_time_key";
  static const _updateNotificationsEnabledKey = "update_notifications_enabled";

  LatestVersionInfo? _latestVersion;
  final _logger = Logger("UpdateService");
  late PackageInfo _packageInfo;
  late SharedPreferences _prefs;

  Future<void> init() async {
    _packageInfo = await PackageInfo.fromPlatform();
    _prefs = await SharedPreferences.getInstance();
  }

  Future<bool> shouldUpdate() async {
    _latestVersion = null;
    if (!supportsInAppUpdates()) {
      return false;
    }
    try {
      _latestVersion = await _getLatestVersionInfo();
      final currentVersionCode = int.parse(_packageInfo.buildNumber);
      return currentVersionCode < _latestVersion!.code!;
    } catch (e) {
      _logger.severe(e);
      return false;
    }
  }

  bool shouldForceUpdate(LatestVersionInfo? info) {
    if (!supportsInAppUpdates()) {
      return false;
    }
    try {
      final currentVersionCode = int.parse(_packageInfo.buildNumber);
      return currentVersionCode < info!.lastSupportedVersionCode;
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

  Future<bool> shouldShowUpdatePrompt() async {
    if (!await shouldUpdate()) {
      return false;
    }
    final isCritical = shouldForceUpdate(_latestVersion);
    return isCritical || _shouldShowNotification(isCritical: false);
  }

  Future<void> showUpdateNotification() async {
    if (!await shouldUpdate()) {
      return;
    }
    final isCritical = shouldForceUpdate(_latestVersion);
    if (!_shouldShowNotification(isCritical: isCritical)) {
      _logger.info("Debouncing notification");
      return;
    }
    final now = DateTime.now().microsecondsSinceEpoch;
    await _prefs.setInt(kUpdateAvailableShownTimeKey, now);
    if (Platform.isAndroid) {
      unawaited(
        NotificationService.instance.showNotification(
          "Update available",
          "Click to install our best version yet",
        ),
      );
    }
  }

  bool _shouldShowNotification({required bool isCritical}) {
    if (!isCritical && !updateNotificationsEnabled) {
      return false;
    }
    final lastNotificationShownTime =
        _prefs.getInt(kUpdateAvailableShownTimeKey) ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    final hasBeen3DaysSinceLastNotification =
        (now - lastNotificationShownTime) > (3 * microSecondsInDay);
    return hasBeen3DaysSinceLastNotification &&
        (isCritical || _latestVersion!.shouldNotify!);
  }

  Future<LatestVersionInfo> _getLatestVersionInfo() async {
    final response = await Network.instance.getDio().get(
      "https://ente.com/release-info/auth-independent.json",
    );
    return LatestVersionInfo.fromMap(response.data["latestVersion"]);
  }

  bool supportsInAppUpdates() {
    return appFlavor == "independent" || PlatformDetector.isDesktop();
  }
}

class LatestVersionInfo {
  final String? name;
  final int? code;
  final List<String> changelog;
  final bool? shouldForceUpdate;
  final int lastSupportedVersionCode;
  final String? url;
  final String? release;
  final int? size;
  final bool? shouldNotify;

  LatestVersionInfo(
    this.name,
    this.code,
    this.changelog,
    this.shouldForceUpdate,
    this.lastSupportedVersionCode,
    this.url,
    this.release,
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
      map['release'],
      map['size'],
      map['shouldNotify'],
    );
  }
}
