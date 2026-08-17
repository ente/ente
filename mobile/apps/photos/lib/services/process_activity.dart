import "package:shared_preferences/shared_preferences.dart";

const kLastBGTaskHeartBeatTime = "bg_task_hb_time";
const kLastFGTaskHeartBeatTime = "fg_task_hb_time";
const kEngineDeathTimeoutInMicroseconds = 5000000;

// Heartbeats affect priority and yield latency, not correctness.
Future<bool> isForegroundEngineActive() =>
    _isEngineActive(kLastFGTaskHeartBeatTime);

Future<bool> isBackgroundEngineActive() =>
    _isEngineActive(kLastBGTaskHeartBeatTime);

Future<bool> _isEngineActive(String heartBeatKey) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final currentTime = DateTime.now().microsecondsSinceEpoch;
  final lastHeartBeatTime = prefs.getInt(heartBeatKey) ?? 0;
  return lastHeartBeatTime > (currentTime - kEngineDeathTimeoutInMicroseconds);
}
