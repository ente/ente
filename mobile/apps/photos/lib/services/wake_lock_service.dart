import "package:wakelock_plus/wakelock_plus.dart";

enum WakeLockFor {
  videoPlayback,
  externalVideoPlayback,
  machineLearningSettingsScreen,
  rewindViewer,
  largeBackupStandbyScreen,
  albumSlideshow,
  mlProgressBanner,
}

class EnteWakeLockService {
  final Set<WakeLockFor> _activeWakeLocks = {};

  void updateWakeLock({
    required bool enable,
    required WakeLockFor wakeLockFor,
  }) {
    if (enable) {
      _activeWakeLocks.add(wakeLockFor);
    } else {
      _activeWakeLocks.remove(wakeLockFor);
    }
    WakelockPlus.toggle(enable: _activeWakeLocks.isNotEmpty);
  }
}
