import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/models/photo_review/photo_review_models.dart";

class ReviewBannerCarousel extends StatefulWidget {
  const ReviewBannerCarousel({
    required this.months,
    required this.horizontalPadding,
    required this.onTap,
    super.key,
  });

  static const double _barHeight = 6;

  final List<ReviewMonthSummary> months;
  final double horizontalPadding;
  final ValueChanged<ReviewMonthSummary> onTap;

  static double heightFor(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle style) =>
        scaler.scale(style.fontSize!) * style.height!;
    final textHeight =
        lineHeight(ReviewBanner.captionStyle) +
        lineHeight(ReviewBanner.titleStyle);
    return Spacing.lg * 2 + textHeight + Spacing.md + _barHeight;
  }

  @override
  State<ReviewBannerCarousel> createState() => _ReviewBannerCarouselState();
}

class _ReviewBannerCarouselState extends State<ReviewBannerCarousel> {
  static const double _gap = Spacing.md;
  static const double _maxCardWidth = 400;

  PageController? _controller;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  PageController _controllerFor(double viewportFraction) {
    final current = _controller;
    if (current != null && current.viewportFraction == viewportFraction) {
      return current;
    }
    final controller = PageController(viewportFraction: viewportFraction);
    _controller = controller;
    if (current != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => current.dispose());
    }
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.months;
    return SizedBox(
      height: ReviewBannerCarousel.heightFor(context),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardWidth = math.min(
            constraints.maxWidth - widget.horizontalPadding * 2,
            _maxCardWidth,
          );
          final viewportWidth = constraints.maxWidth - widget.horizontalPadding;
          final fraction = (cardWidth + _gap) / viewportWidth;
          return Padding(
            padding: EdgeInsets.only(left: widget.horizontalPadding),
            child: PageView.builder(
              controller: _controllerFor(fraction),
              padEnds: false,
              clipBehavior: Clip.none,
              physics: months.length > 1
                  ? const PageScrollPhysics()
                  : const NeverScrollableScrollPhysics(),
              itemCount: months.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.only(right: _gap),
                child: ReviewBanner(
                  month: months[index],
                  onTap: () => widget.onTap(months[index]),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class ReviewBanner extends StatelessWidget {
  const ReviewBanner({required this.month, required this.onTap, super.key});

  static final captionStyle = TextStyles.display3.copyWith(
    fontSize: 12,
    height: 20 / 12,
  );
  static final titleStyle = TextStyles.display2.copyWith(
    fontWeight: FontWeight.w700,
  );

  final ReviewMonthSummary month;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final inProgress = month.state == ReviewMonthState.inProgress;
    final locale = Localizations.localeOf(context).toString();
    final title = DateFormat.yMMMM(locale).format(month.key.start);
    final caption = inProgress
        ? l10n.reviewPickUpAgain
        : l10n.reviewLetsGetStartedWith;

    return Semantics(
      button: true,
      label: "$caption $title",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(
            minHeight: ReviewBannerCarousel.heightFor(context),
          ),
          padding: const EdgeInsets.all(Spacing.lg),
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: captionStyle.copyWith(
                                color: colors.textLighter,
                              ),
                            ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle.copyWith(
                                color: colors.textBase,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (inProgress) ...[
                        const SizedBox(width: Spacing.sm),
                        _PercentLabel(percent: month.progressPercent),
                      ] else
                        const SizedBox(width: 28 + Spacing.sm),
                    ],
                  ),
                  if (inProgress) ...[
                    const SizedBox(height: Spacing.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(200),
                      child: LinearProgressIndicator(
                        value: month.progress,
                        minHeight: 6,
                        backgroundColor: colors.fillDark,
                        valueColor: AlwaysStoppedAnimation(colors.primary),
                      ),
                    ),
                  ],
                ],
              ),
              Positioned(
                top: 0,
                bottom: inProgress ? null : 0,
                right: 0,
                child: Center(child: _ArrowButton(color: colors.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PercentLabel extends StatelessWidget {
  const _PercentLabel({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final text = context.strings.reviewPercentReviewed(percent: percent);
    final number = "$percent%";
    final start = text.indexOf(number);
    final style = TextStyles.tiny.copyWith(
      height: 13 / 10,
      color: colors.textDark,
    );
    final bold = style.copyWith(fontWeight: FontWeight.w700);
    return Text.rich(
      start < 0
          ? TextSpan(text: text, style: style)
          : TextSpan(
              style: style,
              children: [
                TextSpan(text: text.substring(0, start)),
                TextSpan(text: number, style: bold),
                TextSpan(text: text.substring(start + number.length)),
              ],
            ),
      maxLines: 1,
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: CustomPaint(
          painter: _ChevronPainter(color: context.componentColors.specialWhite),
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 28;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.394 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(11.4545 * scale, 8.4848 * scale)
      ..lineTo(17.3939 * scale, 14 * scale)
      ..lineTo(11.4545 * scale, 19.5152 * scale);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}
