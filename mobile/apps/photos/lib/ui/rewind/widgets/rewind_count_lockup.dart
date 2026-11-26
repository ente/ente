import "dart:math";

import "package:flutter/widgets.dart";

class RewindCountLockup extends StatelessWidget {
  const RewindCountLockup({
    required this.number,
    required this.numberText,
    required this.numberStyle,
    required this.label,
    required this.labelText,
    required this.labelStyle,
    required this.overhang,
    required this.drop,
    this.minNumberWidth = 0,
    super.key,
  });

  static const _wideLabelOverlap = 0.3;

  final Widget number;
  final String numberText;
  final TextStyle numberStyle;
  final Widget label;
  final String labelText;
  final TextStyle labelStyle;
  final double overhang;
  final double drop;
  final double minNumberWidth;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final size = numberStyle.fontSize ?? 14;
    final grow = scaler.scale(size) / size;
    final numberSize = _measure(numberText, numberStyle, scaler);
    final labelSize = _measure(labelText, labelStyle, scaler);
    final numberWidth = max(numberSize.width, minNumberWidth * grow);
    final reach = numberWidth + overhang * grow;
    final labelTop = labelSize.width <= reach
        ? numberSize.height + drop * grow - labelSize.height
        : numberSize.height - labelSize.height * _wideLabelOverlap;
    final numberLeft = max(0.0, labelSize.width - reach);
    return SizedBox(
      width: numberLeft + reach,
      height: labelTop + labelSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: numberLeft,
            top: 0,
            width: numberWidth,
            child: Align(alignment: Alignment.centerRight, child: number),
          ),
          Positioned(
            left: max(0.0, reach - labelSize.width),
            top: labelTop,
            child: label,
          ),
        ],
      ),
    );
  }

  static Size _measure(String text, TextStyle style, TextScaler scaler) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final size = painter.size;
    painter.dispose();
    return size;
  }
}
