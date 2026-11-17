import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:photos/ui/rewind/reel/rewind_reel.dart";
import "package:photos/ui/rewind/reel/rewind_video_export.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";

class FinaleReelPreview extends StatefulWidget {
  const FinaleReelPreview({
    required this.active,
    required this.coverInset,
    super.key,
  });

  final bool active;
  final double coverInset;

  @override
  State<FinaleReelPreview> createState() => _FinaleReelPreviewState();
}

class _FinaleReelPreviewState extends State<FinaleReelPreview>
    with SingleTickerProviderStateMixin {
  static const _dwell = Duration(milliseconds: 1400);
  static const _cut = Duration(milliseconds: 600);
  static const _turn = RewindMotion.waveDuration;

  late final Ticker _ticker = createTicker(_onTick);
  final _time = ValueNotifier(Duration.zero);
  RewindReel? _reel;
  Widget? _view;
  Future<void>? _loading;
  var _steps = const <(Duration, Duration)>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load(RewindPageScope.navigatorOf(context));
    _sync();
  }

  @override
  void didUpdateWidget(FinaleReelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  Future<void> _load(RewindNavigator? navigator) async {
    if (navigator == null) return;
    final warmed = await Future.wait([
      for (final page in navigator.pages) page.warmUp(),
    ]);
    final reel = RewindReel.of(navigator.pages);
    if (warmed.contains(false) || reel.pages.isEmpty) return;
    if (!await navigator.loadVideoMedia(reel.pages) || !mounted) return;
    setState(() {
      _reel = reel;
      _steps = _stepsOf(reel);
      _view = RewindReelView(
        reel: reel,
        time: _time,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    });
    _sync();
  }

  void _sync() {
    final play =
        widget.active &&
        _view != null &&
        !MediaQuery.disableAnimationsOf(context);
    if (play && !_ticker.isActive) {
      _ticker.start();
    } else if (!play && _ticker.isActive) {
      _ticker.stop();
      _time.value = Duration.zero;
    }
  }

  static List<(Duration, Duration)> _stepsOf(RewindReel reel) {
    final steps = <(Duration, Duration)>[];
    var start = Duration.zero;
    for (final page in reel.pages) {
      final hold = page.reelHold!;
      for (var stop = 0; stop < page.stops; stop++) {
        steps.add((start, hold));
        start += hold + _turn;
      }
    }
    return steps;
  }

  void _onTick(Duration elapsed) {
    final loop = _dwell * _steps.length + _cut * (_steps.length - 1);
    var left = Duration(
      microseconds: elapsed.inMicroseconds % loop.inMicroseconds,
    );
    for (final (start, hold) in _steps) {
      if (left < _dwell) {
        _time.value = start;
        return;
      }
      left -= _dwell;
      if (left < _cut) {
        _time.value =
            start + hold + _turn * (left.inMicroseconds / _cut.inMicroseconds);
        return;
      }
      left -= _cut;
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = _view;
    final reel = _reel;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (view != null)
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox.fromSize(
              size: RewindReel.canvas,
              child: RepaintBoundary(child: view),
            ),
          )
        else
          RewindVideoCover(inset: widget.coverInset),
        if (reel != null)
          Positioned(right: 7, bottom: 7, child: _DurationTag(reel.duration)),
      ],
    );
  }
}

class _DurationTag extends StatelessWidget {
  const _DurationTag(this.duration);

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final seconds = (duration.inMilliseconds / 1000).round();
    final label =
        "${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, "0")}";
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      decoration: BoxDecoration(
        color: RewindColors.ink.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CustomPaint(size: Size(8, 9), painter: _PlayPainter()),
          const SizedBox(width: 4),
          Text(label, style: RewindTextStyles.body(12, height: 1.15)),
        ],
      ),
    );
  }
}

class _PlayPainter extends CustomPainter {
  const _PlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, size.height / 2)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = RewindColors.cream,
    );
  }

  @override
  bool shouldRepaint(_PlayPainter oldDelegate) => false;
}
