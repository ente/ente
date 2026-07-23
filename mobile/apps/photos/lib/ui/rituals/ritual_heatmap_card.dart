import "dart:io";
import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:share_plus/share_plus.dart";

class RitualHeatmapCard extends StatefulWidget {
  const RitualHeatmapCard({
    required this.ritual,
    required this.progress,
    this.compact = false,
    this.allowHorizontalScroll = true,
    this.showShareButton = false,
    this.daysToShow = 365,
    super.key,
  });

  final Ritual ritual;
  final RitualProgress? progress;
  final bool compact;
  final bool allowHorizontalScroll;
  final bool showShareButton;
  final int daysToShow;

  @override
  State<RitualHeatmapCard> createState() => _RitualHeatmapCardState();
}

class _RitualHeatmapCardState extends State<RitualHeatmapCard> {
  static final Logger _logger = Logger("RitualHeatmapCard");
  final GlobalKey _repaintKey = GlobalKey();
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final progress = widget.progress;
    final dayKeys = progress?.completedDayKeys ?? const <int>{};
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(
      todayMidnight.year,
      todayMidnight.month,
      todayMidnight.day - max(0, widget.daysToShow - 1),
    );

    final title = widget.ritual.title.isEmpty ? "Ritual" : widget.ritual.title;
    final header = "${widget.ritual.icon} $title";

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.brightness == Brightness.dark
              ? colorScheme.backgroundElevated2
              : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colorScheme.strokeFaint),
        ),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    header,
                    style: textTheme.bodyMuted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.showShareButton)
                  IconButton(
                    key: _shareButtonKey,
                    onPressed: progress == null ? null : _shareHeatmap,
                    tooltip: MaterialLocalizations.of(context).shareButtonLabel,
                    icon: const Icon(Icons.share_rounded),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            RepaintBoundary(
              key: _repaintKey,
              child: widget.allowHorizontalScroll
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const ClampingScrollPhysics(),
                      child: _Heatmap(
                        ritual: widget.ritual,
                        completedDayKeys: dayKeys,
                        startDay: startDay,
                        endDayInclusive: todayMidnight,
                        compact: widget.compact,
                      ),
                    )
                  : _Heatmap(
                      ritual: widget.ritual,
                      completedDayKeys: dayKeys,
                      startDay: startDay,
                      endDayInclusive: todayMidnight,
                      compact: widget.compact,
                    ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    "Current: ${progress.currentStreak}",
                    style: textTheme.smallMuted,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "Month: ${progress.longestStreakThisMonth}",
                    style: textTheme.smallMuted,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    "All-time: ${progress.longestStreakOverall}",
                    style: textTheme.smallMuted,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _shareHeatmap() async {
    try {
      final RenderObject? renderObject = _repaintKey.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError("Heatmap boundary not found");
      }
      final pixelRatio = (MediaQuery.devicePixelRatioOf(context) * 2).clamp(
        2.0,
        3.5,
      );
      final ui.Image image = await renderObject.toImage(pixelRatio: pixelRatio);
      final ByteData? bytes = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      final data = bytes?.buffer.asUint8List();
      if (data == null || data.isEmpty) {
        throw StateError("Failed to render heatmap image");
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        "${dir.path}/ritual_heatmap_${widget.ritual.id}_${DateTime.now().millisecondsSinceEpoch}.png",
      );
      await file.writeAsBytes(data, flush: true);

      if (!mounted) return;
      final shareOrigin = _shareButtonRect(context, _shareButtonKey);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: shareOrigin,
        ),
      );
    } catch (e, s) {
      _logger.warning("Failed to share ritual heatmap", e, s);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Failed to share heatmap")));
    }
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({
    required this.ritual,
    required this.completedDayKeys,
    required this.startDay,
    required this.endDayInclusive,
    required this.compact,
  });

  final Ritual ritual;
  final Set<int> completedDayKeys;
  final DateTime startDay;
  final DateTime endDayInclusive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final monthFormatter = DateFormat.MMM(
      Localizations.localeOf(context).toString(),
    );

    final cell = compact ? 10.0 : 12.0;
    final spacing = compact ? 2.0 : 3.0;

    final gridStart = _startOfWeekSunday(startDay);
    final gridEnd = _endOfWeekSaturday(endDayInclusive);
    final weeks = _weekStarts(gridStart, gridEnd);
    final monthLabels = _monthLabelsForWeeks(monthFormatter, weeks);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(weeks.length, (index) {
              final label = monthLabels[index];
              return SizedBox(
                width: cell + spacing,
                child: label == null
                    ? const SizedBox.shrink()
                    : Text(
                        label,
                        style: textTheme.miniMuted,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                      ),
              );
            }, growable: false),
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!compact)
              SizedBox(
                width: 18,
                child: Column(
                  children: [
                    _weekdayLabel(textTheme, "M", cell),
                    SizedBox(height: cell + spacing),
                    _weekdayLabel(textTheme, "W", cell),
                    SizedBox(height: cell + spacing),
                    _weekdayLabel(textTheme, "F", cell),
                  ],
                ),
              ),
            Row(
              children: weeks
                  .map(
                    (weekStart) => Padding(
                      padding: EdgeInsets.only(right: spacing),
                      child: Column(
                        children: List.generate(7, (dayOffset) {
                          final day = DateTime(
                            weekStart.year,
                            weekStart.month,
                            weekStart.day + dayOffset,
                          );
                          final bool inRange =
                              !day.isBefore(startDay) &&
                              !day.isAfter(endDayInclusive);
                          final bool scheduled = _isScheduledDay(
                            ritual.daysOfWeek,
                            day,
                          );
                          final bool completed = completedDayKeys.contains(
                            DateTime(
                              day.year,
                              day.month,
                              day.day,
                            ).millisecondsSinceEpoch,
                          );

                          final Color fill = _cellColor(
                            colorScheme: colorScheme,
                            inRange: inRange,
                            scheduled: scheduled,
                            completed: completed,
                          );

                          return Padding(
                            padding: EdgeInsets.only(bottom: spacing),
                            child: Container(
                              width: cell,
                              height: cell,
                              decoration: BoxDecoration(
                                color: fill,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      ],
    );
  }

  Widget _weekdayLabel(EnteTextTheme textTheme, String label, double cell) {
    return SizedBox(
      width: 18,
      height: cell,
      child: Center(child: Text(label, style: textTheme.miniMuted)),
    );
  }

  Color _cellColor({
    required EnteColorScheme colorScheme,
    required bool inRange,
    required bool scheduled,
    required bool completed,
  }) {
    if (!inRange) {
      return Colors.transparent;
    }
    if (!scheduled) {
      return colorScheme.fillFaint.withValues(alpha: 0.35);
    }
    if (completed) {
      return const Color(0xFF1DB954);
    }
    return colorScheme.fillFaintPressed;
  }
}

List<String?> _monthLabelsForWeeks(DateFormat formatter, List<DateTime> weeks) {
  final labels = <String?>[];
  int? lastLabeledMonth;
  for (final weekStart in weeks) {
    if (weekStart.day <= 7 && weekStart.month != lastLabeledMonth) {
      labels.add(formatter.format(weekStart));
      lastLabeledMonth = weekStart.month;
    } else {
      labels.add(null);
    }
  }
  return labels;
}

bool _isScheduledDay(List<bool> daysOfWeek, DateTime day) {
  if (daysOfWeek.length != 7) return false;
  final dayIndex = day.weekday % 7; // Sunday -> 0
  return daysOfWeek[dayIndex];
}

DateTime _startOfWeekSunday(DateTime day) {
  final idx = day.weekday % 7; // Sunday -> 0
  return DateTime(day.year, day.month, day.day - idx);
}

DateTime _endOfWeekSaturday(DateTime day) {
  final idx = day.weekday % 7; // Sunday -> 0
  return DateTime(day.year, day.month, day.day + (6 - idx));
}

List<DateTime> _weekStarts(DateTime start, DateTime endInclusive) {
  final weeks = <DateTime>[];
  for (
    var day = start;
    !day.isAfter(endInclusive);
    day = day.add(const Duration(days: 7))
  ) {
    weeks.add(day);
  }
  return weeks;
}

Rect _shareButtonRect(BuildContext context, GlobalKey key) {
  final size = MediaQuery.sizeOf(context);
  final RenderObject? renderObject = key.currentContext?.findRenderObject();
  if (renderObject is! RenderBox) {
    return Rect.fromLTWH(0, 0, size.width, size.height / 2);
  }
  final buttonSize = renderObject.size;
  final position = renderObject.localToGlobal(Offset.zero);
  return Rect.fromCenter(
    center: position + Offset(buttonSize.width / 2, buttonSize.height / 2),
    width: buttonSize.width,
    height: buttonSize.height,
  );
}
