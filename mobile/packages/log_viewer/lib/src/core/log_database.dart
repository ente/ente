import 'dart:async';

import 'package:log_viewer/src/core/log_models.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages SQLite database for log storage
class LogDatabase {
  static const String _databaseName = 'log_viewer.db';
  static const String _tableName = 'logs';
  static const int _databaseVersion = 1;

  final int maxEntries;
  Database? _database;

  LogDatabase({this.maxEntries = 10000});

  /// Get database instance
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message TEXT NOT NULL,
        level TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        logger_name TEXT NOT NULL,
        error TEXT,
        stack_trace TEXT,
        process_prefix TEXT NOT NULL DEFAULT ''
      )
    ''');

    // Minimal indexes for write performance - only timestamp for ordering
    await db.execute(
      'CREATE INDEX idx_timestamp ON $_tableName(timestamp DESC)',
    );
  }

  /// Called when database is opened
  Future<void> _onOpen(Database db) async {
    // Enable write-ahead logging for better performance
    // Use rawQuery for PRAGMA commands to avoid permission issues
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }

  /// Insert a single log entry
  Future<int> insertLog(LogEntry entry) async {
    final db = await database;
    final id = await db.insert(_tableName, entry.toMap());

    // Auto-truncate if needed
    await _truncateIfNeeded(db);

    return id;
  }

  /// Insert multiple log entries in a batch
  Future<void> insertLogs(List<LogEntry> entries) async {
    if (entries.isEmpty) return;

    final db = await database;
    final batch = db.batch();

    for (final entry in entries) {
      batch.insert(_tableName, entry.toMap());
    }

    await batch.commit(noResult: true);
    await _truncateIfNeeded(db);
  }

  /// Get logs with optional filtering
  Future<List<LogEntry>> getLogs({
    LogFilter? filter,
    int limit = 250,
    int offset = 0,
  }) async {
    final db = await database;

    // Build WHERE clause
    final conditions = <String>[];
    final args = <dynamic>[];

    if (filter != null) {
      // Logger filter
      if (filter.selectedLoggers.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedLoggers.length,
          '?',
        ).join(',');
        conditions.add('logger_name IN ($placeholders)');
        args.addAll(filter.selectedLoggers);
      }

      // Level filter
      if (filter.selectedLevels.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedLevels.length,
          '?',
        ).join(',');
        conditions.add('level IN ($placeholders)');
        args.addAll(filter.selectedLevels);
      }

      // Process prefix filter
      if (filter.selectedProcesses.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedProcesses.length,
          '?',
        ).join(',');
        conditions.add('process_prefix IN ($placeholders)');
        args.addAll(filter.selectedProcesses);
      }

      // Search query
      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        conditions.add('(message LIKE ? OR error LIKE ?)');
        final searchPattern = '%${filter.searchQuery}%';
        args.add(searchPattern);
        args.add(searchPattern);
      }

      // Time range
      if (filter.startTime != null) {
        conditions.add('timestamp >= ?');
        args.add(filter.startTime!.millisecondsSinceEpoch);
      }
      if (filter.endTime != null) {
        conditions.add('timestamp <= ?');
        args.add(filter.endTime!.millisecondsSinceEpoch);
      }
    }

    final whereClause = conditions.isEmpty ? null : conditions.join(' AND ');

    final results = await db.query(
      _tableName,
      where: whereClause,
      whereArgs: args.isEmpty ? null : args,
      orderBy: filter?.sortNewestFirst == false
          ? 'timestamp ASC'
          : 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return results.map((map) => LogEntry.fromMap(map)).toList();
  }

  /// Get unique logger names for filtering
  Future<List<String>> getUniqueLoggers() async {
    final db = await database;
    final results = await db.rawQuery(
      'SELECT DISTINCT logger_name FROM $_tableName ORDER BY logger_name',
    );

    return results.map((row) => row['logger_name'] as String).toList();
  }

  /// Get unique process prefixes for filtering
  Future<List<String>> getUniqueProcesses() async {
    final db = await database;
    final results = await db.rawQuery(
      'SELECT DISTINCT process_prefix FROM $_tableName WHERE process_prefix != "" ORDER BY process_prefix',
    );

    final prefixes = results
        .map((row) => row['process_prefix'] as String)
        .toList();

    // Always include 'Foreground' as an option for empty prefix
    final uniquePrefixes = <String>[''];
    uniquePrefixes.addAll(prefixes);

    return uniquePrefixes;
  }

  /// Get count of logs matching filter
  Future<int> getLogCount({LogFilter? filter}) async {
    final db = await database;

    if (filter == null || !filter.hasActiveFilters) {
      final result = await db.rawQuery(
        'SELECT COUNT(*) as count FROM $_tableName',
      );
      return result.first['count'] as int;
    }

    // Build WHERE clause (same as getLogs)
    final conditions = <String>[];
    final args = <dynamic>[];

    if (filter.selectedLoggers.isNotEmpty) {
      final placeholders = List.filled(
        filter.selectedLoggers.length,
        '?',
      ).join(',');
      conditions.add('logger_name IN ($placeholders)');
      args.addAll(filter.selectedLoggers);
    }

    if (filter.selectedLevels.isNotEmpty) {
      final placeholders = List.filled(
        filter.selectedLevels.length,
        '?',
      ).join(',');
      conditions.add('level IN ($placeholders)');
      args.addAll(filter.selectedLevels);
    }

    if (filter.selectedProcesses.isNotEmpty) {
      final placeholders = List.filled(
        filter.selectedProcesses.length,
        '?',
      ).join(',');
      conditions.add('process_prefix IN ($placeholders)');
      args.addAll(filter.selectedProcesses);
    }

    if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
      conditions.add('(message LIKE ? OR error LIKE ?)');
      final searchPattern = '%${filter.searchQuery}%';
      args.add(searchPattern);
      args.add(searchPattern);
    }

    if (filter.startTime != null) {
      conditions.add('timestamp >= ?');
      args.add(filter.startTime!.millisecondsSinceEpoch);
    }
    if (filter.endTime != null) {
      conditions.add('timestamp <= ?');
      args.add(filter.endTime!.millisecondsSinceEpoch);
    }

    final whereClause = conditions.join(' AND ');
    final query =
        'SELECT COUNT(*) as count FROM $_tableName WHERE $whereClause';
    final result = await db.rawQuery(query, args);

    return result.first['count'] as int;
  }

  /// Clear all logs
  Future<void> clearLogs() async {
    final db = await database;
    await db.delete(_tableName);
  }

  /// Clear logs by logger name
  Future<void> clearLogsByLogger(String loggerName) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'logger_name = ?',
      whereArgs: [loggerName],
    );
  }

  /// Truncate old logs if over limit
  Future<void> _truncateIfNeeded(Database db) async {
    final countResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM $_tableName',
    );
    final count = countResult.first['count'] as int;

    // When we reach 11k+ entries, keep only the last 10k
    if (count >= maxEntries + 1000) {
      final toDelete = count - maxEntries;

      // Delete oldest entries
      await db.execute(
        '''
        DELETE FROM $_tableName 
        WHERE id IN (
          SELECT id FROM $_tableName 
          ORDER BY timestamp ASC 
          LIMIT ?
        )
      ''',
        [toDelete],
      );
    }
  }

  /// Get logger statistics with count and percentage
  Future<List<LoggerStatistic>> getLoggerStatistics({LogFilter? filter}) async {
    final db = await database;

    // Build WHERE clause (same as getLogs)
    final conditions = <String>[];
    final args = <dynamic>[];

    if (filter != null) {
      if (filter.selectedLoggers.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedLoggers.length,
          '?',
        ).join(',');
        conditions.add('logger_name IN ($placeholders)');
        args.addAll(filter.selectedLoggers);
      }

      if (filter.selectedLevels.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedLevels.length,
          '?',
        ).join(',');
        conditions.add('level IN ($placeholders)');
        args.addAll(filter.selectedLevels);
      }

      if (filter.selectedProcesses.isNotEmpty) {
        final placeholders = List.filled(
          filter.selectedProcesses.length,
          '?',
        ).join(',');
        conditions.add('process_prefix IN ($placeholders)');
        args.addAll(filter.selectedProcesses);
      }

      if (filter.searchQuery != null && filter.searchQuery!.isNotEmpty) {
        conditions.add('(message LIKE ? OR error LIKE ?)');
        final searchPattern = '%${filter.searchQuery}%';
        args.add(searchPattern);
        args.add(searchPattern);
      }

      if (filter.startTime != null) {
        conditions.add('timestamp >= ?');
        args.add(filter.startTime!.millisecondsSinceEpoch);
      }
      if (filter.endTime != null) {
        conditions.add('timestamp <= ?');
        args.add(filter.endTime!.millisecondsSinceEpoch);
      }
    }

    final whereClause = conditions.isEmpty
        ? ''
        : 'WHERE ${conditions.join(' AND ')}';

    // Get total count for percentage calculation
    final totalQuery = 'SELECT COUNT(*) as total FROM $_tableName $whereClause';
    final totalResult = await db.rawQuery(totalQuery, args);
    final totalCount = totalResult.first['total'] as int;

    if (totalCount == 0) return [];

    // Get logger statistics using single optimized query
    final statsQuery =
        '''
      SELECT 
        logger_name,
        COUNT(*) as count,
        (COUNT(*) * 100.0 / $totalCount) as percentage
      FROM $_tableName 
      $whereClause
      GROUP BY logger_name 
      ORDER BY count DESC
    ''';

    final results = await db.rawQuery(statsQuery, args);

    return results
        .map(
          (row) => LoggerStatistic(
            loggerName: row['logger_name'] as String,
            logCount: row['count'] as int,
            percentage: row['percentage'] as double,
          ),
        )
        .toList();
  }

  /// Get time range of all logs
  Future<TimeRange?> getTimeRange() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        MIN(timestamp) as min_timestamp,
        MAX(timestamp) as max_timestamp
      FROM $_tableName
    ''');

    if (result.isNotEmpty && result.first['min_timestamp'] != null) {
      return TimeRange(
        start: DateTime.fromMillisecondsSinceEpoch(
          result.first['min_timestamp'] as int,
        ),
        end: DateTime.fromMillisecondsSinceEpoch(
          result.first['max_timestamp'] as int,
        ),
      );
    }

    return null;
  }

  /// Get all log timestamps for timeline visualization
  Future<List<DateTime>> getLogTimestamps() async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT timestamp
      FROM $_tableName
      ORDER BY timestamp ASC
    ''');

    return result
        .map(
          (row) => DateTime.fromMillisecondsSinceEpoch(row['timestamp'] as int),
        )
        .toList();
  }

  /// Close database connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}
