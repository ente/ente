import "package:shared_preferences/shared_preferences.dart";

const lastBackgroundTaskHeartbeatKey = "bg_task_hb_time";
const lastForegroundTaskHeartbeatKey = "fg_task_hb_time";
const processHeartbeatFrequency = Duration(seconds: 1);
const foregroundActivityTimeout = Duration(seconds: 5);

class ProcessActivityService {
  ProcessActivityService._();

  static final instance = ProcessActivityService._();

  bool isBackgroundProcess = true;

  Future<bool> isForegroundRecentlyActive() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final lastHeartbeat = preferences.getInt(lastForegroundTaskHeartbeatKey);
    if (lastHeartbeat == null) return false;
    final cutoff = DateTime.now().subtract(foregroundActivityTimeout);
    return lastHeartbeat > cutoff.microsecondsSinceEpoch;
  }
}
