import "package:photos/services/rewind/rewind_edition.dart";
import "package:shared_preferences/shared_preferences.dart";

class RewindProgress {
  RewindProgress(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = "ls.rewind_${RewindEdition.year}";
  static const _openedKey = "${_prefix}_opened";
  static const _notificationScheduledKey = "${_prefix}_notification_scheduled";

  bool get opened => _prefs.getBool(_openedKey) ?? false;

  bool get notificationScheduled =>
      _prefs.getBool(_notificationScheduledKey) ?? false;

  Future<void> markOpened() => _prefs.setBool(_openedKey, true);

  Future<void> markNotificationScheduled() =>
      _prefs.setBool(_notificationScheduledKey, true);

  Future<void> clearNotificationScheduled() =>
      _prefs.remove(_notificationScheduledKey);
}
