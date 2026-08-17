import "package:shared_preferences/shared_preferences.dart";
import "package:wakelock_plus/wakelock_plus.dart";

enum WakeLockFor {
  videoPlayback,
  fasterBackupsOniOSByKeepingScreenAwake,
  machineLearningSettingsScreen,
  handlingMediaKitEdgeCase,
  rewindViewer,
  largeBackupStandbyScreen,
}

// Temporary callers must not override the across-session setting.
// media_kit is the only code that intentionally bypasses this wrapper.
class EnteWakeLockService {
  static const String kKeepAppAwakeAcrossSessions =
      "keepAppAwakeAcrossSessions";

  EnteWakeLockService(this._prefs);

  final SharedPreferences _prefs;

  void init({required bool isBackground}) {
    if (isBackground) {
      return;
    }
    if (_prefs.getBool(kKeepAppAwakeAcrossSessions) ?? false) {
      WakelockPlus.enable();
    }
  }

  void updateWakeLock({
    required bool enable,
    required WakeLockFor wakeLockFor,
  }) {
    if (wakeLockFor == WakeLockFor.fasterBackupsOniOSByKeepingScreenAwake ||
        wakeLockFor == WakeLockFor.handlingMediaKitEdgeCase) {
      WakelockPlus.toggle(enable: enable);
      _prefs.setBool(kKeepAppAwakeAcrossSessions, enable);
    } else {
      if (!shouldKeepAppAwakeAcrossSessions) {
        WakelockPlus.toggle(enable: enable);
      }
    }
  }

  bool get shouldKeepAppAwakeAcrossSessions =>
      _prefs.getBool(kKeepAppAwakeAcrossSessions) ?? false;
}
