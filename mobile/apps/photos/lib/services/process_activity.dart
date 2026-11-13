import "package:shared_preferences/shared_preferences.dart";

const kLastBGTaskHeartBeatTime = "bg_task_hb_time";
const kLastFGTaskHeartBeatTime = "fg_task_hb_time";
const kLastNativeFGTaskHeartBeatTime = "native_fg_task_hb_time";
const kEngineDeathTimeoutInMicroseconds = 5000000;

// Heartbeats affect priority and yield latency, not correctness.
Future<bool> isForegroundEngineActive() =>
    _isEngineActive([kLastFGTaskHeartBeatTime, kLastNativeFGTaskHeartBeatTime]);

Future<bool> isBackgroundEngineActive() =>
    _isEngineActive([kLastBGTaskHeartBeatTime]);

Future<bool> _isEngineActive(List<String> heartBeatKeys) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final threshold =
      DateTime.now().microsecondsSinceEpoch - kEngineDeathTimeoutInMicroseconds;
  return heartBeatKeys.any((key) => (prefs.getInt(key) ?? 0) > threshold);
}
