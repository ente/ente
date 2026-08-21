import "package:wakelock_plus/wakelock_plus.dart";

enum WakeLockFor {
  videoPlayback,
  machineLearningSettingsScreen,
  rewindViewer,
  largeBackupStandbyScreen,
  albumSlideshow,
}

class EnteWakeLockService {
  void updateWakeLock({
    required bool enable,
    required WakeLockFor wakeLockFor,
  }) {
    WakelockPlus.toggle(enable: enable);
  }
}
