import 'dart:async';

import 'package:log_viewer/src/core/log_database.dart';
import 'package:log_viewer/src/core/log_models.dart';
import 'package:logging/logging.dart' as log;

class LogStore {
  static final LogStore _instance = LogStore._internal();
  static LogStore get instance => _instance;

  LogStore._internal();

  final LogDatabase _database = LogDatabase();
  final _logStreamController = StreamController<LogEntry>.broadcast();

  final List<LogEntry> _buffer = [];
  Timer? _flushTimer;
  static const int _bufferSize = 10;
  static const int _maxBufferSize = 200;

  bool _initialized = false;
  bool get initialized => _initialized;

  Stream<LogEntry> get logStream => _logStreamController.stream;

  Future<void> initialize() async {
    if (_initialized) return;

    await _database.database;

    _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flush());

    _initialized = true;
  }

  static void addLogRecord(log.LogRecord record, [String? processPrefix]) {
    if (_instance._initialized) {
      _instance._addLog(record, processPrefix ?? '');
    }
  }

  void _addLog(log.LogRecord record, String processPrefix) {
    final entry = LogEntry(
      message: record.message,
      level: record.level.name,
      timestamp: record.time,
      loggerName: record.loggerName,
      error: record.error?.toString(),
      stackTrace: record.stackTrace?.toString(),
      processPrefix: processPrefix,
    );

    _buffer.add(entry);

    _logStreamController.add(entry);

    if (_buffer.length >= _bufferSize) {
      _flush();
    } else if (_buffer.length >= _maxBufferSize) {
      _flush();
    }
  }

  Future<void> _flush() async {
    if (_buffer.isEmpty) return;

    final toInsert = List<LogEntry>.from(_buffer);
    _buffer.clear();

    unawaited(
      _database.insertLogs(toInsert).catchError((e) {
        // ignore: avoid_print
        print('Failed to insert logs to database: $e');
      }),
    );
  }

  Future<List<LogEntry>> getLogs({
    LogFilter? filter,
    int limit = 250,
    int offset = 0,
  }) async {
    await _flush();

    return _database.getLogs(filter: filter, limit: limit, offset: offset);
  }

  Future<List<String>> getLoggerNames() async {
    return _database.getUniqueLoggers();
  }

  Future<List<String>> getProcessNames() async {
    return _database.getUniqueProcesses();
  }

  Future<List<LoggerStatistic>> getLoggerStatistics({LogFilter? filter}) async {
    await _flush();
    return _database.getLoggerStatistics(filter: filter);
  }

  Future<int> getLogCount({LogFilter? filter}) async {
    await _flush();
    return _database.getLogCount(filter: filter);
  }

  Future<void> clearLogs() async {
    _buffer.clear();
    await _database.clearLogs();
  }

  Future<void> clearLogsByLogger(String loggerName) async {
    _buffer.removeWhere((log) => log.loggerName == loggerName);
    await _database.clearLogsByLogger(loggerName);
  }

  Future<String> exportLogs({LogFilter? filter}) async {
    final logs = await getLogs(filter: filter, limit: 10000);

    final buffer = StringBuffer();
    buffer.writeln('=== Ente App Logs ===');
    buffer.writeln('Exported at: ${DateTime.now()}');
    if (filter != null && filter.hasActiveFilters) {
      buffer.writeln('Filters applied:');
      if (filter.selectedLoggers.isNotEmpty) {
        buffer.writeln('  Loggers: ${filter.selectedLoggers.join(', ')}');
      }
      if (filter.selectedLevels.isNotEmpty) {
        buffer.writeln('  Levels: ${filter.selectedLevels.join(', ')}');
      }
      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        buffer.writeln('  Search: ${filter.searchQuery}');
      }
    }
    buffer.writeln('Total logs: ${logs.length}');
    buffer.writeln('=' * 40);
    buffer.writeln();

    for (final log in logs) {
      buffer.writeln(log.toString());
      buffer.writeln('-' * 40);
    }

    return buffer.toString();
  }

  Future<TimeRange?> getTimeRange() async {
    await _flush();
    return _database.getTimeRange();
  }

  Future<List<DateTime>> getLogTimestamps() async {
    await _flush();
    return _database.getLogTimestamps();
  }

  Future<String> exportLogsAsJson({LogFilter? filter}) async {
    final logs = await getLogs(filter: filter, limit: 10000);

    final jsonLogs = logs
        .map(
          (log) => {
            'timestamp': log.timestamp.toIso8601String(),
            'level': log.level,
            'logger': log.loggerName,
            'message': log.message,
            if (log.error != null) 'error': log.error,
            if (log.stackTrace != null) 'stackTrace': log.stackTrace,
          },
        )
        .toList();

    final buffer = StringBuffer();
    buffer.writeln('[');
    for (int i = 0; i < jsonLogs.length; i++) {
      buffer.write('  ');
      buffer.write(jsonLogs[i].toString());
      if (i < jsonLogs.length - 1) {
        buffer.writeln(',');
      } else {
        buffer.writeln();
      }
    }
    buffer.writeln(']');

    return buffer.toString();
  }

  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
    await _database.close();
    await _logStreamController.close();
    _initialized = false;
  }
}
