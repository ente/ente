import 'dart:ui' show lerpDouble;

import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

class SubscriptionPrice extends StatelessWidget {
  const SubscriptionPrice({
    super.key,
    required this.amount,
    this.periodLabel,
    this.monthlyPriceLabel,
    this.originalMonthlyPrice,
    this.isSelected = false,
  });

  final String amount;
  final String? periodLabel;
  final String? monthlyPriceLabel;
  final String? originalMonthlyPrice;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final selection = isSelected ? 1.0 : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: selection, end: selection),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : Motion.slow,
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => _buildPrice(context, progress),
    );
  }

  Widget _buildPrice(BuildContext context, double selection) {
    final colors = context.componentColors;
    final lineHeight = periodLabel == null
        ? 20.0
        : lerpDouble(28, 20, selection)!;
    final foreground = Color.lerp(
      colors.textBase,
      colors.specialWhite,
      selection,
    );
    final secondaryForeground = Color.lerp(
      colors.textLight,
      colors.specialWhite.withValues(alpha: 0.6),
      selection,
    );
    final amountStyle = TextStyles.large.copyWith(
      color: foreground,
      height: lineHeight / 16,
    );
    final periodStyle = TextStyles.mini.copyWith(
      color: secondaryForeground,
      height: lineHeight / 12,
      fontWeight: FontWeight.w600,
    );
    if (periodLabel == null) {
      return Text(amount, style: amountStyle);
    }

    if (monthlyPriceLabel == null) {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: amount, style: amountStyle),
            TextSpan(text: "/$periodLabel", style: periodStyle),
          ],
        ),
        textAlign: TextAlign.end,
      );
    }

    final perMonthStyle = TextStyles.tiny.copyWith(
      color: secondaryForeground,
      height: 16.8067 / 10,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: amount, style: amountStyle),
              TextSpan(text: "/$periodLabel", style: periodStyle),
            ],
          ),
          textAlign: TextAlign.end,
          strutStyle: StrutStyle(
            fontFamily: TextStyles.fontFamily,
            package: TextStyles.fontPackage,
            fontSize: 16,
            height: lineHeight / 16,
            forceStrutHeight: true,
          ),
        ),
        Align(
          alignment: Alignment.bottomRight,
          widthFactor: 1,
          heightFactor: lerpDouble(15 / 17, 1, selection),
          child: Text.rich(
            TextSpan(
              children: [
                if (originalMonthlyPrice != null) ...[
                  TextSpan(
                    text: originalMonthlyPrice!,
                    style: perMonthStyle.copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Color.lerp(
                        colors.textLight,
                        colors.specialWhite,
                        selection,
                      ),
                    ),
                  ),
                  const TextSpan(text: " → "),
                ],
                TextSpan(text: monthlyPriceLabel!),
              ],
              style: perMonthStyle,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
