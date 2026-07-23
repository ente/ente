import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import "package:flutter_timezone/flutter_timezone.dart";
import "package:logging/logging.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/services/timezone_aliases.dart";
import "package:shared_preferences/shared_preferences.dart";
import 'package:timezone/data/latest_10y.dart' as tzdb;
import "package:timezone/timezone.dart" as tz;

class NotificationService {
  static final NotificationService instance =
      NotificationService._privateConstructor();
  static const String keyGrantedNotificationPermission =
      "notification_permission_granted";
  static const String keyShouldShowNotificationsForSharedPhotos =
      "notifications_enabled_shared_photos";
  static const String keyShouldShowSocialNotifications =
      "notifications_enabled_social";

  NotificationService._privateConstructor();

  late SharedPreferences _preferences;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final _logger = Logger("NotificationService");
  void Function(NotificationResponse notificationResponse)?
  _onNotificationTapped;
  bool _pluginInitialized = false;
  bool _launchDetailsHandled = false;

  void init(SharedPreferences preferences) {
    _preferences = preferences;
  }

  bool timezoneInitialized = false;

  Future<void> initialize(
    void Function(NotificationResponse notificationResponse)
    onNotificationTapped,
  ) async {
    _onNotificationTapped = onNotificationTapped;
    await _ensurePluginInitialized();
    await _handleLaunchDetailsIfNeeded();
    if (!hasGrantedPermissions() &&
        RemoteSyncService.instance.isFirstRemoteSyncDone()) {
      await requestPermissions();
    }
  }

  Future<void> initializeForBackground() async {
    await _ensurePluginInitialized();
  }

