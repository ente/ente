import 'package:flutter/material.dart';
import 'package:log_viewer/src/core/log_models.dart';
import 'package:log_viewer/src/core/log_store.dart';

/// Page showing logger statistics with percentage breakdown
class LoggerStatisticsPage extends StatefulWidget {
  final LogFilter filter;

  const LoggerStatisticsPage({super.key, required this.filter});

  @override
  State<LoggerStatisticsPage> createState() => _LoggerStatisticsPageState();
}

class _LoggerStatisticsPageState extends State<LoggerStatisticsPage> {
  final LogStore _logStore = LogStore.instance;
  List<LoggerStatistic> _statistics = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stats = await _logStore.getLoggerStatistics(filter: widget.filter);
      if (mounted) {
        setState(() {
          _statistics = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Color _getLoggerColor(int index, double percentage) {
    // Color coding based on percentage
    if (percentage > 50) return Colors.red.shade400;
    if (percentage > 20) return Colors.orange.shade400;
    if (percentage > 10) return Colors.blue.shade400;
    return Colors.green.shade400;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Logger Analytics'), elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Failed to load statistics',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadStatistics,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          : _statistics.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.analytics_outlined,
                    size: 64,
                    color: theme.disabledColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No log data available',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.disabledColor,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                // Summary cards
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'Total Logs',
                          value: _statistics
                              .fold(0, (sum, stat) => sum + stat.count)
                              .toString(),
                          icon: Icons.notes,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _SummaryCard(
                          title: 'Loggers',
                          value: _statistics.length.toString(),
                          icon: Icons.category,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),

                // Statistics list
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadStatistics,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _statistics.length,
                      itemBuilder: (context, index) {
                        final stat = _statistics[index];
                        final color = _getLoggerColor(index, stat.percentage);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              // Navigate back to log viewer with logger filter in search
                              Navigator.pop(
                                context,
                                'logger:${stat.loggerName}',
                              );
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          stat.loggerName,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w500,
                                              ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        stat.formattedPercentage,
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                              color: color,
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: LinearProgressIndicator(
                                          value: stat.percentage / 100,
                                          backgroundColor: color.withValues(
                                            alpha: 0.2,
                                          ),
                                          valueColor: AlwaysStoppedAnimation(
                                            color,
                                          ),
                                          minHeight: 6,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${stat.count} logs',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
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

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
