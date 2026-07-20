part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildStatsCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  switch (card.type) {
    case WrappedCardType.statsTotals:
      return _TotalsCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.statsVelocity:
      return _RhythmCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.busiestDay:
      return _BusiestDayCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.statsHeatmap:
      return _HeatmapCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    default:
      return null;
  }
}

class _TotalsCardContent extends StatelessWidget {
  const _TotalsCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = _stringListFromMeta(card.meta, "detailChips");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroMediaCollage(media: card.media, colorScheme: colorScheme),
        const SizedBox(height: 24),
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _RhythmCardContent extends StatelessWidget {
  const _RhythmCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = _stringListFromMeta(card.meta, "detailChips");
    final Map<int, int> monthCounts = _parseMonthCounts(
      card.meta["monthCounts"],
    );
    final Map<String, int> formatCounts = _parseFormatCounts(
      card.meta["formatCounts"],
    );
    final int totalFormatCount = formatCounts.values.fold(
      0,
      (int sum, int value) => sum + value,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        if (monthCounts.isNotEmpty) ...[
          const SizedBox(height: 24),
          _MonthlyCaptureChart(
            monthCounts: monthCounts,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        if (formatCounts.isNotEmpty && totalFormatCount > 0) ...[
          const SizedBox(height: 24),
          _FormatDistributionChart(
            formatCounts: formatCounts,
            totalCount: totalFormatCount,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

Map<int, int> _parseMonthCounts(Object? raw) {
  if (raw is Map) {
    final Map<int, int> result = <int, int>{};
    raw.forEach((dynamic key, dynamic value) {
      int? month;
      if (key is int) {
        month = key;
      } else if (key is String) {
        month = int.tryParse(key);
      }
      if (month == null || month < 1 || month > 12) {
        return;
      }
      if (value is num) {
        result[month] = value.toInt();
      }
    });
    return result;
  }
  return const <int, int>{};
}

Map<String, int> _parseFormatCounts(Object? raw) {
  if (raw is Map) {
    final Map<String, int> result = <String, int>{};
    raw.forEach((dynamic key, dynamic value) {
      if (key == null || value is! num) {
        return;
      }
      final String label = key.toString();
      if (label.isEmpty) {
        return;
      }
      result[label] = value.toInt();
    });
    return result;
  }
  return const <String, int>{};
}

double _resolveAxisMax(double rawMax) {
  if (rawMax <= 0) {
    return 1;
  }
  return math.max(1, _niceCeiling(rawMax));
}

List<_ChartTick> _buildAxisTicks(double axisMax) {
  if (axisMax <= 0) {
    return const <_ChartTick>[_ChartTick(value: 0, label: "0")];
  }

  const int divisions = 2; // top, mid, baseline
  final double step = axisMax / divisions;
  final NumberFormat compactFormat = NumberFormat.compact();
  final NumberFormat integerFormat = NumberFormat.decimalPattern();

  final List<_ChartTick> ticks = <_ChartTick>[];
  for (int i = 0; i <= divisions; i += 1) {
    final double value = axisMax - (step * i);
    final double normalized = i == divisions ? 0 : value.clamp(0, axisMax);

    final String label;
    if (normalized <= 0) {
      label = "0";
    } else if (axisMax >= 1000) {
      label = compactFormat.format(normalized);
    } else {
      label = integerFormat.format(normalized.round());
    }

    ticks.add(_ChartTick(value: normalized, label: label));
  }
  return ticks;
}

double _niceCeiling(double value) {
  if (value <= 0) {
    return 1;
  }
  final double log10 = math.log(value) / math.ln10;
  final double exponent = math.pow(10, log10.floor()).toDouble();
  final double fraction = value / exponent;
  double niceFraction;
  if (fraction <= 1) {
    niceFraction = 1;
  } else if (fraction <= 2) {
    niceFraction = 2;
  } else if (fraction <= 5) {
    niceFraction = 5;
  } else {
    niceFraction = 10;
  }
  final double niceValue = niceFraction * exponent;
  if (niceValue < value) {
    return niceValue * 2;
  }
  return niceValue;
}

const String _otherLabel = "Other";

List<MapEntry<String, int>> _limitFormatEntries(
  List<MapEntry<String, int>> entries,
  int maxEntries,
) {
  if (entries.length <= maxEntries) {
    return entries;
  }
  final List<MapEntry<String, int>> limited = entries
      .take(maxEntries)
      .toList(growable: true);
  final int remainder = entries
      .skip(maxEntries)
      .fold<int>(
        0,
        (int sum, MapEntry<String, int> entry) => sum + entry.value,
      );
  if (remainder > 0) {
    limited.add(MapEntry<String, int>(_otherLabel, remainder));
  }
  return limited;
}

class _ChartTick {
  const _ChartTick({required this.value, required this.label});

  final double value;
  final String label;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _ChartTick && value == other.value && label == other.label;
  }

  @override
  int get hashCode => Object.hash(value, label);
}

class _MonthlyCaptureChart extends StatelessWidget {
  const _MonthlyCaptureChart({
    required this.monthCounts,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<int, int> monthCounts;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  static const double _axisLabelWidth = 30;
  static const double _axisLabelSpacing = 4;
  static const List<String> _labels = <String>[
    "J",
    "F",
    "M",
    "A",
    "M",
    "J",
    "J",
    "A",
    "S",
    "O",
    "N",
    "D",
  ];

  @override
  Widget build(BuildContext context) {
    final List<int> orderedCounts = List<int>.generate(
      12,
      (int index) => monthCounts[index + 1] ?? 0,
      growable: false,
    );
    final double rawMaxValue = orderedCounts.fold<double>(
      0,
      (double currentMax, int value) => math.max(currentMax, value.toDouble()),
    );
    final double axisMax = _resolveAxisMax(rawMaxValue);
    final List<_ChartTick> ticks = _buildAxisTicks(axisMax);

    final Color accent = colorScheme.primary500;
    final Color gridColor = colorScheme.fillMuted.withValues(alpha: 0.35);
    final Color background = colorScheme.fillMuted.withValues(alpha: 0.12);
    final Color axisColor = colorScheme.fillMuted.withValues(alpha: 0.45);
    final Color outlineColor = colorScheme.backgroundElevated;
    const double leftInset = _axisLabelWidth + _axisLabelSpacing;
    final double rightInset = math.max(12, leftInset * 0.4);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 160,
            width: double.infinity,
            child: CustomPaint(
              painter: _MonthlyCaptureChartPainter(
                values: orderedCounts
                    .map((int value) => value.toDouble())
                    .toList(growable: false),
                maxValue: axisMax <= 0 ? 1 : axisMax,
                lineColor: accent,
                fillColor: accent.withValues(alpha: 0.18),
                gridColor: gridColor,
                axisColor: axisColor,
                pointColor: accent,
                pointOutlineColor: outlineColor,
                axisLabelStyle: textTheme.miniMuted,
                axisLabelWidth: _axisLabelWidth,
                axisLabelSpacing: _axisLabelSpacing,
                rightPadding: rightInset,
                ticks: ticks,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsets.only(left: leftInset, right: rightInset),
            child: Row(
              children: [
                for (final String label in _labels)
                  Expanded(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: textTheme.tinyMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyCaptureChartPainter extends CustomPainter {
  _MonthlyCaptureChartPainter({
    required this.values,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.axisColor,
    required this.pointColor,
    required this.pointOutlineColor,
    required this.axisLabelStyle,
    required this.axisLabelWidth,
    required this.axisLabelSpacing,
    required this.rightPadding,
    required this.ticks,
  });

  final List<double> values;
  final double maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color axisColor;
  final Color pointColor;
  final Color pointOutlineColor;
  final TextStyle axisLabelStyle;
  final double axisLabelWidth;
  final double axisLabelSpacing;
  final double rightPadding;
  final List<_ChartTick> ticks;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) {
      return;
    }

    const double topPadding = 12;
    const double bottomPadding = 12;
    final double leftPadding = axisLabelWidth + axisLabelSpacing;
    final double chartHeight = math.max(
      0,
      size.height - topPadding - bottomPadding,
    );
    final double chartWidth = math.max(
      0,
      size.width - leftPadding - rightPadding,
    );
    final double baselineY = topPadding + chartHeight;
    final double segmentWidth = values.isEmpty
        ? 0
        : (chartWidth / values.length);
    final double chartLeft = values.length <= 1
        ? leftPadding + (chartWidth / 2)
        : leftPadding + (segmentWidth / 2);
    final double chartRight = values.length <= 1
        ? chartLeft
        : size.width - rightPadding - (segmentWidth / 2);
    final double gridStartX = values.length <= 1 ? leftPadding : chartLeft;
    final double gridEndX = values.length <= 1
        ? size.width - rightPadding
        : chartRight;

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (final _ChartTick tick in ticks) {
      final double fraction = maxValue <= 0
          ? 0
          : (tick.value / maxValue).clamp(0, 1);
      final double y = baselineY - (fraction * chartHeight);

      if (tick.value > 0) {
        canvas.drawLine(Offset(gridStartX, y), Offset(gridEndX, y), gridPaint);
      }

      final TextPainter labelPainter = TextPainter(
        text: TextSpan(text: tick.label, style: axisLabelStyle),
        textAlign: TextAlign.right,
        textDirection: ui.TextDirection.ltr,
      )..layout();

      labelPainter.paint(
        canvas,
        Offset(
          axisLabelWidth - axisLabelSpacing - labelPainter.width,
          y - (labelPainter.height / 2),
        ),
      );
    }

    final List<Offset> points = <Offset>[];
    final double stepX = values.length <= 1 ? 0 : segmentWidth;
    for (int i = 0; i < values.length; i += 1) {
      final double fraction = maxValue <= 0
          ? 0
          : (values[i] / maxValue).clamp(0, 1);
      final double x = (values.length <= 1 || stepX <= 0)
          ? chartLeft
          : chartLeft + (stepX * i);
      final double y = baselineY - (fraction * chartHeight);
      points.add(Offset(x, y));
    }

    if (points.isEmpty) {
      return;
    }

    final Path linePath = _createSmoothPath(points);
    final Path fillPath = Path()
      ..addPath(linePath, Offset.zero)
      ..lineTo(points.last.dx, baselineY)
      ..lineTo(points.first.dx, baselineY)
      ..close();

    final Rect fillBounds = Rect.fromLTWH(
      gridStartX,
      topPadding,
      math.max(0, gridEndX - gridStartX),
      chartHeight,
    );
    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        colors: <Color>[fillColor, fillColor.withValues(alpha: 0.02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(fillBounds);
    canvas.drawPath(fillPath, fillPaint);

    final Paint axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(gridStartX, baselineY),
      Offset(gridEndX, baselineY),
      axisPaint,
    );

    final Paint linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    final Paint pointOutlinePaint = Paint()
      ..color = pointOutlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final Paint pointPaint = Paint()
      ..color = pointColor
      ..style = PaintingStyle.fill;

    for (final Offset point in points) {
      canvas.drawCircle(point, 4, pointOutlinePaint);
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MonthlyCaptureChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.axisColor != axisColor ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.pointOutlineColor != pointOutlineColor ||
        oldDelegate.axisLabelStyle != axisLabelStyle ||
        oldDelegate.axisLabelWidth != axisLabelWidth ||
        oldDelegate.axisLabelSpacing != axisLabelSpacing ||
        oldDelegate.rightPadding != rightPadding ||
        !listEquals(oldDelegate.ticks, ticks);
  }

  Path _createSmoothPath(List<Offset> points) {
    final Path path = Path();
    if (points.isEmpty) {
      return path;
    }

    path.moveTo(points.first.dx, points.first.dy);

    if (points.length == 1) {
      return path;
    }

    if (points.length == 2) {
      path.lineTo(points.last.dx, points.last.dy);
      return path;
    }

    final int count = points.length;
    final List<double> slopes = <double>[];
    final List<double> dx = <double>[];
    for (int i = 0; i < count - 1; i += 1) {
      final double deltaX = points[i + 1].dx - points[i].dx;
      final double deltaY = points[i + 1].dy - points[i].dy;
      dx.add(deltaX);
      if (deltaX.abs() < 1e-6) {
        slopes.add(0);
      } else {
        slopes.add(deltaY / deltaX);
      }
    }

    final List<double> tangents = List<double>.filled(count, 0);
    tangents[0] = slopes.first;
    tangents[count - 1] = slopes.last;
    for (int i = 1; i < count - 1; i += 1) {
      final double slopePrev = slopes[i - 1];
      final double slopeNext = slopes[i];
      if ((slopePrev > 0 && slopeNext < 0) ||
          (slopePrev < 0 && slopeNext > 0) ||
          slopePrev.abs() < 1e-6 ||
          slopeNext.abs() < 1e-6) {
        tangents[i] = 0;
      } else {
        tangents[i] = (slopePrev + slopeNext) / 2;
      }
    }

    for (int i = 0; i < slopes.length; i += 1) {
      final double slope = slopes[i];
      if (slope.abs() < 1e-6) {
        tangents[i] = 0;
        tangents[i + 1] = 0;
        continue;
      }
      double a = tangents[i] / slope;
      double b = tangents[i + 1] / slope;
      final double sum = (a * a) + (b * b);
      if (sum > 9) {
        final double tau = 3 / math.sqrt(sum);
        a *= tau;
        b *= tau;
        tangents[i] = a * slope;
        tangents[i + 1] = b * slope;
      }
    }

    for (int i = 0; i < count - 1; i += 1) {
      final Offset p0 = points[i];
      final Offset p1 = points[i + 1];
      final double segmentDx = dx[i];
      if (segmentDx.abs() < 1e-6) {
        path.lineTo(p1.dx, p1.dy);
        continue;
      }
      final double t0 = tangents[i];
      final double t1 = tangents[i + 1];
      final Offset control1 = Offset(
        p0.dx + segmentDx / 3,
        p0.dy + (t0 * segmentDx) / 3,
      );
      final Offset control2 = Offset(
        p1.dx - segmentDx / 3,
        p1.dy - (t1 * segmentDx) / 3,
      );
      path.cubicTo(
        control1.dx,
        control1.dy,
        control2.dx,
        control2.dy,
        p1.dx,
        p1.dy,
      );
    }
    return path;
  }
}

class _FormatDistributionChart extends StatelessWidget {
  const _FormatDistributionChart({
    required this.formatCounts,
    required this.totalCount,
    required this.colorScheme,
    required this.textTheme,
  });

  final Map<String, int> formatCounts;
  final int totalCount;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<MapEntry<String, int>> sortedEntries =
        formatCounts.entries
            .where((MapEntry<String, int> entry) => entry.value > 0)
            .toList(growable: false)
          ..sort(
            (MapEntry<String, int> a, MapEntry<String, int> b) =>
                b.value.compareTo(a.value),
          );
    if (sortedEntries.isEmpty) {
      return const SizedBox.shrink();
    }

    const int maxLegendEntries = 6;
    final List<MapEntry<String, int>> entries = _limitFormatEntries(
      sortedEntries,
      maxLegendEntries,
    );

    final NumberFormat numberFormat = NumberFormat.decimalPattern();
    final palette = Theme.of(context).brightness == Brightness.dark
        ? components.avatarDark
        : components.avatarLight;
    final List<Color> colors = <Color>[];
    for (int i = 0; i < entries.length; i += 1) {
      final String label = entries[i].key;
      if (i == 0) {
        colors.add(colorScheme.primary500);
      } else if (label == _otherLabel) {
        colors.add(colorScheme.fillStrong);
      } else if (palette.isNotEmpty) {
        final int paletteIndex = (i - 1) % palette.length;
        colors.add(palette[paletteIndex]);
      } else {
        colors.add(colorScheme.primary400);
      }
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.fillMuted.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 140,
              width: 140,
              child: CustomPaint(
                painter: _FormatPieChartPainter(
                  values: entries
                      .map(
                        (MapEntry<String, int> entry) => entry.value.toDouble(),
                      )
                      .toList(growable: false),
                  colors: colors,
                  totalLabel: numberFormat.format(totalCount),
                  totalCaption: "files",
                  totalStyle: textTheme.largeBold,
                  captionStyle: textTheme.tinyMuted,
                  ringBackgroundColor: colorScheme.fillMuted.withValues(
                    alpha: 0.18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int index = 0; index < entries.length; index += 1)
                  Padding(
                    padding: EdgeInsets.only(
                      bottom: index == entries.length - 1 ? 0 : 10,
                    ),
                    child: _FormatLegendEntry(
                      color: colors[index],
                      label: entries[index].key,
                      textTheme: textTheme,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatPieChartPainter extends CustomPainter {
  _FormatPieChartPainter({
    required this.values,
    required this.colors,
    required this.totalLabel,
    required this.totalCaption,
    required this.totalStyle,
    required this.captionStyle,
    required this.ringBackgroundColor,
  });

  final List<double> values;
  final List<Color> colors;
  final String totalLabel;
  final String totalCaption;
  final TextStyle totalStyle;
  final TextStyle captionStyle;
  final Color ringBackgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) / 2;
    final double strokeWidth = radius * 0.35;
    final Rect arcRect = Rect.fromCircle(
      center: center,
      radius: radius - (strokeWidth / 2),
    );

    final Paint basePaint = Paint()
      ..isAntiAlias = true
      ..color = ringBackgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(arcRect, 0, 2 * math.pi, false, basePaint);

    final double total = values.fold<double>(
      0,
      (double sum, double value) => sum + value,
    );
    if (total > 0) {
      double startAngle = -math.pi / 2;
      for (int i = 0; i < values.length; i += 1) {
        final double value = values[i];
        if (value <= 0) {
          continue;
        }
        final double sweepAngle = (value / total) * 2 * math.pi;
        final Paint segmentPaint = Paint()
          ..isAntiAlias = true
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;
        canvas.drawArc(arcRect, startAngle, sweepAngle, false, segmentPaint);
        startAngle += sweepAngle;
      }
    }

    _drawTotal(canvas, center);
  }

  void _drawTotal(Canvas canvas, Offset center) {
    final TextPainter totalPainter = TextPainter(
      text: TextSpan(text: totalLabel, style: totalStyle),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final TextPainter captionPainter = TextPainter(
      text: TextSpan(text: totalCaption, style: captionStyle),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
    )..layout();

    final double combinedHeight =
        totalPainter.height + 6 + captionPainter.height;
    final double startY = center.dy - (combinedHeight / 2);

    totalPainter.paint(
      canvas,
      Offset(center.dx - (totalPainter.width / 2), startY),
    );
    captionPainter.paint(
      canvas,
      Offset(
        center.dx - (captionPainter.width / 2),
        startY + totalPainter.height + 6,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _FormatPieChartPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.totalLabel != totalLabel ||
        oldDelegate.totalCaption != totalCaption ||
        oldDelegate.totalStyle != totalStyle ||
        oldDelegate.captionStyle != captionStyle ||
        oldDelegate.ringBackgroundColor != ringBackgroundColor;
  }
}

class _FormatLegendEntry extends StatelessWidget {
  const _FormatLegendEntry({
    required this.color,
    required this.label,
    required this.textTheme,
  });

  final Color color;
  final String label;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label, style: textTheme.smallMuted),
      ],
    );
  }
}

class _BusiestDayCardContent extends StatelessWidget {
  const _BusiestDayCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = _stringListFromMeta(card.meta, "detailChips");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        const SizedBox(height: 22),
        _MediaGrid(
          media: card.media.take(6).toList(growable: false),
          colorScheme: colorScheme,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _HeatmapCardContent extends StatelessWidget {
  const _HeatmapCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = _stringListFromMeta(card.meta, "detailChips");
    final List<List<int>> grid = _parseHeatmapGrid(card.meta["grid"]);
    final List<String> weekdayLabels =
        (card.meta["weekdayLabels"] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()
            .toList(growable: false);
    final List<String> weekLabels = _stringListFromMeta(
      card.meta,
      "weekLabels",
    );
    final int maxCount = (card.meta["maxCount"] as num?)?.toInt() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        const SizedBox(height: 20),
        if (grid.isEmpty)
          _MediaPlaceholder(height: 180, colorScheme: colorScheme)
        else
          _HeatmapBackground(
            colorScheme: colorScheme,
            child: _YearHeatmap(
              grid: grid,
              weekLabels: weekLabels,
              weekdayLabels: weekdayLabels,
              maxCount: maxCount,
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 16),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

List<List<int>> _parseHeatmapGrid(Object? raw) {
  if (raw is! List) {
    return const <List<int>>[];
  }
  final List<List<int>> rows = <List<int>>[];
  for (final dynamic entry in raw) {
    if (entry is! List) {
      continue;
    }
    final List<int> parsedRow = <int>[];
    for (final dynamic value in entry) {
      if (value is num) {
        parsedRow.add(value.toInt());
      }
    }
    rows.add(List<int>.unmodifiable(parsedRow));
  }
  return List<List<int>>.unmodifiable(rows);
}

class _YearHeatmap extends StatelessWidget {
  const _YearHeatmap({
    required this.grid,
    required this.weekLabels,
    required this.weekdayLabels,
    required this.maxCount,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<List<int>> grid;
  final List<String> weekLabels;
  final List<String> weekdayLabels;
  final int maxCount;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final int columnCount = grid.isNotEmpty ? grid.first.length : 0;
    if (columnCount == 0) {
      return _MediaPlaceholder(height: 180, colorScheme: colorScheme);
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double labelColumnWidth = 24;
        const double horizontalSpacing = 1.2;
        const double verticalSpacing = 1.0;
        const double minCellSize = 5;
        const double maxCellWidth = 13;
        const double maxCellHeight = 9.0;
        const double heightCompression = 0.7;

        final double usableWidth = math.max(
          0,
          constraints.maxWidth -
              labelColumnWidth -
              horizontalSpacing * math.max(0, columnCount - 1),
        );
        final double rawCellWidth = columnCount > 0
            ? usableWidth / columnCount
            : minCellSize;
        final double cellWidth = rawCellWidth
            .clamp(minCellSize, maxCellWidth.toDouble())
            .toDouble();
        final double compressedHeight = cellWidth * heightCompression;
        final double cellHeight = compressedHeight
            .clamp(minCellSize, maxCellHeight)
            .toDouble();
        final double gridWidth =
            labelColumnWidth +
            (cellWidth * columnCount) +
            horizontalSpacing * math.max(0, columnCount - 1);
        final TextStyle axisStyle = textTheme.tinyMuted.copyWith(
          fontSize: 8.0,
          height: 1.1,
        );

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: labelColumnWidth),
                    for (
                      int columnIndex = 0;
                      columnIndex < columnCount;
                      columnIndex += 1
                    ) ...[
                      SizedBox(
                        width: cellWidth,
                        child: Text(
                          columnIndex < weekdayLabels.length
                              ? weekdayLabels[columnIndex]
                              : "",
                          style: axisStyle,
                          textAlign: TextAlign.center,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                        ),
                      ),
                      SizedBox(
                        width: columnIndex == columnCount - 1
                            ? 0
                            : horizontalSpacing,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Column(
                  children: List<Widget>.generate(grid.length, (int rowIndex) {
                    final List<int> row = grid[rowIndex];
                    final String label = rowIndex < weekLabels.length
                        ? weekLabels[rowIndex]
                        : "";
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: rowIndex == grid.length - 1
                            ? 0
                            : verticalSpacing,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: labelColumnWidth,
                            child: Visibility(
                              visible: label.isNotEmpty,
                              maintainSize: true,
                              maintainAnimation: true,
                              maintainState: true,
                              child: Text(label, style: axisStyle),
                            ),
                          ),
                          for (
                            int columnIndex = 0;
                            columnIndex < columnCount;
                            columnIndex += 1
                          ) ...[
                            _HeatmapCell(
                              value: columnIndex < row.length
                                  ? row[columnIndex]
                                  : -1,
                              width: cellWidth,
                              height: cellHeight,
                              colorScheme: colorScheme,
                              maxCount: maxCount,
                            ),
                            SizedBox(
                              width: columnIndex == columnCount - 1
                                  ? 0
                                  : horizontalSpacing,
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeatmapBackground extends StatelessWidget {
  const _HeatmapBackground({required this.child, required this.colorScheme});

  final Widget child;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final Color base = Colors.black.withValues(alpha: 0.32);
    final Color border = Colors.white.withValues(alpha: 0.16);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: border,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: child,
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.value,
    required this.width,
    required this.height,
    required this.colorScheme,
    required this.maxCount,
  });

  final int value;
  final double width;
  final double height;
  final EnteColorScheme colorScheme;
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    if (value == kWrappedHeatmapFutureValue) {
      return SizedBox(width: width, height: height);
    }
    if (value == kWrappedHeatmapPaddedValue) {
      final Color base = colorScheme.fillFaint;
      final double placeholderAlpha = (base.a * 0.4).clamp(0.0, 1.0).toDouble();
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: placeholderAlpha),
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _heatmapColorForValue(value, maxCount, colorScheme),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}