  Future<void> _ensurePluginInitialized() async {
    if (_pluginInitialized) return;
    final pluginInitStopwatch = Stopwatch()..start();
    const androidSettings = AndroidInitializationSettings('notification_icon');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestCriticalPermission: false,
    );
    const InitializationSettings initializationSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
    _logger.info(
      "flutter_local_notifications.initialize took ${pluginInitStopwatch.elapsedMilliseconds}ms",
    );
    _pluginInitialized = true;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    if (_onNotificationTapped != null) {
      _onNotificationTapped!(response);
      return;
    }
    _logger.warning(
      "Notification response received before handler was set; ignoring.",
    );
  }

  Future<void> _handleLaunchDetailsIfNeeded() async {
    if (_launchDetailsHandled) return;
    final launchDetailsStopwatch = Stopwatch()..start();
    final launchDetails = await _notificationsPlugin
        .getNotificationAppLaunchDetails();
    _logger.info(
      "getNotificationAppLaunchDetails took ${launchDetailsStopwatch.elapsedMilliseconds}ms",
    );
    if (launchDetails != null &&
        launchDetails.didNotificationLaunchApp &&
        launchDetails.notificationResponse != null) {
      _onNotificationTapped?.call(launchDetails.notificationResponse!);
    }
    _launchDetailsHandled = true;
  }

  Future<void> initTimezones() async {
    if (timezoneInitialized) return;
    final timezoneInitStopwatch = Stopwatch()..start();
    final tzdbStopwatch = Stopwatch()..start();
    tzdb.initializeTimeZones();
    _logger.info(
      "tz.initializeTimeZones took ${tzdbStopwatch.elapsedMilliseconds}ms",
    );
    final localTimezoneStopwatch = Stopwatch()..start();
    final String currentTimeZone = await FlutterTimezone.getLocalTimezone();
    _logger.info(
      "FlutterTimezone.getLocalTimezone took ${localTimezoneStopwatch.elapsedMilliseconds}ms",
    );
    final String resolvedTimeZone = _resolveTimeZoneName(currentTimeZone);
    tz.setLocalLocation(tz.getLocation(resolvedTimeZone));
    timezoneInitialized = true;
    _logger.info(
      "Notification timezone init took ${timezoneInitStopwatch.elapsedMilliseconds}ms",
    );
  }

  String _resolveTimeZoneName(String timeZoneName) {
    if (tz.timeZoneDatabase.locations.containsKey(timeZoneName)) {
      return timeZoneName;
    }

    final alias = kTimeZoneAliases[timeZoneName];
    if (alias != null && tz.timeZoneDatabase.locations.containsKey(alias)) {
      _logger.warning(
        'Timezone "$timeZoneName" not found, using alias "$alias".',
      );
      return alias;
    }

    final normalized = timeZoneName.replaceAll(' ', '_');
    if (normalized != timeZoneName &&
        tz.timeZoneDatabase.locations.containsKey(normalized)) {
      _logger.warning(
        'Timezone "$timeZoneName" not found, using normalized "$normalized".',
      );
      return normalized;
    }

    final lower = timeZoneName.toLowerCase();
    String? caseMatch;
    for (final name in tz.timeZoneDatabase.locations.keys) {
      if (name.toLowerCase() == lower) {
        caseMatch = name;
        break;
      }
    }
    if (caseMatch != null) {
      _logger.warning(
        'Timezone "$timeZoneName" not found, using "$caseMatch".',
      );
      return caseMatch;
    }

    _logger.warning('Timezone "$timeZoneName" not found, falling back to UTC.');
    return 'UTC';
  }

  Future<void> requestPermissions() async {
    await _ensurePluginInitialized();
    bool? result;
    if (Platform.isIOS) {
      result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(sound: true, alert: true);
    } else {
      result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    }
    if (result != null) {
      await _preferences.setBool(keyGrantedNotificationPermission, result);
    }
  }

  bool hasGrantedPermissions() {
    final result = _preferences.getBool(keyGrantedNotificationPermission);
    return result ?? false;
  }

  bool shouldShowNotificationsForSharedPhotosAndAlbums() {
    final result = _preferences.getBool(
      keyShouldShowNotificationsForSharedPhotos,
    );
    return result ?? true;
  }

  Future<void> setShouldShowNotificationsForSharedPhotosAndAlbums(bool value) {
    return _preferences.setBool(
      keyShouldShowNotificationsForSharedPhotos,
      value,
    );
  }

  bool shouldShowSocialNotifications() {
    final result = _preferences.getBool(keyShouldShowSocialNotifications);
    return result ?? true;
  }

  Future<void> setShouldShowSocialNotifications(bool value) {
    return _preferences.setBool(keyShouldShowSocialNotifications, value);
  }

  Future<void> showNotification(
    String title,
    String message, {
    int? id,
    String channelID = "io.ente.photos",
    String channelName = "ente",
    String payload = "ente://home",
  }) async {
    await _ensurePluginInitialized();
    _logger.info(
      "Showing notification with: $title, $message, $channelID, $channelName, $payload",
    );
    final androidSpecs = AndroidNotificationDetails(
      channelID,
      channelName,
      channelDescription: 'ente alerts',
      importance: Importance.max,
      priority: Priority.high,
      icon: 'notification_icon',
      showWhen: false,
    );
    final iosSpecs = DarwinNotificationDetails(threadIdentifier: channelID);
    final platformChannelSpecs = NotificationDetails(
      android: androidSpecs,
      iOS: iosSpecs,
    );
    await _notificationsPlugin.show(
      id ?? channelName.hashCode,
      title,
      message,
      platformChannelSpecs,
      payload: payload,
    );
  }

  Future<void> scheduleNotification(
    String title, {
    String? message,
    required int id,
    String channelID = "io.ente.photos",
    String channelName = "ente",
    String payload = "ente://home",
    required DateTime dateTime,
    Duration? timeoutDurationAndroid,
    bool logSchedule = true,
  }) async {
    try {
      await _ensurePluginInitialized();
      if (logSchedule) {
        _logger.info(
          "Scheduling notification with: $title, $message, $channelID, $channelName, $payload",
        );
      }
      await initTimezones();
      if (!hasGrantedPermissions()) {
        _logger.warning("Notification permissions not granted");
        await requestPermissions();
        if (!hasGrantedPermissions()) {
          _logger.severe("Failed to get notification permissions");
          return;
        }
      } else {
        if (logSchedule) {
          _logger.info("Notification permissions already granted");
        }
      }
      final androidSpecs = AndroidNotificationDetails(
        channelID,
        channelName,
        channelDescription: 'ente alerts',
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        icon: 'notification_icon',
        showWhen: false,
        timeoutAfter: timeoutDurationAndroid?.inMilliseconds,
      );
      final iosSpecs = DarwinNotificationDetails(threadIdentifier: channelID);
      final platformChannelSpecs = NotificationDetails(
        android: androidSpecs,
        iOS: iosSpecs,
      );
      final scheduledDate = tz.TZDateTime.local(
        dateTime.year,
        dateTime.month,
        dateTime.day,
        dateTime.hour,
        dateTime.minute,
        dateTime.second,
      );
      // final tz.TZDateTime scheduledDate = tz.TZDateTime.now(tz.local).add(delay);
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        message,
        scheduledDate,
        platformChannelSpecs,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      if (logSchedule) {
        _logger.info(
          "Scheduled notification with: $title, $message, $channelID, $channelName, $payload for $dateTime",
        );
      }
    } catch (e, s) {
      // For now we're swallowing any exceptions here because we don't want the memories logic to get disturbed
      _logger.severe(
        "Something went wrong while scheduling notification",
        e,
        s,
      );
    }
  }

  Future<void> clearAllScheduledNotifications({
    String? containingPayload,
    bool logLines = true,
  }) async {
    try {
      await _ensurePluginInitialized();
      if (logLines) {
        _logger.info("Clearing all scheduled notifications");
      }
      final pending = await _notificationsPlugin.pendingNotificationRequests();
      if (pending.isEmpty) {
        if (logLines) {
          _logger.info("No pending notifications to clear");
        }
        return;
      }
      for (final request in pending) {
        if (containingPayload != null &&
            !request.payload.toString().contains(containingPayload)) {
          if (logLines) {
            _logger.info(
              "Skip clearing of notification with id: ${request.id} and payload: ${request.payload}",
            );
          }
          continue;
        }
        if (logLines) {
          _logger.info(
            "Clearing notification with id: ${request.id} and payload: ${request.payload}",
          );
        }
        await _notificationsPlugin.cancel(request.id);
        if (logLines) {
          _logger.info(
            "Cleared notification with id: ${request.id} and payload: ${request.payload}",
          );
        }
      }
    } catch (e, s) {
      _logger.severe("Something is wrong with scheduled notifications", e, s);
    }
  }

  Future<int> pendingNotifications() async {
    await _ensurePluginInitialized();
    final pending = await _notificationsPlugin.pendingNotificationRequests();
    return pending.length;
  }
}
