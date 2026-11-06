import "package:flutter/scheduler.dart";
import "package:flutter/widgets.dart";

double rewindProgress(
  double ms, {
  required double delayMs,
  required double durationMs,
  Curve curve = Curves.linear,
}) => curve.transform(((ms - delayMs) / durationMs).clamp(0.0, 1.0));

class RewindElapsed extends StatefulWidget {
  const RewindElapsed({
    required this.active,
    required this.builder,
    this.stillMs = 0,
    super.key,
  });

  final bool active;
  final double stillMs;
  final Widget Function(BuildContext context, double ms) builder;

  @override
  State<RewindElapsed> createState() => _RewindElapsedState();
}

class _RewindElapsedState extends State<RewindElapsed>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  var _banked = Duration.zero;
  var _elapsed = Duration.zero;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(RewindElapsed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final run = widget.active && !MediaQuery.disableAnimationsOf(context);
    if (run && !_ticker.isActive) {
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
      _banked = _elapsed;
    }
  }

  void _onTick(Duration elapsed) {
    setState(() => _elapsed = _banked + elapsed);
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ms = MediaQuery.disableAnimationsOf(context)
        ? widget.stillMs
        : _elapsed.inMicroseconds / Duration.microsecondsPerMillisecond;
    return widget.builder(context, ms);
  }
}
