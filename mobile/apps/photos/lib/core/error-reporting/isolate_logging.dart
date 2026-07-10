import "dart:collection" show Queue;
import "dart:convert" show jsonEncode, jsonDecode;

import "package:logging/logging.dart";
import "package:photos/core/error-reporting/super_logging.dart";

class IsolateLogString {
  final String logString;
  final String? error;
  final String? stackTrace;
  final String loggerName;
  final String levelName;
  final String message;

  IsolateLogString({
    required this.logString,
    required this.error,
    required this.stackTrace,
    required this.loggerName,
    required this.levelName,
    required this.message,
  });

  String toJsonString() => jsonEncode({
    'logString': logString,
    'error': error,
    'stackTrace': stackTrace,
    'loggerName': loggerName,
    'levelName': levelName,
    'message': message,
  });

  static IsolateLogString fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString);
    final rawError = json['error'];
    return IsolateLogString(
      logString: json['logString'] as String,
      error: rawError is String ? rawError : null,
      stackTrace: json['stackTrace'] as String?,
      loggerName: json['loggerName'] as String? ?? 'isolate',
      levelName: json['levelName'] as String? ?? Level.INFO.name,
      message: json['message'] as String? ?? '',
    );
  }
}

class IsolateLogError implements Exception {
  final String message;

  const IsolateLogError(this.message);

  @override
  String toString() => message;
}

class IsolateLogger {
  final Queue<IsolateLogString> fileQueueEntries = Queue();

  Future onLogRecordInIsolate(LogRecord rec) async {
    final str = rec.toPrettyString(null, true);

    // write to stdout
    if (SuperLogging.shouldPrintLogRecord(rec)) {
      SuperLogging.printLog(str);
    }

    // push to log queue
    fileQueueEntries.add(
      IsolateLogString(
        logString: str,
        error: rec.error?.toString(),
        stackTrace: rec.stackTrace?.toString(),
        loggerName: rec.loggerName,
        levelName: rec.level.name,
        message: rec.message,
      ),
    );
  }

  /// WARNING: only call this from the isolate
  Queue<String> getLogStringsAndClear() {
    if (fileQueueEntries.isEmpty) return Queue<String>();
    final result = Queue<String>();
    while (fileQueueEntries.isNotEmpty) {
      final entry = fileQueueEntries.removeFirst();
      result.add(entry.toJsonString());
    }
    return result;
  }

  /// WARNING: only call this from the main thread
  static void handLogStringsToMainLogger(List<String> logs) {
    while (logs.isNotEmpty) {
      final logString = logs.removeAt(0);
      final log = IsolateLogString.fromJsonString(logString);
      final error = log.error;
      if (error == null) {
        SuperLogging.saveLogString(log.logString, null);
        continue;
      }
      final stackTraceString = log.stackTrace;
      final stackTrace = stackTraceString == null || stackTraceString.isEmpty
          ? null
          : StackTrace.fromString(stackTraceString);
      final isolateError = IsolateLogError(error);
      SuperLogging.saveLogString(
        log.logString,
        isolateError,
        stackTrace: stackTrace,
        rec: LogRecord(
          _levelFromName(log.levelName),
          log.message,
          log.loggerName,
          isolateError,
          stackTrace,
        ),
      );
    }
  }

  static Level _levelFromName(String levelName) {
    return switch (levelName) {
      'SHOUT' => Level.SHOUT,
      'SEVERE' => Level.SEVERE,
      'WARNING' => Level.WARNING,
      'INFO' => Level.INFO,
      'CONFIG' => Level.CONFIG,
      'FINE' => Level.FINE,
      'FINER' => Level.FINER,
      'FINEST' => Level.FINEST,
      _ => Level.INFO,
    };
  }
}
