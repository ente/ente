import 'dart:async';

import 'package:flutter/material.dart';
import 'package:log_viewer/src/core/log_models.dart';
import 'package:log_viewer/src/core/log_store.dart';
import 'package:log_viewer/src/ui/log_detail_page.dart';
import 'package:log_viewer/src/ui/log_filter_dialog.dart';
import 'package:log_viewer/src/ui/log_list_tile.dart';
import 'package:log_viewer/src/ui/logger_statistics_page.dart';
import 'package:log_viewer/src/ui/timeline_widget.dart';
import 'package:share_plus/share_plus.dart';

/// Main log viewer page
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> {
  final LogStore _logStore = LogStore.instance;
  final TextEditingController _searchController = TextEditingController();

  List<LogEntry> _logs = [];
  List<String> _availableLoggers = [];
  List<String> _availableProcesses = [];
  LogFilter _filter = const LogFilter(
    selectedLevels: {'WARNING', 'SEVERE', 'SHOUT'},
  );
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreLogs = true;
  int _currentOffset = 0;
  static const int _pageSize = 100; // Load 100 logs at a time
  StreamSubscription<LogEntry>? _logStreamSubscription;

  // Time filtering state
  bool _timeFilterEnabled = false;

  // Timeline state
  DateTime? _overallStartTime;
  DateTime? _overallEndTime;
  DateTime? _timelineStartTime;
  DateTime? _timelineEndTime;
  List<DateTime> _logTimestamps = [];

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadLoggers();
    await _loadProcesses();
    await _initializeTimeline();
    await _loadLogs();

    // Listen for new logs
    _logStreamSubscription = _logStore.logStream.listen((_) {
      // Debounce updates to avoid too frequent refreshes
      _scheduleRefresh();
    });
  }

  Future<void> _initializeTimeline() async {
    final timeRange = await _logStore.getTimeRange();
    if (timeRange != null) {
      setState(() {
        _overallStartTime = timeRange.start;
        _overallEndTime = timeRange.end;
        _timelineStartTime = timeRange.start;
        _timelineEndTime = timeRange.end;
      });
    }
    await _loadLogTimestamps();
  }

  Future<void> _loadLogTimestamps() async {
    final timestamps = await _logStore.getLogTimestamps();
    setState(() {
      _logTimestamps = timestamps;
    });
  }

  void _onTimelineRangeChanged(DateTime start, DateTime end) {
    setState(() {
      _timelineStartTime = start;
      _timelineEndTime = end;
      _filter = _filter.copyWith(startTime: start, endTime: end);
    });
    _loadLogs();
  }

  Timer? _refreshTimer;
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _loadLogs();
      }
    });
  }

  Future<void> _loadLogs({bool reset = true}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _currentOffset = 0;
        _hasMoreLogs = true;
        _logs.clear();
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final logs = await _logStore.getLogs(
        filter: _filter,
        limit: _pageSize,
        offset: _currentOffset,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _logs = logs;
            _isLoading = false;
          } else {
            _logs.addAll(logs);
            _isLoadingMore = false;
          }

          _currentOffset += logs.length;
          _hasMoreLogs = logs.length == _pageSize;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load logs: $e')));
      }
    }
  }

  Future<void> _loadMoreLogs() async {
    if (!_hasMoreLogs || _isLoadingMore) return;
    await _loadLogs(reset: false);
  }

  Future<void> _loadLoggers() async {
    try {
      final loggers = await _logStore.getLoggerNames();
      if (mounted) {
        setState(() => _availableLoggers = loggers);
      }
    } catch (e) {
      debugPrint('Failed to load logger names: $e');
    }
  }

  Future<void> _loadProcesses() async {
    try {
      final processes = await _logStore.getProcessNames();
      if (mounted) {
        setState(() => _availableProcesses = processes);
      }
    } catch (e) {
      debugPrint('Failed to load process names: $e');
    }
  }

  void _onSearchChanged(String query) {
    // Parse query for special syntax like "logger:SomeName"
    String? searchText = query;
    Set<String>? loggerFilters;

    if (query.isNotEmpty) {
      // Regular expression to match logger:name patterns
      final loggerPattern = RegExp(r'logger:(\S+)');
      final matches = loggerPattern.allMatches(query);

      if (matches.isNotEmpty) {
        loggerFilters = {};
        for (final match in matches) {
          final loggerName = match.group(1);
          if (loggerName != null) {
            // Support wildcards (e.g., Auth* matches AuthService, Authentication, etc.)
            if (loggerName.endsWith('*')) {
              final prefix = loggerName.substring(0, loggerName.length - 1);
              // Find all loggers that start with this prefix
              for (final logger in _availableLoggers) {
                if (logger.startsWith(prefix)) {
                  loggerFilters.add(logger);
                }
              }
            } else {
              loggerFilters.add(loggerName);
            }
          }
        }

        // Remove logger:name patterns from search text
        searchText = query.replaceAll(loggerPattern, '').trim();
        if (searchText.isEmpty) {
          searchText = null;
        }
      }
    } else {
      // Clear logger filters when search is empty
      loggerFilters = {};
    }

    setState(() {
      // Only update logger filters if logger: syntax was found or query is empty
      final newLoggerFilters =
          loggerFilters ??
          (query.isEmpty ? <String>{} : _filter.selectedLoggers);

      _filter = _filter.copyWith(
        searchQuery: searchText,
        clearSearchQuery: query.isEmpty,
        selectedLoggers: newLoggerFilters,
      );
    });
    _loadLogs();
  }

  void _updateTimeFilter() {
    setState(() {
      if (_timeFilterEnabled &&
          _timelineStartTime != null &&
          _timelineEndTime != null) {
        _filter = _filter.copyWith(
          startTime: _timelineStartTime,
          endTime: _timelineEndTime,
        );
      } else {
        _filter = _filter.copyWith(clearTimeFilter: true);
      }
    });
    _loadLogs();
  }

  // String _formatTimeRange(double hours) {
  //   if (hours < 1) {
  //     final minutes = (hours * 60).round();
  //     return '${minutes}m';
  //   } else if (hours < 24) {
  //     return '${hours.round()}h';
  //   } else {
  //     final days = (hours / 24).round();
  //     return '${days}d';
  //   }
  // }

  Future<void> _showFilterDialog() async {
    final newFilter = await showDialog<LogFilter>(
      context: context,
      builder: (context) => LogFilterDialog(
        availableLoggers: _availableLoggers,
        availableProcesses: _availableProcesses,
        currentFilter: _filter,
      ),
    );

    if (newFilter != null && mounted) {
      setState(() => _filter = newFilter);
      await _loadLogs();
    }
  }

  Future<void> _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text('Are you sure you want to clear all logs?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _logStore.clearLogs();
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Logs cleared')));
      }
    }
  }

  Future<void> _exportLogs() async {
    try {
      final logText = await _logStore.exportLogs(filter: _filter);

      await SharePlus.instance.share(
        ShareParams(text: logText, subject: 'App Logs'),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to export logs: $e')));
      }
    }
  }

  void _toggleSort() {
    setState(() {
      _filter = _filter.copyWith(sortNewestFirst: !_filter.sortNewestFirst);
    });
    _loadLogs();
  }

  void _showAnalytics() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => LoggerStatisticsPage(filter: _filter),
      ),
    );

    // If a logger filter was returned, apply it to the search box
    if (result != null && mounted) {
      _searchController.text = result;
      _onSearchChanged(result);
    }
  }

  void _showLogDetail(LogEntry log) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => LogDetailPage(log: log)),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _logStreamSubscription?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        elevation: 0,
        actions: [
          if (_filter.hasActiveFilters)
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.filter_list),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              onPressed: _showFilterDialog,
              tooltip: 'Filters',
            )
          else
            IconButton(
              icon: const Icon(Icons.filter_list),
              onPressed: _showFilterDialog,
              tooltip: 'Filters',
            ),
          IconButton(
            icon: Icon(
              _filter.sortNewestFirst
                  ? Icons.arrow_downward
                  : Icons.arrow_upward,
            ),
            onPressed: _toggleSort,
            tooltip: _filter.sortNewestFirst
                ? 'Sort oldest first'
                : 'Sort newest first',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'analytics':
                  _showAnalytics();
                  break;
                case 'clear':
                  _clearLogs();
                  break;
                case 'export':
                  _exportLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'analytics',
                child: ListTile(
                  leading: Icon(Icons.analytics),
                  title: Text('View Analytics'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.share),
                  title: Text('Export Logs'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.clear_all, color: Colors.red),
                  title: Text(
                    'Clear Logs',
                    style: TextStyle(color: Colors.red),
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: theme.appBarTheme.backgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search logs...',
                hintStyle: const TextStyle(fontSize: 14),
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
              onChanged: _onSearchChanged,
            ),
          ),

          // Timeline filter
          if (_overallStartTime != null && _overallEndTime != null) ...[
            Container(
              color: theme.appBarTheme.backgroundColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.timeline,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Timeline Filter',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      _timeFilterEnabled
                          ? Icons.timeline
                          : Icons.timeline_outlined,
                      color: _timeFilterEnabled
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                    onPressed: () {
                      setState(() {
                        _timeFilterEnabled = !_timeFilterEnabled;
                        if (_timeFilterEnabled) {
                          // Reset timeline to full range when enabled
                          _timelineStartTime = _overallStartTime;
                          _timelineEndTime = _overallEndTime;
                        }
                      });
                      _updateTimeFilter();
                    },
                    tooltip: _timeFilterEnabled
                        ? 'Disable Timeline Filter'
                        : 'Enable Timeline Filter',
                  ),
                ],
              ),
            ),
            if (_timeFilterEnabled) ...[
              TimelineWidget(
                startTime: _overallStartTime!,
                endTime: _overallEndTime!,
                currentStart: _timelineStartTime ?? _overallStartTime!,
                currentEnd: _timelineEndTime ?? _overallEndTime!,
                onTimeRangeChanged: _onTimelineRangeChanged,
                logTimestamps: _logTimestamps,
              ),
            ],
          ],

          // Active filters display
          if (_filter.hasActiveFilters)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_filter.selectedLoggers.isNotEmpty)
                    ..._filter.selectedLoggers.map(
                      (logger) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Chip(
                          label: Text(
                            logger,
                            style: const TextStyle(fontSize: 12),
                          ),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              final newLoggers = Set<String>.from(
                                _filter.selectedLoggers,
                              );
                              newLoggers.remove(logger);
                              _filter = _filter.copyWith(
                                selectedLoggers: newLoggers,
                              );
                            });
                            _loadLogs();
                          },
                        ),
                      ),
                    ),
                  if (_filter.selectedLevels.isNotEmpty)
                    ..._filter.selectedLevels.map(
                      (level) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Chip(
                          label: Text(
                            level,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: LogEntry(
                            message: '',
                            level: level,
                            timestamp: DateTime.now(),
                            loggerName: '',
                          ).levelColor.withValues(alpha: 0.2),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              final newLevels = Set<String>.from(
                                _filter.selectedLevels,
                              );
                              newLevels.remove(level);
                              _filter = _filter.copyWith(
                                selectedLevels: newLevels,
                              );
                            });
                            _loadLogs();
                          },
                        ),
                      ),
                    ),
                  if (_filter.selectedProcesses.isNotEmpty)
                    ..._filter.selectedProcesses.map(
                      (process) => Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Chip(
                          label: Text(
                            LogEntry(
                              message: '',
                              level: 'INFO',
                              timestamp: DateTime.now(),
                              loggerName: '',
                              processPrefix: process,
                            ).processDisplayName,
                            style: const TextStyle(fontSize: 12),
                          ),
                          backgroundColor: Colors.purple.withValues(alpha: 0.2),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() {
                              final newProcesses = Set<String>.from(
                                _filter.selectedProcesses,
                              );
                              newProcesses.remove(process);
                              _filter = _filter.copyWith(
                                selectedProcesses: newProcesses,
                              );
                            });
                            _loadLogs();
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // Log list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _logs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: theme.disabledColor),
                        const SizedBox(height: 16),
                        Text(
                          _filter.hasActiveFilters
                              ? 'No logs match the current filters'
                              : 'No logs available',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.disabledColor,
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadLogs,
                    child: ListView.separated(
                      itemCount: _logs.length + (_hasMoreLogs ? 1 : 0),
                      separatorBuilder: (context, index) =>
                          index >= _logs.length
                          ? const SizedBox.shrink()
                          : const Divider(height: 1),
                      itemBuilder: (context, index) {
                        // Show loading indicator at the bottom
                        if (index >= _logs.length) {
                          if (_isLoadingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          } else {
                            // Trigger loading more when reaching the end
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              _loadMoreLogs();
                            });
                            return const SizedBox.shrink();
                          }
                        }

                        final log = _logs[index];
                        return LogListTile(
                          log: log,
                          onTap: () => _showLogDetail(log),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
