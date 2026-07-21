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
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher_string.dart';

enum ChangeLogAction { skip, consumeWithoutShowing, show }

class UpdateService {
  static const kUpdateAvailableShownTimeKey = "update_available_shown_time_key";
  static const changeLogVersionKey = "update_change_log_key";
  static const currentChangeLogVersion = 56;

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
    // fetch the change log version which was last shown to user.
    final lastShownAtVersion = _prefs.getInt(changeLogVersionKey);
    if (lastShownAtVersion == null) {
      // Fresh install: the key was never set, so the user has no previous
      // version to show a "What's New" for. Silently mark as seen.
      await hideChangeLog();
      return false;
    }
    return lastShownAtVersion < currentChangeLogVersion;
  }

  Future<ChangeLogAction> getChangeLogAction({
    required Locale locale,
    required bool isLocalGallery,
    required bool isSignedIn,
    required bool isAndroid,
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
          isAndroid: isAndroid,
        )
        ? ChangeLogAction.show
        : ChangeLogAction.consumeWithoutShowing;
  }

  Future<bool> hideChangeLog() async {
    return _prefs.setInt(changeLogVersionKey, currentChangeLogVersion);
  }

  Future<bool> shouldUpdate() async {
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

  Future<bool> shouldShowUpdateNotification() async {
    final shouldUpdate = await this.shouldUpdate();

    if (!shouldUpdate) {
      return false;
    }

    final lastNotificationShownTime =
        _prefs.getInt(kUpdateAvailableShownTimeKey) ?? 0;
    final now = DateTime.now().microsecondsSinceEpoch;
    final hasBeenThresholdDaysSinceLastNotification =
        (now - lastNotificationShownTime) >
        ((_latestVersion!.shouldNotify ? 1 : 3) * microSecondsInDay);

    return shouldUpdate && hasBeenThresholdDaysSinceLastNotification;
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

  // getRateDetails returns details about the place
  Tuple2<String, String> getRateDetails() {
    if (isFDroidFlavor() || isIndependentFlavor()) {
      return const Tuple2(
        "AlternativeTo",
        "https://alternativeto.net/software/ente/about/",
      );
    }
    return Platform.isAndroid
        ? const Tuple2(
            "Google Play",
            "https://play.google.com/store/apps/details?id=io.ente.photos",
          )
        : const Tuple2(
            "App Store",
            "https://apps.apple.com/in/app/ente-photos/id1542026904",
          );
  }

  Future<void> launchReviewUrl() async {
    // TODO: Replace with https://pub.dev/packages/in_app_review
    final String url = getRateDetails().item2;
    try {
      await launchUrlString(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      _logger.severe("Failed top open launch url $url", e);
      // Fall back if we fail to open play-store market app on android
      if (Platform.isAndroid && url.startsWith("market://")) {
        launchUrlString(
          "https://play.google.com/store/apps/details?id=io"
          ".ente.photos",
          mode: LaunchMode.externalApplication,
        ).ignore();
      }
    }
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
