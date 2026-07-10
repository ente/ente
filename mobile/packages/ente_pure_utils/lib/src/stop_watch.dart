import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class EnteWatch extends Stopwatch {
  final String context;
  int previousElapsed = 0;

  EnteWatch(this.context) : super();

  static bool _shouldLog = kDebugMode && Logger.root.isLoggable(Level.INFO);

  static void setLogLevel(Level level) {
    _shouldLog = kDebugMode && Level.INFO.value >= level.value;
  }

  void log(String msg) {
    if (_shouldLog) {
      debugPrint(
        "[$context]: $msg took ${Duration(microseconds: elapsedMicroseconds - previousElapsed).inMilliseconds} ms  total: "
        "${elapsed.inMilliseconds} ms",
      );
    }
    previousElapsed = elapsedMicroseconds;
  }

  void logAndReset(String msg) {
    if (_shouldLog) {
      debugPrint("[$context]: $msg took ${elapsed.inMilliseconds} ms");
    }
    reset();
    previousElapsed = 0;
  }

  void stopWithLog(String msg) {
    log(msg);
    stop();
  }
}

// TimerLogger helps in quickly including the timeTaken for various operation.
// The timeTaken is logged only if it exceeds the logThreshold. With each call to toString, the timer is reset.
// Usage:
// final TimeLogger tlog = TimeLogger(context: "FaceRecognitionService");
// _logger.info("some operation $tlog");
// _logger.info("another operation $tlog");
class TimeLogger {
  final String context;
  final int logThreshold;
  DateTime _start;
  TimeLogger({this.context = "TLog", this.logThreshold = 5})
    : _start = DateTime.now();

  @override
  String toString() {
    final int diff = DateTime.now().difference(_start).inMilliseconds;
    late String res;
    if (diff > logThreshold) {
      res = "[$context: $diff ms]";
    } else {
      res = "[]";
    }
    _start = DateTime.now();
    return res;
  }
}
