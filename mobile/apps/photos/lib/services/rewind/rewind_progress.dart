import "package:flutter/foundation.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:shared_preferences/shared_preferences.dart";

class RewindProgress extends ChangeNotifier {
  RewindProgress(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = "ls.rewind_${RewindEdition.year}";
  static const _openedKey = "${_prefix}_opened";
  static const _notificationScheduledKey = "${_prefix}_notification_scheduled";
  static const _resumePageKey = "${_prefix}_resume_page";
  static const _resumeStopKey = "${_prefix}_resume_stop";
  static const _completedKey = "${_prefix}_completed";

  bool get opened => _prefs.getBool(_openedKey) ?? false;

  bool get notificationScheduled =>
      _prefs.getBool(_notificationScheduledKey) ?? false;

  String? get resumePage => _prefs.getString(_resumePageKey);

  int get resumeStop => _prefs.getInt(_resumeStopKey) ?? 0;

  bool get completed => _prefs.getBool(_completedKey) ?? false;

  Future<void> markOpened() async {
    await _prefs.setBool(_openedKey, true);
    notifyListeners();
  }

  Future<void> saveResume(String page, int stop) async {
    await _prefs.setString(_resumePageKey, page);
    await _prefs.setInt(_resumeStopKey, stop);
    notifyListeners();
  }

  Future<void> markCompleted() async {
    await _prefs.setBool(_completedKey, true);
    notifyListeners();
  }

  Future<void> markNotificationScheduled() =>
      _prefs.setBool(_notificationScheduledKey, true);

  Future<void> clearNotificationScheduled() =>
      _prefs.remove(_notificationScheduledKey);
}
