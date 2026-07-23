import 'dart:async';
import 'dart:io';

import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class CodeTimerProgress extends StatefulWidget {
  final int period;
  final bool isCompactMode;
  final int timeOffsetInMilliseconds;
  const CodeTimerProgress({
    super.key,
    required this.period,
    this.isCompactMode = false,
    this.timeOffsetInMilliseconds = 0,
  });

  @override
  State<CodeTimerProgress> createState() => _CodeTimerProgressState();
}

class _CodeTimerProgressState extends State<CodeTimerProgress> {
  late final Timer _timer;
  late final ValueNotifier<double> _progress;
  late final int _periodInMilii;

  // Reduce update frequency
  final int _updateIntervalMs = (Platform.isAndroid || Platform.isIOS)
      ? 16
      : 500; // approximately 60 FPS

  @override
  void initState() {
    super.initState();
    _periodInMilii = widget.period * 1000;
    _progress = ValueNotifier<double>(0.0);
    _updateTimeRemaining(DateTime.now().millisecondsSinceEpoch);

    _timer = Timer.periodic(Duration(milliseconds: _updateIntervalMs), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _updateTimeRemaining(now);
    });
  }

  void _updateTimeRemaining(int currentMilliSeconds) {
    // More efficient time calculation using modulo
    final elapsed =
        (currentMilliSeconds + widget.timeOffsetInMilliseconds) %
        _periodInMilii;
    final timeRemaining = _periodInMilii - elapsed;
    _progress.value = timeRemaining / _periodInMilii;
  }

  @override
  void didUpdateWidget(covariant CodeTimerProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.period != widget.period) {
      _periodInMilii = widget.period * 1000;
      _updateTimeRemaining(DateTime.now().millisecondsSinceEpoch);
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.isCompactMode ? 1 : 3,
      width: double.infinity,
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (context, progress, _) {
          return CustomPaint(
            key: Key(progress.toString()), // Add key here
            painter: _ProgressPainter(
              progress: progress,
              color: progress > 0.4
                  ? getEnteColorScheme(context).primary700
                  : Colors.orange,
            ),
          );
        },
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _ProgressPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width * progress, size.height),
      const Radius.circular(2),
    );

    canvas.drawRRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ProgressPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}
