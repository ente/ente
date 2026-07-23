import "package:shared_preferences/shared_preferences.dart";

class BackupSettings {
  BackupSettings(this._preferences);

  static const _keyShouldBackupOverMobileData =
      "should_backup_over_mobile_data";
  static const _keyShouldBackupVideos = "should_backup_videos";

  final SharedPreferences _preferences;

  bool shouldBackupOverMobileData() {
    return _preferences.getBool(_keyShouldBackupOverMobileData) ?? false;
  }

  Future<void> setBackupOverMobileData(bool value) async {
    await _preferences.setBool(_keyShouldBackupOverMobileData, value);
  }

  bool shouldBackupVideos() {
    return _preferences.getBool(_keyShouldBackupVideos) ?? true;
  }

  Future<void> setBackupVideos(bool value) async {
    await _preferences.setBool(_keyShouldBackupVideos, value);
  }
}
