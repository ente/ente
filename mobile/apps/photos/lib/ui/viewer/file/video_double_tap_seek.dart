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
  final Duration Function(Duration) seekBy;
  final VoidCallback? onSingleTap;
  final VoidCallback? onSeekInteraction;
  final GestureLongPressCallback? onLongPress;
  final GestureLongPressUpCallback? onLongPressUp;

  const DoubleTapSeekOverlay({
    required this.enabled,
    required this.position,
    required this.duration,
    required this.seekBy,
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
  Duration? _lastSeekTarget;
  TapDownDetails? _doubleTapDetails;
  int _seekGeneration = 0;
  late final AnimationController _badgeAnimation;

  @override
  void initState() {
    super.initState();
    _badgeAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
  }

  @override
  void dispose() {
    _badgeHideTimer?.cancel();
    _badgeAnimation.dispose();
    super.dispose();
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (!widget.enabled()) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? MediaQuery.of(context).size.width;
    final isForward = details.localPosition.dx >= width / 2;

    if (widget.duration() <= Duration.zero) return;

    final now = DateTime.now();
    final isFastSequence =
        _lastDoubleTapTime != null &&
        now.difference(_lastDoubleTapTime!).inMilliseconds <= 750 &&
        _lastDirection == isForward;

    final position = widget.position();
    final target = widget.seekBy(
      isForward ? kDefaultSeekDuration : -kDefaultSeekDuration,
    );
    if (isFastSequence && target == _lastSeekTarget) {
      _lastDoubleTapTime = now;
      _showSeekBadge(isForward);
      return;
    }
    if (target == position) {
      if (_showBadge) {
        _lastDoubleTapTime = now;
        _showSeekBadge(isForward);
      }
      return;
    }
    final requestedSeconds = kDefaultSeekDuration.inSeconds;

    if (isFastSequence) {
      _accumulatedSeconds += requestedSeconds;
    } else {
      _accumulatedSeconds = requestedSeconds;
      _lastDirection = isForward;
    }
    _lastDoubleTapTime = now;
    _lastSeekTarget = target;
    _seekGeneration++;

    widget.onSeekInteraction?.call();
    _showSeekBadge(isForward);
  }

  void _showSeekBadge(bool forward) {
    _badgeHideTimer?.cancel();
    final generation = _seekGeneration;
    setState(() {
      _badgeForward = forward;
      _showBadge = true;
    });
    _badgeAnimation.forward(from: 0);
    _badgeHideTimer = Timer(const Duration(milliseconds: 750), () {
      if (!mounted || generation != _seekGeneration) return;
      setState(() {
        _showBadge = false;
        _lastDoubleTapTime = null;
        _lastSeekTarget = null;
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
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTapCancel: () => _doubleTapDetails = null,
          onDoubleTap: () {
            if (_doubleTapDetails != null) {
              _handleDoubleTap(_doubleTapDetails!);
              _doubleTapDetails = null;
            }
          },
          onLongPress: widget.onLongPress,
          onLongPressUp: widget.onLongPressUp,
          child: Container(constraints: const BoxConstraints.expand()),
        ),
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
                      width: 54,
                      height: 54,
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
                            size: 20,
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
