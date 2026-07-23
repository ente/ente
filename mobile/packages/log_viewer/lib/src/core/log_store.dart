import 'dart:async';

import 'package:log_viewer/src/core/log_database.dart';
import 'package:log_viewer/src/core/log_models.dart';
import 'package:logging/logging.dart' as log;

/// Singleton store that receives and manages logs
class LogStore {
  static final LogStore _instance = LogStore._internal();
  static LogStore get instance => _instance;

  LogStore._internal();

  final LogDatabase _database = LogDatabase();
  final _logStreamController = StreamController<LogEntry>.broadcast();

  // Buffer for batch inserts - optimized for small entries
  final List<LogEntry> _buffer = [];
  Timer? _flushTimer;
  static const int _bufferSize = 10;
  static const int _maxBufferSize = 200; // Safety limit

  bool _initialized = false;
  bool get initialized => _initialized;

  /// Stream of new log entries
  Stream<LogEntry> get logStream => _logStreamController.stream;

  /// Initialize the log store
  Future<void> initialize() async {
    if (_initialized) return;

    await _database.database; // Initialize database

    // Start periodic flush timer - less frequent for better batching
    _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flush());

    _initialized = true;
  }

  /// Static method that super_logging.dart will call
  static void addLogRecord(log.LogRecord record, [String? processPrefix]) {
    if (_instance._initialized) {
      _instance._addLog(record, processPrefix ?? '');
    }
  }

  /// Add a log from a LogRecord
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

    // Add to buffer for batch insert
    _buffer.add(entry);

    // Emit to stream for real-time updates
    _logStreamController.add(entry);

    // Flush when buffer reaches optimal size or safety limit
    if (_buffer.length >= _bufferSize) {
      _flush();
    } else if (_buffer.length >= _maxBufferSize) {
      // Emergency flush if buffer grows too large
      _flush();
    }
  }

  /// Flush buffered logs to database
  Future<void> _flush() async {
    if (_buffer.isEmpty) return;

    final toInsert = List<LogEntry>.from(_buffer);
    _buffer.clear();

    // Use non-blocking database insert for better write performance
    unawaited(
      _database.insertLogs(toInsert).catchError((e) {
        // ignore: avoid_print
        print('Failed to insert logs to database: $e');
      }),
    );
  }

  /// Get logs with filtering
  Future<List<LogEntry>> getLogs({
    LogFilter? filter,
    int limit = 250,
    int offset = 0,
  }) async {
    // Flush any pending logs first
    await _flush();

    return _database.getLogs(filter: filter, limit: limit, offset: offset);
  }

  /// Get unique logger names
  Future<List<String>> getLoggerNames() async {
    return _database.getUniqueLoggers();
  }

  /// Get unique process prefixes
  Future<List<String>> getProcessNames() async {
    return _database.getUniqueProcesses();
  }

  /// Get logger statistics with count and percentage
  Future<List<LoggerStatistic>> getLoggerStatistics({LogFilter? filter}) async {
    await _flush();
    return _database.getLoggerStatistics(filter: filter);
  }

  /// Get count of logs matching filter
  Future<int> getLogCount({LogFilter? filter}) async {
    await _flush();
    return _database.getLogCount(filter: filter);
  }

  /// Clear all logs
  Future<void> clearLogs() async {
    _buffer.clear();
    await _database.clearLogs();
  }

  /// Clear logs by logger
  Future<void> clearLogsByLogger(String loggerName) async {
    _buffer.removeWhere((log) => log.loggerName == loggerName);
    await _database.clearLogsByLogger(loggerName);
  }

  /// Export logs as text
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

  /// Get time range of all logs
  Future<TimeRange?> getTimeRange() async {
    await _flush();
    return _database.getTimeRange();
  }

  /// Get all log timestamps for timeline visualization
  Future<List<DateTime>> getLogTimestamps() async {
    await _flush();
    return _database.getLogTimestamps();
  }

  /// Export logs as JSON
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

    // Manual JSON formatting for readability
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

  /// Dispose resources
  Future<void> dispose() async {
    _flushTimer?.cancel();
    await _flush();
    await _database.close();
    await _logStreamController.close();
    _initialized = false;
  }
}
