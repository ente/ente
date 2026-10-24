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
    final colors = context.componentColors;
    final lineHeight = isSelected || periodLabel == null ? 20.0 : 28.0;
    final amountStyle = TextStyles.large.copyWith(
      color: isSelected ? colors.specialWhite : colors.textBase,
      height: lineHeight / 16,
    );
    final periodStyle = TextStyles.mini.copyWith(
      color: isSelected
          ? colors.specialWhite.withValues(alpha: 0.6)
          : colors.textLight,
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
      color: isSelected
          ? colors.specialWhite.withValues(alpha: 0.6)
          : colors.textLight,
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
          heightFactor: isSelected ? 1 : 15 / 17,
          child: Text.rich(
            TextSpan(
              children: [
                if (originalMonthlyPrice != null) ...[
                  TextSpan(
                    text: originalMonthlyPrice!,
                    style: perMonthStyle.copyWith(
                      decoration: TextDecoration.lineThrough,
                      decorationColor: isSelected
                          ? colors.specialWhite
                          : colors.textLight,
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
