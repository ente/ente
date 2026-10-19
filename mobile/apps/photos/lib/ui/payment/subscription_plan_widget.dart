import "dart:math" as math;

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';

class SubscriptionPlanWidget extends StatelessWidget {
  const SubscriptionPlanWidget({
    super.key,
    required this.storage,
    required this.price,
    required this.period,
    this.monthlyPrice,
    this.isActive = false,
    this.isPopular = false,
  });

  static const double height = 84;
  static const double _borderWidth = 2;
  static const double _horizontalPadding = Spacing.xl - _borderWidth;
  static const double _verticalPadding = Spacing.lg - _borderWidth;
  static const double _contentMinHeight =
      height - 2 * _borderWidth - 2 * _verticalPadding;
  static const double _badgeWidth = 102;
  static const double _badgeHeight = 26;
  static const double _badgeLineHeight = 20;
  static const double _badgeVerticalPadding =
      (_badgeHeight - _badgeLineHeight) / 2;

  final int storage;
  final String price;
  final String period;

  final String? monthlyPrice;
  final bool isActive;
  final bool isPopular;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final numAndUnit = convertBytesToNumberAndUnit(storage);
    int storageValueInUnit = numAndUnit.$1;
    String storageUnit = numAndUnit.$2.toUpperCase();
    if (storageUnit == "TB") {
      storageValueInUnit = storageValueInUnit * 1000;
      storageUnit = "GB";
    }
    final String storageValue = storageValueInUnit.toString();
    final badgeHeight =
        MediaQuery.textScalerOf(context).scale(_badgeLineHeight) +
        2 * _badgeVerticalPadding;
    final badgeOverflow = isPopular
        ? math.max(0.0, badgeHeight - _badgeHeight)
        : 0.0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.button),
        border: Border.all(
          color: isActive ? colors.primary : Colors.transparent,
          width: _borderWidth,
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              _horizontalPadding,
              _verticalPadding + badgeOverflow,
              _horizontalPadding,
              _verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: _contentMinHeight),
              child: Column(
                mainAxisAlignment: isPopular
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                color: colors.textBase,
                                fontFamily: TextStyles.outfitFontFamily,
                                package: TextStyles.fontPackage,
                                fontWeight: FontWeight.w900,
                              ),
                              children: [
                                TextSpan(
                                  text: storageValue,
                                  style: const TextStyle(
                                    fontSize: 36,
                                    height: 28 / 36,
                                    letterSpacing: -1.8,
                                  ),
                                ),
                                const TextSpan(
                                  text: " ",
                                  style: TextStyle(
                                    fontSize: 24,
                                    height: 28 / 24,
                                    letterSpacing: -0.96,
                                  ),
                                ),
                                TextSpan(
                                  text: storageUnit,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 28 / 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            textHeightBehavior: const TextHeightBehavior(
                              applyHeightToFirstAscent: false,
                              applyHeightToLastDescent: false,
                            ),
                          ),
                        ),
                      ),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: _Price(
                            price: price,
                            period: period,
                            monthlyPrice: monthlyPrice,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isPopular)
            Positioned(
              left: -_borderWidth,
              top: -_borderWidth,
              child: Container(
                constraints: const BoxConstraints(
                  minWidth: _badgeWidth,
                  minHeight: _badgeHeight,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: _badgeVerticalPadding,
                ),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(Radii.button),
                    bottomRight: Radius.circular(Radii.button),
                  ),
                ),
                child: Text(
                  context.strings.mostPopular,
                  textAlign: TextAlign.center,
                  style: TextStyles.tiny.copyWith(
                    color: colors.specialWhite,
                    fontFamily: TextStyles.outfitFontFamily,
                    fontWeight: FontWeight.w700,
                    height: _badgeLineHeight / 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({
    required this.price,
    required this.period,
    required this.monthlyPrice,
  });

  final String price;
  final String period;
  final String? monthlyPrice;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final amountStyle = TextStyles.large.copyWith(
      color: colors.textBase,
      height: 28 / 16,
    );
    final periodStyle = TextStyles.mini.copyWith(
      color: colors.textLight,
      height: 28 / 12,
    );
    if (price.isEmpty) {
      return Text(context.strings.free, style: amountStyle);
    }

    if (period == "month") {
      return Text.rich(
        TextSpan(
          children: [
            TextSpan(text: price, style: amountStyle),
            TextSpan(text: "/${context.strings.month}", style: periodStyle),
          ],
        ),
        textAlign: TextAlign.end,
      );
    }

    assert(period == "year", "Invalid period: $period");
    final currencySymbol = price[0];
    final pricePerMonth = double.parse(price.substring(1)) / 12;
    String pricePerMonthString = pricePerMonth.toStringAsFixed(2);
    if (pricePerMonthString.endsWith(".00")) {
      pricePerMonthString = pricePerMonthString.substring(
        0,
        pricePerMonthString.length - 3,
      );
    }
    final perMonthStyle = TextStyles.tiny.copyWith(
      color: colors.textLight,
      height: 16 / 10,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: price, style: amountStyle),
              TextSpan(text: "/${context.strings.year}", style: periodStyle),
            ],
          ),
          textAlign: TextAlign.end,
        ),
        Text.rich(
          TextSpan(
            children: [
              if (monthlyPrice != null) ...[
                TextSpan(
                  text: monthlyPrice,
                  style: perMonthStyle.copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: colors.textLight,
                  ),
                ),
                const TextSpan(text: " → "),
              ],
              TextSpan(
                text:
                    "$currencySymbol$pricePerMonthString"
                    "/${context.strings.month}",
              ),
            ],
            style: perMonthStyle,
          ),
          textAlign: TextAlign.end,
        ),
      ],
    );
  }
}
