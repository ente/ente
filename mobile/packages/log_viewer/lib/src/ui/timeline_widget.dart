import 'package:flutter/material.dart';

class TimelineWidget extends StatefulWidget {
  final DateTime startTime;
  final DateTime endTime;
  final DateTime currentStart;
  final DateTime currentEnd;
  final Function(DateTime start, DateTime end) onTimeRangeChanged;
  final List<DateTime> logTimestamps;

  const TimelineWidget({
    super.key,
    required this.startTime,
    required this.endTime,
    required this.currentStart,
    required this.currentEnd,
    required this.onTimeRangeChanged,
    this.logTimestamps = const [],
  });

  @override
  State<TimelineWidget> createState() => _TimelineWidgetState();
}

class _TimelineWidgetState extends State<TimelineWidget> {
  late double _leftPosition;
  late double _rightPosition;
  bool _isDraggingLeft = false;
  bool _isDraggingRight = false;

  @override
  void initState() {
    super.initState();
    _updatePositions();
  }

  @override
  void didUpdateWidget(TimelineWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentStart != widget.currentStart ||
        oldWidget.currentEnd != widget.currentEnd ||
        oldWidget.startTime != widget.startTime ||
        oldWidget.endTime != widget.endTime) {
      _updatePositions();
    }
  }

  void _updatePositions() {
    final totalDuration = widget.endTime
        .difference(widget.startTime)
        .inMilliseconds;
    final startOffset = widget.currentStart
        .difference(widget.startTime)
        .inMilliseconds;
    final endOffset = widget.currentEnd
        .difference(widget.startTime)
        .inMilliseconds;

    _leftPosition = startOffset / totalDuration;
    _rightPosition = endOffset / totalDuration;
  }

  void _onPanUpdate(DragUpdateDetails details, bool isLeft) {
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final double width = renderBox.size.width - 40; // Account for handle width

    // Convert global position to local position within the timeline track
    final Offset globalPosition = details.globalPosition;
    final Offset localPosition = renderBox.globalToLocal(globalPosition);
    final double localX =
        localPosition.dx - 20; // Account for left handle width
    final double position = (localX / width).clamp(0.0, 1.0);

    setState(() {
      if (isLeft) {
        _leftPosition = position.clamp(0.0, _rightPosition - 0.01);
      } else {
        _rightPosition = position.clamp(_leftPosition + 0.01, 1.0);
      }
    });

    final totalDuration = widget.endTime
        .difference(widget.startTime)
        .inMilliseconds;
    final newStart = widget.startTime.add(
      Duration(milliseconds: (_leftPosition * totalDuration).round()),
    );
    final newEnd = widget.startTime.add(
      Duration(milliseconds: (_rightPosition * totalDuration).round()),
    );

    widget.onTimeRangeChanged(newStart, newEnd);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 120,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Timeline Filter',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Timeline track
                    Positioned(
                      left: 20,
                      right: 20,
                      top: 20,
                      bottom: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.outline.withValues(
                              alpha: 0.3,
                            ),
                            width: 1,
                          ),
                        ),
                        child: _buildLogDensityIndicator(
                          constraints.maxWidth - 40,
                        ),
                      ),
                    ),

                    // Selected range
                    Positioned(
                      left: 20 + (_leftPosition * (constraints.maxWidth - 40)),
                      right:
                          constraints.maxWidth -
                          20 -
                          (_rightPosition * (constraints.maxWidth - 40)),
                      top: 20,
                      bottom: 20,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.7,
                            ),
                            width: 1,
                          ),
                        ),
                      ),
                    ),

                    // Left handle
                    Positioned(
                      left: (_leftPosition * (constraints.maxWidth - 40)),
                      top: 12,
                      child: GestureDetector(
                        onPanUpdate: (details) => _onPanUpdate(details, true),
                        onPanStart: (_) =>
                            setState(() => _isDraggingLeft = true),
                        onPanEnd: (_) =>
                            setState(() => _isDraggingLeft = false),
                        child: Container(
                          width: 20,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _isDraggingLeft
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.8,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 12,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),

                    // Right handle
                    Positioned(
                      left: (_rightPosition * (constraints.maxWidth - 40)),
                      top: 12,
                      child: GestureDetector(
                        onPanUpdate: (details) => _onPanUpdate(details, false),
                        onPanStart: (_) =>
                            setState(() => _isDraggingRight = true),
                        onPanEnd: (_) =>
                            setState(() => _isDraggingRight = false),
                        child: Container(
                          width: 20,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _isDraggingRight
                                ? theme.colorScheme.primary
                                : theme.colorScheme.primary.withValues(
                                    alpha: 0.8,
                                  ),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.drag_indicator,
                            size: 12,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Time labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatTime(widget.currentStart),
                style: theme.textTheme.bodySmall,
              ),
              Text(
                _formatTime(widget.currentEnd),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogDensityIndicator(double width) {
    if (widget.logTimestamps.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final totalDuration = widget.endTime
        .difference(widget.startTime)
        .inMilliseconds;
    const bucketCount = 50;
    final bucketDuration = totalDuration / bucketCount;
    final buckets = List<int>.filled(bucketCount, 0);

    // Count logs in each bucket
    for (final timestamp in widget.logTimestamps) {
      final offset = timestamp.difference(widget.startTime).inMilliseconds;
      if (offset >= 0 && offset <= totalDuration) {
        final bucketIndex = (offset / bucketDuration).floor().clamp(
          0,
          bucketCount - 1,
        );
        buckets[bucketIndex]++;
      }
    }

    final maxCount = buckets.reduce((a, b) => a > b ? a : b);
    if (maxCount == 0) return const SizedBox.shrink();

    return Row(
      children: buckets.map((count) {
        final intensity = count / maxCount;
        return Expanded(
          child: Container(
            height: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 0.5),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(
                alpha: intensity * 0.6,
              ),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        );
      }).toList(),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
