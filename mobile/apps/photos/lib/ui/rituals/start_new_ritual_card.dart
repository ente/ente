import "dart:math" as math;

import "package:ente_components/theme/text_styles.dart";
import "package:ente_icons/ente_icons.dart";
import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/utils/pending_translation.dart";

enum StartNewRitualCardVariant { compact, wide }

class StartNewRitualCard extends StatelessWidget {
  const StartNewRitualCard({
    super.key,
    required this.variant,
    required this.onTap,
    double? compactHeight,
  }) : _compactHeightOverride = compactHeight,
       assert(
         variant == StartNewRitualCardVariant.compact || compactHeight == null,
       );

  final StartNewRitualCardVariant variant;
  final VoidCallback onTap;
  final double? _compactHeightOverride;

  static const _cardRadius = 25.0;
  static const _cardHeight = 94.0;
  static const _compactHeight = 94.0;
  static const _compactWidth = 167.5;
  static const _wideHorizontalPadding = 20.0;
  static const _wideBottomPadding = 14.0;
  static const _wideIllustrationWidth = 123.0;
  static const _wideIllustrationHeight = 116.0;
  static const _wideIllustrationRight = 10.0;
  static const _wideIllustrationTop = -27.0;

  static double compactHeightFor(BuildContext context) {
    final titleHeight = _measuredTextHeight(
      context,
      text: pendingTranslation("Start new ritual"),
      style: _compactTitleStyle(Colors.black),
      maxWidth: _compactWidth - 24,
    );
    return math.max(_compactHeight, 16 + 24 + 4 + titleHeight + 16);
  }

