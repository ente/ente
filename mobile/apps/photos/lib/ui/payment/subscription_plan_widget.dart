import 'dart:math' as math;

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";

class SubscriptionPlanWidget extends StatelessWidget {
  const SubscriptionPlanWidget({
    super.key,
    required this.storage,
    required this.price,
    required this.period,
    required this.isOnboarding,
    this.isActive = false,
    this.isPopular = false,
  });

  final int storage;
  final String price;
  final String period;
  final bool isActive;
  final bool isPopular;
  final bool isOnboarding;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final numAndUnit = convertBytesToNumberAndUnit(storage);
    int storageValueInUnit = numAndUnit.$1;
    String storageUnit = numAndUnit.$2.toUpperCase();
    if (storageUnit == "TB") {
      storageValueInUnit = storageValueInUnit * 1000;
      storageUnit = "GB";
    }
    final String storageValue = storageValueInUnit.toString();
    final bool isSelected = isActive;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 24),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minHeight: 72),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.greenLight : colorScheme.fill,
              borderRadius: BorderRadius.circular(20),
              border: isSelected
                  ? Border.all(color: colorScheme.greenBase, width: 2)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            color: colorScheme.contentDarker,
                            fontFamily: "Nunito",
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
                              text: storageUnit.isEmpty
                                  ? ""
                                  : storageUnit.substring(0, 1),
                              style: const TextStyle(
                                fontSize: 16,
                                height: 28 / 16,
                                letterSpacing: -0.64,
                              ),
                            ),
                            TextSpan(
                              text: storageUnit.length > 1
                                  ? storageUnit.substring(1)
                                  : "",
                              style: const TextStyle(
                                fontSize: 16,
                                height: 28 / 16,
                              ),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.left,
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
                      child: _Price(price: price, period: period),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isPopular)
            Positioned(
              right: -8,
              top: -4,
              child: Transform.rotate(
                angle: 8 * math.pi / 180,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.greenBase,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: const Text(
                    "Most popular",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: "Nunito",
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      height: 20 / 10,
                    ),
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
  final String price;
  final String period;

  const _Price({required this.price, required this.period});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    if (price.isEmpty) {
      return Text(
        "Free",
        style: textTheme.bodyBold.copyWith(
          color: colorScheme.contentDarker,
          fontFamily: "Inter",
          fontSize: 16,
          height: 28 / 16,
        ),
      );
    }

    if (period == "month") {
      return Text.rich(
        TextSpan(
          style: textTheme.largeBold.copyWith(
            color: colorScheme.contentDarker,
            height: 1.1,
          ),
          children: [
            TextSpan(text: price),
            TextSpan(
              text: "/${AppLocalizations.of(context).month}",
              style: textTheme.small.copyWith(color: colorScheme.contentLight),
            ),
          ],
        ),
        textAlign: TextAlign.end,
      );
    }

    if (period == "year") {
      final currencySymbol = price[0];
      final priceWithoutCurrency = price.substring(1);
      final priceDouble = double.parse(priceWithoutCurrency);
      final pricePerMonth = priceDouble / 12;
      String pricePerMonthString = pricePerMonth.toStringAsFixed(2);

      if (pricePerMonthString.endsWith(".00")) {
        pricePerMonthString = pricePerMonthString.substring(
          0,
          pricePerMonthString.length - 3,
        );
      }

      final bool isPlayStore = updateService.isPlayStoreFlavor();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (isPlayStore)
            Text.rich(
              TextSpan(
                style: textTheme.largeBold.copyWith(
                  color: colorScheme.contentDarker,
                  height: 1.1,
                ),
                children: [
                  TextSpan(text: price),
                  TextSpan(
                    text: "/${AppLocalizations.of(context).yearShort}",
                    style: textTheme.small.copyWith(
                      color: colorScheme.contentLight,
                    ),
                  ),
                ],
              ),
              textAlign: TextAlign.end,
            ),
          if (isPlayStore)
            Text(
              "$currencySymbol$pricePerMonthString / ${AppLocalizations.of(context).month}",
              style: textTheme.tiny.copyWith(color: colorScheme.contentLight),
              textAlign: TextAlign.end,
            ),
          if (!isPlayStore)
            Text(
              "$currencySymbol$pricePerMonthString / ${AppLocalizations.of(context).month}",
              style: textTheme.largeBold.copyWith(
                color: colorScheme.contentDarker,
              ),
              textAlign: TextAlign.end,
            ),
          if (!isPlayStore)
            Text.rich(
              TextSpan(
                style: textTheme.tiny.copyWith(color: colorScheme.contentLight),
                children: [
                  TextSpan(text: price),
                  TextSpan(text: "/${AppLocalizations.of(context).yearShort}"),
                ],
              ),
              textAlign: TextAlign.end,
            ),
        ],
      );
    } else {
      assert(false, "Invalid period: $period");
      return const Text("");
    }
  }
}
