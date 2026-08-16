import "dart:async";

import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";

const kDefaultSeekDuration = Duration(seconds: 5);

class DoubleTapSeekOverlay extends StatefulWidget {
  final bool Function() enabled;
  final Duration Function() position;
  final Duration Function() duration;
  final void Function(Duration) seekTo;
  final VoidCallback? onSingleTap;
  final VoidCallback? onSeekInteraction;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressUpCallback? onLongPressUp;

  const DoubleTapSeekOverlay({
    required this.enabled,
    required this.position,
    required this.duration,
    required this.seekTo,
    this.onSeekInteraction,
    this.onSingleTap,
    this.onLongPress,
    this.onLongPressUp,
    super.key,
  });

  @override
  State<DoubleTapSeekOverlay> createState() => _DoubleTapSeekOverlayState();
}

class _DoubleTapSeekOverlayState extends State<DoubleTapSeekOverlay>
    with SingleTickerProviderStateMixin {
  Timer? _badgeHideTimer;
  bool _showBadge = false;
  bool _badgeForward = true;
  int _accumulatedSeconds = 0;
  DateTime? _lastDoubleTapTime;
  bool? _lastDirection;
  Duration? _pendingTarget;
  late final AnimationController _badgeAnimation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void dispose() {
    _badgeHideTimer?.cancel();
    _badgeAnimation.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    if (!widget.enabled()) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? MediaQuery.of(context).size.width;
    final isForward = details.localPosition.dx >= width / 2;

    final totalDur = widget.duration();
    if (totalDur == Duration.zero) return;

    final now = DateTime.now();
    final isFastSequence =
        _lastDoubleTapTime != null &&
        now.difference(_lastDoubleTapTime!).inMilliseconds <= 750 &&
        _lastDirection == isForward;

    if (isFastSequence) {
      _accumulatedSeconds += 5;
    } else {
      _accumulatedSeconds = 5;
      _lastDirection = isForward;
    }
    _lastDoubleTapTime = now;

    final currentPos = isFastSequence && _pendingTarget != null
        ? _pendingTarget!
        : widget.position();
    var target = isForward
        ? currentPos + kDefaultSeekDuration
        : currentPos - kDefaultSeekDuration;

    if (target < Duration.zero) target = Duration.zero;
    if (target > totalDur) target = totalDur;

    _pendingTarget = target;
    widget.seekTo(target);
    widget.onSeekInteraction?.call();
    _showSeekBadge(isForward);
  }

  void _showSeekBadge(bool forward) {
    _badgeHideTimer?.cancel();
    setState(() {
      _badgeForward = forward;
      _showBadge = true;
    });
    _badgeAnimation.forward(from: 0);
    _badgeHideTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted) return;
      setState(() {
        _showBadge = false;
        _accumulatedSeconds = 0;
        _lastDoubleTapTime = null;
        _pendingTarget = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: widget.onSingleTap,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: () {},
          onLongPress: widget.onLongPress,
          onLongPressUp: widget.onLongPressUp,
          child: Container(constraints: const BoxConstraints.expand()),
        ),
        if (_showBadge)
          SafeArea(
            top: false,
            bottom: false,
            child: Align(
              alignment: _badgeForward
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showBadge ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.8, end: 1).animate(
                        CurvedAnimation(
                          parent: _badgeAnimation,
                          curve: Curves.easeOutQuad,
                        ),
                      ),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(color: strokeFaintDark, width: 1),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            HugeIcon(
                              icon: _badgeForward
                                  ? HugeIcons.strokeRoundedArrowRightDouble
                                  : HugeIcons.strokeRoundedArrowLeftDouble,
                              size: 22,
                              color: textBaseDark,
                            ),
                            Text(
                              "${_accumulatedSeconds}s",
                              style: getEnteTextTheme(
                                context,
                              ).tiny.copyWith(color: textBaseDark),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
