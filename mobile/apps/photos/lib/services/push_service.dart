import "dart:async";

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/signed_in_event.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/sync/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef BackgroundPushHandler = Future<void> Function(Object message);

class PushService {
  static const kFCMPushToken = "fcm_push_token";
  static const kLastFCMTokenUpdationTime = "fcm_push_token_updation_time";
  static const kFCMTokenUpdationIntervalInMicroSeconds = 30 * microSecondsInDay;
  static const kPushAction = "action";
  static const kSync = "sync";

  static final PushService instance = PushService._privateConstructor();
  static final _logger = Logger("PushService");

  late SharedPreferences _prefs;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<SignedInEvent>? _signedInSubscription;

  PushService._privateConstructor();

  Future<void> init({BackgroundPushHandler? onBackgroundPush}) async {
    _prefs = await SharedPreferences.getInstance();
    await Firebase.initializeApp();
    if (onBackgroundPush != null) {
      FirebaseMessaging.onBackgroundMessage(onBackgroundPush);
    }
    if (_foregroundMessageSubscription != null) {
      await _foregroundMessageSubscription!.cancel();
    }
    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      _logger.info("Got a message whilst in the foreground!");
      _handleForegroundPushMessage(message);
    });
    try {
      if (_signedInSubscription != null) {
        await _signedInSubscription!.cancel();
      }
      if (Configuration.instance.hasConfiguredAccount()) {
        await _configurePushToken();
      } else {
        _signedInSubscription = Bus.instance.on<SignedInEvent>().listen((
          _,
        ) async {
          // ignore: unawaited_futures
          _configurePushToken();
        });
      }
    } catch (e, s) {
      _logger.severe("Could not configure push token", e, s);
    }
  }

  Future<void> _configurePushToken() async {
    final String? fcmToken = await FirebaseMessaging.instance.getToken();
    final shouldForceRefreshServerToken =
        DateTime.now().microsecondsSinceEpoch -
            (_prefs.getInt(kLastFCMTokenUpdationTime) ?? 0) >
        kFCMTokenUpdationIntervalInMicroSeconds;
    if (fcmToken != null &&
        (_prefs.getString(kFCMPushToken) != fcmToken ||
            shouldForceRefreshServerToken)) {
      final String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      try {
        _logger.info("Updating token on server");
        await _setPushTokenOnServer(fcmToken, apnsToken);
        await _prefs.setString(kFCMPushToken, fcmToken);
        await _prefs.setInt(
          kLastFCMTokenUpdationTime,
          DateTime.now().microsecondsSinceEpoch,
        );
        _logger.info("Push token updated on server");
      } catch (e) {
        _logger.severe("Could not set push token", e, StackTrace.current);
      }
    } else {
      _logger.info("Skipping token update");
    }
  }

  Future<void> _setPushTokenOnServer(String fcmToken, String? apnsToken) async {
    await pushGateway.registerToken(fcmToken: fcmToken, apnsToken: apnsToken);
  }

  void _handleForegroundPushMessage(RemoteMessage message) {
    _logger.info("Message data: ${message.data}");
    if (message.notification != null) {
      _logger.info(
        "Message also contained a notification: ${message.notification}",
      );
    }
    if (shouldSync(message)) {
      SyncService.instance.sync();
    }
  }

  static bool shouldSync(Object message) {
    if (message is! RemoteMessage) {
      return false;
    }
    return message.data.containsKey(kPushAction) &&
        message.data[kPushAction] == kSync;
  }
}
