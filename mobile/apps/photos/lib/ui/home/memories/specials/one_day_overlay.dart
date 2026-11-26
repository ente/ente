import "dart:math";

import "package:flutter/foundation.dart" show listEquals;
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/special_memory.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/specials/special_memory_chrome.dart";

const _dayStartMinute = 4 * 60;
const _minutesPerDay = 24 * 60;

double _storyMinuteOf(EnteFile file) {
  final taken = wallClockOf(file);
  final minute = taken.hour * 60 + taken.minute + taken.second / 60;
  return minute < _dayStartMinute ? minute + _minutesPerDay : minute;
}

class Daylight {
  static const typical = Daylight(6.5 * 60, 19 * 60);

  final double sunrise;
  final double sunset;

  const Daylight(this.sunrise, this.sunset);

  factory Daylight.on(
    DateTime date, {
    required double latitude,
    required double longitude,
    required Duration utcOffset,
  }) {
    final dayOfYear = calendarDaysBetween(DateTime(date.year), date) + 1;
    final season = 2 * pi * (dayOfYear - 81) / 364;
    final equationOfTime =
        9.87 * sin(2 * season) - 7.53 * cos(season) - 1.5 * sin(season);
    final declination =
        23.44 * pi / 180 * sin(2 * pi * (284 + dayOfYear) / 365);
    final cosHourAngle = -tan(latitude * pi / 180) * tan(declination);
    final halfDay = acos(cosHourAngle.clamp(-1.0, 1.0)) * 180 / pi * 4;
    final noon = 720 - 4 * longitude - equationOfTime + utcOffset.inMinutes;
    return Daylight(noon - halfDay, noon + halfDay);
  }

  bool isUp(double minute) {
    final time = minute % _minutesPerDay;
    return time >= sunrise && time <= sunset;
  }

  double elevation(double minute) {
    final time = minute % _minutesPerDay;
    final dayLength = max(sunset - sunrise, 1.0);
    if (time >= sunrise && time <= sunset) {
      return sin(pi * (time - sunrise) / dayLength);
    }
    final nightLength = max(_minutesPerDay - dayLength, 1.0);
    final sinceSunset = (time - sunset) % _minutesPerDay;
    return -0.42 * sin(pi * sinceSunset / nightLength);
  }
}

class OneDayOverlay extends StatefulWidget {
  final OneDayMemory memory;

  const OneDayOverlay(this.memory, {super.key});

  @override
  State<OneDayOverlay> createState() => _OneDayOverlayState();
}

