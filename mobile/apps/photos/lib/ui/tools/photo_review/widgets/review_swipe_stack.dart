import "dart:async";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/ui/viewer/file/file_icons_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

enum ReviewSwipeDirection { left, right }

extension ReviewSwipeDirectionDecision on ReviewSwipeDirection {
  ReviewDecision get decision => switch (this) {
    ReviewSwipeDirection.left => ReviewDecision.queued,
    ReviewSwipeDirection.right => ReviewDecision.keep,
  };

  double get sign => this == ReviewSwipeDirection.right ? 1 : -1;
}

class ReviewSwipeStackController {
  _ReviewSwipeStackState? _state;

  bool get isSwipingOut => _state?._flying ?? false;

  bool get isDragging => _state?._dragging ?? false;

  Future<void> swipe(ReviewSwipeDirection direction) async {
    await _state?._flyOut(direction);
  }

  void _detach(_ReviewSwipeStackState state) {
    if (identical(_state, state)) _state = null;
  }

  void revealFromSide(ReviewSwipeDirection direction) {
    _state?._revealFromSide(direction);
  }
}

class ReviewSwipeStack extends StatefulWidget {
  const ReviewSwipeStack({
    required this.files,
    required this.controller,
    required this.onSwiped,
    required this.onCardTap,
    required this.isFavorite,
    super.key,
  });

  static const double aspectRatio = 312.9 / 503;
  static const double horizontalInset = 31;
  static const double backCardPeek = 26;
  static const double _backCardRise = 53.5;
  static const double _backCardScale = 273 / 312.9;
  static const double _backCardShift = 23;
  static const double _backCardTilt = 4.06;
  static const double _minCardWidth = 80;
  static const double _cardRadius = 21;
  static const double _cardBorder = 4.2;
  static const double _maxTiltDegrees = 12;
  static const double _swipeFraction = 0.3;
  static const double _glowFraction = 0.21;
  static const double _flingVelocity = 800;
  static const double _verticalDamping = 0.2;
  static const double _maxVerticalDrift = 24;

  final List<EnteFile> files;
  final ReviewSwipeStackController controller;
  final Future<void> Function(EnteFile file, ReviewSwipeDirection direction)
  onSwiped;
  final ValueChanged<EnteFile> onCardTap;
  final bool Function(EnteFile file) isFavorite;

  @override
  State<ReviewSwipeStack> createState() => _ReviewSwipeStackState();
}

