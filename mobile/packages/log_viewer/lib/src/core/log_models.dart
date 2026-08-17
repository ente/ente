import 'package:flutter/material.dart';

class LogEntry {
  final int? id;
  final String message;
  final String level;
  final DateTime timestamp;
  final String loggerName;
  final String? error;
  final String? stackTrace;
  final String processPrefix;

  LogEntry({
    this.id,
    required this.message,
    required this.level,
    required this.timestamp,
    required this.loggerName,
    this.error,
    this.stackTrace,
    this.processPrefix = '',
  });

  factory LogEntry.fromMap(Map<String, dynamic> map) {
    return LogEntry(
      id: map['id'] as int?,
      message: map['message'] as String,
      level: map['level'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      loggerName: map['logger_name'] as String,
      error: map['error'] as String?,
      stackTrace: map['stack_trace'] as String?,
      processPrefix: map['process_prefix'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'message': message,
      'level': level,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'logger_name': loggerName,
      'error': error,
      'stack_trace': stackTrace,
      'process_prefix': processPrefix,
    };
  }

  Color get levelColor {
    switch (level.toUpperCase()) {
      case 'SHOUT':
      case 'SEVERE':
        return Colors.red;
      case 'WARNING':
        return Colors.orange;
      case 'INFO':
        return Colors.blue;
      case 'CONFIG':
        return Colors.green;
      case 'FINE':
      case 'FINER':
      case 'FINEST':
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  Color? get backgroundColor {
    switch (level.toUpperCase()) {
      case 'SHOUT':
      case 'SEVERE':
        return Colors.red.withValues(alpha: 0.1);
      case 'WARNING':
        return Colors.orange.withValues(alpha: 0.1);
      default:
        return null;
    }
  }

  String get truncatedMessage {
    final lines = message.split('\n');
    const maxLines = 4;

    if (lines.length <= maxLines) {
      return message;
    }

    return '${lines.take(maxLines).join('\n')}...';
  }

  String get formattedTime {
    final hour = timestamp.hour.toString().padLeft(2, '0');
    final minute = timestamp.minute.toString().padLeft(2, '0');
    final second = timestamp.second.toString().padLeft(2, '0');
    final millis = timestamp.millisecond.toString().padLeft(3, '0');
    return '$hour:$minute:$second.$millis';
  }

  String get processDisplayName {
    if (processPrefix.isEmpty) {
      return 'Foreground';
    }
    final cleanPrefix = processPrefix.replaceAll(RegExp(r'[\[\]]'), '');
    switch (cleanPrefix) {
      case 'fbg':
        return 'Firebase Background';
      default:
        return cleanPrefix.isEmpty ? 'Foreground' : cleanPrefix;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('[$formattedTime] [$loggerName] [$level]');
    buffer.writeln(message);
    if (error != null) {
      buffer.writeln('Error: $error');
    }
    if (stackTrace != null) {
      buffer.writeln('Stack trace:\n$stackTrace');
    }
    return buffer.toString();
  }
}

class LogFilter {
  final Set<String> selectedLoggers;
  final Set<String> selectedLevels;
  final Set<String> selectedProcesses;
  final String? searchQuery;
  final DateTime? startTime;
  final DateTime? endTime;
  final bool sortNewestFirst;

  const LogFilter({
    this.selectedLoggers = const {},
    this.selectedLevels = const {},
    this.selectedProcesses = const {},
    this.searchQuery,
    this.startTime,
    this.endTime,
    this.sortNewestFirst = true,
  });

  LogFilter copyWith({
    Set<String>? selectedLoggers,
    Set<String>? selectedLevels,
    Set<String>? selectedProcesses,
    String? searchQuery,
    DateTime? startTime,
    DateTime? endTime,
    bool? sortNewestFirst,
    bool clearSearchQuery = false,
    bool clearTimeFilter = false,
  }) {
    return LogFilter(
      selectedLoggers: selectedLoggers ?? this.selectedLoggers,
      selectedLevels: selectedLevels ?? this.selectedLevels,
      selectedProcesses: selectedProcesses ?? this.selectedProcesses,
      searchQuery: clearSearchQuery ? null : (searchQuery ?? this.searchQuery),
      startTime: clearTimeFilter ? null : (startTime ?? this.startTime),
      endTime: clearTimeFilter ? null : (endTime ?? this.endTime),
      sortNewestFirst: sortNewestFirst ?? this.sortNewestFirst,
    );
  }

  bool get hasActiveFilters {
    return selectedLoggers.isNotEmpty ||
        selectedLevels.isNotEmpty ||
        selectedProcesses.isNotEmpty ||
        (searchQuery != null && searchQuery!.isNotEmpty) ||
        startTime != null ||
        endTime != null;
  }

  static const LogFilter empty = LogFilter();
}

class LoggerStatistic {
  final String loggerName;
  final int logCount;
  final double percentage;

  const LoggerStatistic({
    required this.loggerName,
    required this.logCount,
    required this.percentage,
  });

  int get count => logCount;

  String get formattedPercentage {
    if (percentage >= 10) {
      return '${percentage.toStringAsFixed(1)}%';
    } else if (percentage >= 1) {
      return '${percentage.toStringAsFixed(1)}%';
    } else {
      return '${percentage.toStringAsFixed(2)}%';
    }
  }
}

class LogLevels {
  static const List<String> all = [
    'ALL',
    'FINEST',
    'FINER',
    'FINE',
    'CONFIG',
    'INFO',
    'WARNING',
    'SEVERE',
    'SHOUT',
    'OFF',
  ];

  static const List<String> defaultVisible = [
    'INFO',
    'WARNING',
    'SEVERE',
    'SHOUT',
  ];
}

class TimeRange {
  final DateTime start;
  final DateTime end;

  const TimeRange({required this.start, required this.end});
}