class _OneDayOverlayState extends State<OneDayOverlay>
    with SingleTickerProviderStateMixin {
  late final _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  ValueNotifier<int>? _index;
  List<double> _minutes = const [];
  Daylight _daylight = Daylight.typical;
  double _from = _dayStartMinute.toDouble();
  double _to = _dayStartMinute.toDouble();

  double get _minute {
    final progress = Curves.easeInOutCubic.transform(_travel.value);
    return _from + (_to - _from) * progress;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = FullScreenMemoryData.of(context);
    if (data == null) return;
    final minutes = [
      for (final memory in data.memories) _storyMinuteOf(memory.file),
    ];
    final hasNewMoments = !listEquals(minutes, _minutes);
    if (hasNewMoments) {
      _minutes = minutes;
      _daylight = _daylightOf(data.memories.firstOrNull?.file);
    }
    if (!identical(_index, data.indexNotifier)) {
      _index?.removeListener(_travelToCurrent);
      _index = data.indexNotifier..addListener(_travelToCurrent);
      _from = _to = _currentMinute ?? _to;
    } else if (hasNewMoments) {
      _travelToCurrent();
    }
  }

  @override
  void dispose() {
    _index?.removeListener(_travelToCurrent);
    _travel.dispose();
    super.dispose();
  }

  double? get _currentMinute {
    final index = _index?.value;
    if (index == null || index < 0 || index >= _minutes.length) return null;
    return _minutes[index];
  }

  Daylight _daylightOf(EnteFile? file) {
    final creationTime = file?.creationTime;
    if (file == null || creationTime == null) return Daylight.typical;
    final wallClock = wallClockOf(file);
    final utc = DateTime.fromMicrosecondsSinceEpoch(creationTime, isUtc: true);
    final utcOffset = DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
    ).difference(utc);
    return Daylight.on(
      widget.memory.date,
      latitude: widget.memory.latitude,
      longitude: widget.memory.longitude,
      utcOffset: utcOffset,
    );
  }

  void _travelToCurrent() {
    final minute = _currentMinute;
    if (minute == null || !mounted) return;
    _from = _minute;
    _to = minute;
    _travel.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const SpecialMemoryStoryScrim(),
          Positioned(
            left: safePadding.left + 24,
            right: safePadding.right + 24,
            bottom: safePadding.bottom + 182,
            child: AnimatedBuilder(
              animation: _travel,
              builder: (context, _) {
                final minute = _minute;
                final clock = DateTime(
                  2000,
                ).add(Duration(seconds: (minute * 60).round()));
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat.jm(locale).format(clock),
                      style: specialDisplayStyle(44).copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        shadows: const [
                          Shadow(color: Color(0x80000000), blurRadius: 12),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 68,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _DayArcPainter(
                          minute: minute,
                          moments: _minutes,
                          daylight: _daylight,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DayArcPainter extends CustomPainter {
  static const _horizonShare = 0.7;
  static const _step = 8.0;

  final double minute;
  final List<double> moments;
  final Daylight daylight;

  const _DayArcPainter({
    required this.minute,
    required this.moments,
    required this.daylight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * _horizonShare;
    Offset pointAt(double minute) {
      final x = (minute - _dayStartMinute) / _minutesPerDay * size.width;
      return Offset(x, horizon - daylight.elevation(minute) * (horizon - 9));
    }

    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );
    final end = _dayStartMinute + _minutesPerDay.toDouble();
    Path pathBetween(double from, double to) {
      final path = Path()..moveTo(pointAt(from).dx, pointAt(from).dy);
      for (var at = from + _step; at < to; at += _step) {
        path.lineTo(pointAt(at).dx, pointAt(at).dy);
      }
      return path..lineTo(pointAt(to).dx, pointAt(to).dy);
    }

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      pathBetween(minute, end),
      stroke..color = Colors.white.withValues(alpha: 0.3),
    );
    canvas.drawPath(
      pathBetween(_dayStartMinute.toDouble(), minute),
      stroke..color = Colors.white.withValues(alpha: 0.95),
    );
    for (final moment in moments) {
      canvas.drawCircle(
        pointAt(moment),
        3,
        Paint()
          ..color = Colors.white.withValues(
            alpha: moment <= minute + 0.5 ? 1 : 0.45,
          ),
      );
    }
    final isUp = daylight.isUp(minute);
    final body = isUp ? SpecialMemoryColors.yellow : const Color(0xFFDDE4FF);
    final position = pointAt(minute);
    canvas.drawCircle(
      position,
      17,
      Paint()
        ..color = body.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(position, 9, Paint()..color = body);
    if (!isUp) {
      canvas.drawCircle(
        position + const Offset(4, -3),
        7,
        Paint()..color = const Color(0xFF20263A),
      );
    }
  }

  @override
  bool shouldRepaint(_DayArcPainter oldDelegate) {
    return oldDelegate.minute != minute ||
        oldDelegate.daylight != daylight ||
        !listEquals(oldDelegate.moments, moments);
  }
}

class SunArcGlyphPainter extends CustomPainter {
  const SunArcGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height - 3;
    final arc = Path()
      ..moveTo(0, horizon)
      ..quadraticBezierTo(
        size.width / 2,
        -size.height * 0.8,
        size.width,
        horizon,
      );
    canvas.drawLine(
      Offset(0, horizon),
      Offset(size.width, horizon),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      arc,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.9),
    );
    final metric = arc.computeMetrics().first;
    final sun = metric.getTangentForOffset(metric.length * 0.3)?.position;
    if (sun == null) return;
    canvas.drawCircle(
      sun,
      9,
      Paint()
        ..color = SpecialMemoryColors.yellow.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(sun, 4.5, Paint()..color = SpecialMemoryColors.yellow);
  }

  @override
  bool shouldRepaint(SunArcGlyphPainter oldDelegate) => false;
}