  @override
  Widget build(BuildContext context) {
    if (variant == StartNewRitualCardVariant.compact) {
      return _CompactStartNewRitualCard(
        onTap: onTap,
        height: _compactHeightOverride,
      );
    }

    final colorScheme = getEnteColorScheme(context);
    final borderRadius = BorderRadius.circular(_cardRadius);
    final titleText = pendingTranslation("Start new ritual");
    final subtitleText = pendingTranslation(
      "Create a ritual, build streaks, and share your progress.",
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _WideRitualCardLayout.forWidth(
          context,
          constraints.maxWidth,
          titleText: titleText,
          subtitleText: subtitleText,
          titleStyle: _wideTitleStyle(colorScheme.textBase),
          subtitleStyle: TextStyles.tiny.copyWith(color: colorScheme.textMuted),
        );

        return SizedBox(
          height: layout.cardHeight,
          child: Material(
            color: colorScheme.fill,
            borderRadius: borderRadius,
            child: InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _wideHorizontalPadding,
                    top: _wideHorizontalPadding,
                    width: layout.textWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Icon(
                              EnteIcons.lightningFilled,
                              size: 13,
                              color: Color(0xFFFFBC03),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                titleText,
                                style: _wideTitleStyle(colorScheme.textBase),
                                textHeightBehavior: _tightTextHeightBehavior,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          subtitleText,
                          style: TextStyles.tiny.copyWith(
                            color: colorScheme.textMuted,
                          ),
                          textHeightBehavior: _tightTextHeightBehavior,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    right: _wideIllustrationRight,
                    top: layout.illustrationTop,
                    width: layout.illustrationWidth,
                    height: layout.illustrationHeight,
                    child: const _WideRitualIllustration(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompactStartNewRitualCard extends StatelessWidget {
  const _CompactStartNewRitualCard({required this.onTap, required this.height});

  final VoidCallback onTap;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final borderRadius = BorderRadius.circular(StartNewRitualCard._cardRadius);
    return SizedBox(
      width: StartNewRitualCard._compactWidth,
      height: height ?? StartNewRitualCard._compactHeight,
      child: Material(
        color: colorScheme.fill,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Stack(
            children: [
              const Positioned(
                left: 50.5,
                top: 38,
                child: _SparkleIcon(size: 8),
              ),
              const Positioned(
                left: 103.25,
                top: 16.93,
                child: _SparkleIcon(size: 13),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: colorScheme.greenBase,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(child: _PlusSignIcon()),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        pendingTranslation("Start new ritual"),
                        style: _compactTitleStyle(colorScheme.textBase),
                        textAlign: TextAlign.center,
                        textHeightBehavior: _tightTextHeightBehavior,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

TextStyle _wideTitleStyle(Color color) {
  return const TextStyle(
    fontFamily: TextStyles.outfitFontFamily,
    package: TextStyles.fontPackage,
    fontSize: 16.72,
    fontWeight: FontWeight.w500,
    height: 21 / 16.72,
    letterSpacing: 0,
  ).copyWith(color: color);
}

TextStyle _compactTitleStyle(Color color) {
  return TextStyle(
    color: color,
    fontFamily: TextStyles.outfitFontFamily,
    package: TextStyles.fontPackage,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
}

class _PlusSignIcon extends StatelessWidget {
  static const _painter = _PlusSignPainter();

  const _PlusSignIcon();

  @override
  Widget build(BuildContext context) {
    return const CustomPaint(size: Size.square(9.33333), painter: _painter);
  }
}

class _PlusSignPainter extends CustomPainter {
  const _PlusSignPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 9.33333;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawLine(
        Offset(4.66667 * scale, 1 * scale),
        Offset(4.66667 * scale, 8.33333 * scale),
        paint,
      )
      ..drawLine(
        Offset(8.33333 * scale, 4.66667 * scale),
        Offset(1 * scale, 4.66667 * scale),
        paint,
      );
  }

  @override
  bool shouldRepaint(covariant _PlusSignPainter oldDelegate) => false;
}

class _SparkleIcon extends StatelessWidget {
  static const _painter = _SparklePainter();

  const _SparkleIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _painter);
  }
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const bend = 0.2761875;
    const inverseBend = 1 - bend;
    final midX = size.width / 2;
    final midY = size.height / 2;
    final path = Path()
      ..moveTo(size.width, midY)
      ..cubicTo(
        size.width * inverseBend,
        midY,
        midX,
        size.height * bend,
        midX,
        0,
      )
      ..cubicTo(midX, size.height * bend, size.width * bend, midY, 0, midY)
      ..cubicTo(
        size.width * bend,
        midY,
        midX,
        size.height * inverseBend,
        midX,
        size.height,
      )
      ..cubicTo(
        midX,
        size.height * inverseBend,
        size.width * inverseBend,
        midY,
        size.width,
        midY,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFB800));
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => false;
}

class _WideRitualCardLayout {
  const _WideRitualCardLayout({
    required this.cardHeight,
    required this.textWidth,
    required this.illustrationWidth,
    required this.illustrationHeight,
    required this.illustrationTop,
  });

  static const _textIllustrationGap = 12.0;
  static const _minIllustrationScale = 0.86;
  static const _narrowWidth = 320.0;

  final double cardHeight;
  final double textWidth;
  final double illustrationWidth;
  final double illustrationHeight;
  final double illustrationTop;

  factory _WideRitualCardLayout.forWidth(
    BuildContext context,
    double width, {
    required String titleText,
    required String subtitleText,
    required TextStyle titleStyle,
    required TextStyle subtitleStyle,
  }) {
    final widthScale = width < _narrowWidth ? width / _narrowWidth : 1.0;
    final illustrationScale = widthScale
        .clamp(_minIllustrationScale, 1.0)
        .toDouble();
    final illustrationWidth =
        StartNewRitualCard._wideIllustrationWidth * illustrationScale;
    final illustrationHeight =
        StartNewRitualCard._wideIllustrationHeight * illustrationScale;
    final textWidth = math.max(
      0.0,
      width -
          StartNewRitualCard._wideHorizontalPadding -
          _textIllustrationGap -
          StartNewRitualCard._wideIllustrationRight -
          illustrationWidth,
    );
    const titleIconWidth = 13.0;
    const titleIconGap = 8.0;
    final titleTextWidth = math.max(
      0.0,
      textWidth - titleIconWidth - titleIconGap,
    );
    final titleHeight = _measuredTextHeight(
      context,
      text: titleText,
      style: titleStyle,
      maxWidth: titleTextWidth,
    );
    final subtitleHeight = _measuredTextHeight(
      context,
      text: subtitleText,
      style: subtitleStyle,
      maxWidth: textWidth,
    );
    final textHeight = titleHeight + 6 + subtitleHeight;
    final cardHeight = math.max(
      StartNewRitualCard._cardHeight,
      StartNewRitualCard._wideHorizontalPadding +
          textHeight +
          StartNewRitualCard._wideBottomPadding,
    );

    return _WideRitualCardLayout(
      cardHeight: cardHeight,
      textWidth: textWidth,
      illustrationWidth: illustrationWidth,
      illustrationHeight: illustrationHeight,
      illustrationTop:
          StartNewRitualCard._wideIllustrationTop * illustrationScale,
    );
  }
}

class _WideRitualIllustration extends StatelessWidget {
  const _WideRitualIllustration();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      "assets/rituals/search_start_ritual_illustration.png",
      fit: BoxFit.contain,
    );
  }
}

double _measuredTextHeight(
  BuildContext context, {
  required String text,
  required TextStyle style,
  required double maxWidth,
  int? maxLines,
}) {
  if (maxWidth <= 0) {
    return 0;
  }
  final textPainter = TextPainter(
    text: TextSpan(text: text, style: style),
    maxLines: maxLines,
    ellipsis: maxLines == null ? null : "…",
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: _tightTextHeightBehavior,
  )..layout(maxWidth: maxWidth);
  return textPainter.height;
}

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);
