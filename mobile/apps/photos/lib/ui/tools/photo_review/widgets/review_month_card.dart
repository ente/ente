import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class ReviewMonthCard extends StatelessWidget {
  const ReviewMonthCard({
    required this.cover,
    required this.label,
    required this.count,
    required this.state,
    required this.progress,
    required this.selected,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    super.key,
  });

  static const double width = 86;
  static const double height = 122;
  static const double borderWidth = 2.522;
  static const double radius = 10.088;
  static const String sparkleAsset = "assets/photo_review/sparkle.svg";
  static const double _labelBaselineShift = 2;
  static const List<BoxShadow> shadow = [
    BoxShadow(
      color: Color(0x40000000),
      offset: Offset(2.522, 2.522),
      blurRadius: 4.92,
    ),
  ];

  final EnteFile cover;
  final String label;
  final int count;
  final ReviewMonthState state;
  final double progress;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final white = colors.specialWhite;
    final showShadow = state != ReviewMonthState.inProgress;
    final labelText = Transform.translate(
      offset: const Offset(0, _labelBaselineShift),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          style: TextStyles.display2.copyWith(
            fontWeight: FontWeight.w700,
            height: 1,
            leadingDistribution: TextLeadingDistribution.even,
            color: white,
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: -borderWidth,
                top: -borderWidth,
                right: -borderWidth,
                bottom: -borderWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: white,
                    borderRadius: BorderRadius.circular(radius + borderWidth),
                    boxShadow: showShadow ? shadow : null,
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ThumbnailWidget(
                        cover,
                        key: Key("review_month_card_${cover.tag}"),
                        shouldShowSyncStatus: false,
                        shouldShowFavoriteIcon: false,
                        shouldShowVideoOverlayIcon: false,
                        placeholderColor: colors.fillDark,
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: state == ReviewMonthState.completed
                              ? _completedGradient
                              : _defaultGradient,
                        ),
                      ),
                      if (state == ReviewMonthState.completed)
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _completedTintGradient,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (state == ReviewMonthState.inProgress)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ProgressRingPainter(
                      progress: progress,
                      color: colors.primary,
                    ),
                  ),
                ),
              Positioned(
                left: Spacing.sm,
                right: Spacing.sm,
                top: Spacing.md,
                bottom: Spacing.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (state == ReviewMonthState.completed)
                      SvgPicture.asset(
                        sparkleAsset,
                        width: 13,
                        height: 13,
                        colorFilter: ColorFilter.mode(white, BlendMode.srcIn),
                      ),
                    const Spacer(),
                    if (state == ReviewMonthState.inProgress) ...[
                      _ProgressPill(progress: progress),
                      const SizedBox(height: Spacing.xs),
                    ],
                    labelText,
                  ],
                ),
              ),
              if (selected)
                const Positioned(top: -9, left: 71, child: _SelectedTick())
              else if (state == ReviewMonthState.normal)
                Positioned(top: -8, left: 70, child: _CountBadge(count: count)),
            ],
          ),
        ),
      ),
    );
  }

  static const _defaultGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xA3000000), Color(0x00000000)],
  );

  static const _completedTintGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x330F9223), Color(0x33000000)],
    stops: [0, 0.84],
  );

  static const _completedGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x69045E13), Color(0x4FFFFFFF), Color(0x694CE245)],
    stops: [0, 0.28846, 0.84],
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(19),
        boxShadow: ReviewMonthCard.shadow,
      ),
      alignment: Alignment.center,
      child: Text(
        count.toString(),
        maxLines: 1,
        style: TextStyles.tiny.copyWith(
          fontWeight: FontWeight.w700,
          height: null,
          color: colors.textLighter,
        ),
      ),
    );
  }
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Text(
        "${(progress * 100).floor()}%",
        maxLines: 1,
        style: TextStyles.tiny.copyWith(
          fontWeight: FontWeight.w700,
          height: null,
          color: colors.specialWhite,
        ),
      ),
    );
  }
}

class ReviewSelectedTick extends StatelessWidget {
  const ReviewSelectedTick({super.key});

  @override
  Widget build(BuildContext context) => const _SelectedTick();
}

class _SelectedTick extends StatelessWidget {
  const _SelectedTick();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.specialWhite, width: 1.5),
      ),
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedTick02,
        size: 12,
        strokeWidth: 3,
        color: colors.specialWhite,
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  static const double _strokeWidth = 5;
  static const double _radius = 12;
  static const Rect _ringRect = Rect.fromLTWH(-1.71, -1, 89, 125);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = _clockwiseRRectPath(_ringRect, _radius);
    final metric = path.computeMetrics().first;
    final visible = metric.extractPath(0, metric.length * progress.clamp(0, 1));
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.342);
    canvas.save();
    canvas.translate(2.522, 2.522);
    canvas.drawPath(visible, shadow);
    canvas.restore();
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(visible, paint);
  }

  static Path _clockwiseRRectPath(Rect rect, double radius) {
    final r = math.min(radius, math.min(rect.width, rect.height) / 2);
    final path = Path()..moveTo(rect.center.dx, rect.top);
    path.lineTo(rect.right - r, rect.top);
    path.arcToPoint(
      Offset(rect.right, rect.top + r),
      radius: Radius.circular(r),
    );
    path.lineTo(rect.right, rect.bottom - r);
    path.arcToPoint(
      Offset(rect.right - r, rect.bottom),
      radius: Radius.circular(r),
    );
    path.lineTo(rect.left + r, rect.bottom);
    path.arcToPoint(
      Offset(rect.left, rect.bottom - r),
      radius: Radius.circular(r),
    );
    path.lineTo(rect.left, rect.top + r);
    path.arcToPoint(
      Offset(rect.left + r, rect.top),
      radius: Radius.circular(r),
    );
    path.lineTo(rect.center.dx, rect.top);
    return path;
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