class _ReviewSwipeStackState extends State<ReviewSwipeStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );
  Animation<Offset>? _tween;
  Offset _drag = Offset.zero;
  bool _dragging = false;
  bool _flying = false;
  bool _crossedThreshold = false;
  Size _cardSize = Size.zero;
  _SideGlow? _keepGlow;
  _SideGlow? _deleteGlow;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _animation.addListener(() {
      final tween = _tween;
      if (tween != null) {
        setState(() => _drag = tween.value);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ReviewSwipeStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._detach(this);
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    widget.controller._detach(this);
    _animation.dispose();
    super.dispose();
  }

  double get _threshold => _cardSize.width * ReviewSwipeStack._swipeFraction;

  Future<void> _animateTo(Offset target, {Curve curve = Curves.easeOutCubic}) {
    _tween = Tween(
      begin: _drag,
      end: target,
    ).animate(CurvedAnimation(parent: _animation, curve: curve));
    _animation
      ..reset()
      ..duration = Motion.slow;
    return _animation.forward().orCancel.catchError((_) {});
  }

  Future<void> _flyOut(ReviewSwipeDirection direction) async {
    if (_flying || _dragging || widget.files.isEmpty || !mounted) return;
    final file = widget.files.first;
    _flying = true;
    final width = MediaQuery.sizeOf(context).width;
    final target = Offset(direction.sign * (width + _cardSize.width), _drag.dy);
    unawaited(HapticFeedback.mediumImpact());
    await _animateTo(target, curve: Curves.easeIn);
    if (!mounted) return;
    _tween = null;
    _drag = Offset.zero;
    _flying = false;
    _crossedThreshold = false;
    await widget.onSwiped(file, direction);
  }

  void _revealFromSide(ReviewSwipeDirection direction) {
    if (!mounted) return;
    final width = MediaQuery.sizeOf(context).width;
    _drag = Offset(direction.sign * (width + _cardSize.width), 0);
    unawaited(_animateTo(Offset.zero));
  }

  void _onPanStart(DragStartDetails details) {
    if (_flying) return;
    _animation.stop();
    _tween = null;
    _dragging = true;
    _crossedThreshold = false;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() {
      final dy =
          _drag.dy + details.delta.dy * ReviewSwipeStack._verticalDamping;
      _drag = Offset(
        _drag.dx + details.delta.dx,
        dy.clamp(
          -ReviewSwipeStack._maxVerticalDrift,
          ReviewSwipeStack._maxVerticalDrift,
        ),
      );
    });
    final crossed = _drag.dx.abs() >= _threshold;
    if (crossed != _crossedThreshold) {
      _crossedThreshold = crossed;
      if (crossed) unawaited(HapticFeedback.selectionClick());
    }
  }

  void _onPanEnd(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final passed = _drag.dx.abs() >= _threshold;
    final flung = velocity.abs() >= ReviewSwipeStack._flingVelocity;
    if (passed || flung) {
      final direction = (passed ? _drag.dx : velocity) > 0
          ? ReviewSwipeDirection.right
          : ReviewSwipeDirection.left;
      unawaited(_flyOut(direction));
    } else {
      unawaited(_animateTo(Offset.zero));
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math
            .min(
              constraints.maxWidth - ReviewSwipeStack.horizontalInset * 2,
              (constraints.maxHeight - ReviewSwipeStack.backCardPeek) *
                  ReviewSwipeStack.aspectRatio,
            )
            .clamp(ReviewSwipeStack._minCardWidth, double.infinity);
        _cardSize = Size(width, width / ReviewSwipeStack.aspectRatio);
        final files = widget.files.take(3).toList();
        final glow =
            (_drag.dx / (_cardSize.width * ReviewSwipeStack._glowFraction))
                .clamp(-1.0, 1.0);
        final tilt =
            (_drag.dx / _cardSize.width * ReviewSwipeStack._maxTiltDegrees)
                .clamp(
                  -ReviewSwipeStack._maxTiltDegrees,
                  ReviewSwipeStack._maxTiltDegrees,
                ) *
            math.pi /
            180;

        _keepGlow = _glowFor(_keepGlow, context.componentColors.primary);
        _deleteGlow = _glowFor(_deleteGlow, _SideGlow.deleteColor);

        return Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              right: -81 - _SideGlow.spread,
              top: -_SideGlow.spread,
              child: IgnorePointer(
                child: Opacity(opacity: glow.clamp(0, 1), child: _keepGlow),
              ),
            ),
            Positioned(
              left: -72 - _SideGlow.spread,
              top: -_SideGlow.spread,
              child: IgnorePointer(
                child: Opacity(
                  opacity: (-glow).clamp(0, 1),
                  child: _deleteGlow,
                ),
              ),
            ),
            for (var index = files.length - 1; index >= 0; index--)
              _positionedCard(files[index], index, tilt),
          ],
        );
      },
    );
  }

  _SideGlow _glowFor(_SideGlow? cached, Color color) {
    if (cached != null &&
        cached.color == color &&
        cached.cardHeight == _cardSize.height) {
      return cached;
    }
    return _SideGlow(color: color, cardHeight: _cardSize.height);
  }

  Widget _positionedCard(EnteFile file, int index, double topTilt) {
    final isTop = index == 0;
    final depth = index.clamp(0, 2);
    final back = !isTop;
    final shift = back
        ? (depth == 1 ? 1 : -1) * ReviewSwipeStack._backCardShift
        : 0.0;
    final scale = back ? ReviewSwipeStack._backCardScale : 1.0;
    final backTilt = back
        ? (depth == 1 ? 1 : -1) * ReviewSwipeStack._backCardTilt * math.pi / 180
        : 0.0;
    final translate = back
        ? Offset(
            shift,
            ReviewSwipeStack.backCardPeek - ReviewSwipeStack._backCardRise,
          )
        : Offset(_drag.dx, ReviewSwipeStack.backCardPeek + _drag.dy);
    final transform = Matrix4.identity()
      ..translateByDouble(translate.dx, translate.dy, 0, 1)
      ..translateByDouble(_cardSize.width / 2, _cardSize.height / 2, 0, 1)
      ..rotateZ(back ? backTilt : topTilt)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-_cardSize.width / 2, -_cardSize.height / 2, 0, 1);

    final card = RepaintBoundary(
      child: _ReviewCard(
        file: file,
        size: _cardSize,
        radius: ReviewSwipeStack._cardRadius,
        border: ReviewSwipeStack._cardBorder,
        isFavorite: widget.isFavorite(file),
        onTap: isTop ? () => widget.onCardTap(file) : null,
      ),
    );

    return Positioned(
      key: ValueKey("review_card_${file.tag}"),
      top: 0,
      child: AnimatedContainer(
        duration: _dragging || _flying || _animation.isAnimating
            ? Duration.zero
            : Motion.slow,
        curve: Curves.easeOutCubic,
        transform: transform,
        child: isTop
            ? GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onPanCancel: () => _onPanEnd(DragEndDetails()),
                child: card,
              )
            : IgnorePointer(child: card),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.file,
    required this.size,
    required this.radius,
    required this.border,
    required this.isFavorite,
    required this.onTap,
  });

  final EnteFile file;
  final Size size;
  final double radius;
  final double border;
  final bool isFavorite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final fileSize = file.fileSize;
    return Semantics(
      button: onTap != null,
      label: file.displayName,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: colors.fillDark,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: colors.specialWhite, width: border),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                offset: Offset(0, 6.031),
                blurRadius: 14.7,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - border),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ThumbnailWidget(
                  file,
                  key: Key("review_swipe_${file.tag}"),
                  thumbnailSize: thumbnailLargeSize,
                  shouldShowSyncStatus: false,
                  shouldShowFavoriteIcon: false,
                  shouldShowVideoOverlayIcon: false,
                  placeholderColor: colors.fillDark,
                ),
                if (file.fileType == FileType.video)
                  Center(child: _VideoIndicator(duration: file.duration)),
                if (fileSize != null)
                  Positioned(
                    left: Spacing.lg,
                    top: Spacing.lg,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.md,
                        vertical: Spacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.specialScrim,
                        borderRadius: BorderRadius.circular(38),
                      ),
                      child: Text(
                        formatBytes(fileSize, fileSize >= 1024 * 1024 ? 1 : 0),
                        style: TextStyles.mini.copyWith(
                          color: colors.specialWhite,
                        ),
                      ),
                    ),
                  ),
                if (isFavorite)
                  Positioned(
                    right: Spacing.lg,
                    top: Spacing.lg,
                    child: SvgPicture.asset(
                      "assets/photo_review/favorite_star.svg",
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        colors.specialWhite,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoIndicator extends StatelessWidget {
  const _VideoIndicator({required this.duration});

  final int? duration;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final seconds = duration ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.specialScrim,
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.specialWhite.withValues(alpha: 0.16),
              width: 1,
            ),
          ),
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedPlay,
            size: 32,
            color: colors.specialWhite,
          ),
        ),
        if (seconds > 0) ...[
          const SizedBox(height: Spacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: Spacing.xs,
            ),
            decoration: BoxDecoration(
              color: colors.specialScrim,
              borderRadius: BorderRadius.circular(38),
            ),
            child: Text(
              formatVideoDuration(seconds),
              style: TextStyles.mini.copyWith(color: colors.specialWhite),
            ),
          ),
        ],
      ],
    );
  }
}

class _SideGlow extends StatelessWidget {
  const _SideGlow({required this.color, required this.cardHeight});

  static const double _width = 120;
  static const double _top = 58;
  static const double _bottomInset = 31;
  static const double _blurSigma = 60;
  static const double spread = _blurSigma * 3;
  static const Color deleteColor = Color(0xFFFF4C38);

  final Color color;
  final double cardHeight;

  @override
  Widget build(BuildContext context) {
    final height = math.max(0.0, cardHeight - _bottomInset);
    final boxHeight = spread + _top + height + spread;
    return RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [
            Color(0x00FFFFFF),
            Color(0x00FFFFFF),
            Color(0xFFFFFFFF),
          ],
          stops: [0, spread / boxHeight, (spread + _top) / boxHeight],
        ).createShader(bounds),
        child: SizedBox(
          width: _width + spread * 2,
          height: boxHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: spread,
                top: spread + _top,
                child: Container(
                  width: _width,
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_width / 2),
                    boxShadow: [
                      BoxShadow(
                        color: color,
                        blurRadius: (_blurSigma - 0.5) / 0.57735,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
