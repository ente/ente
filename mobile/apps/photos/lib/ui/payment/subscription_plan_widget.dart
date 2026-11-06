import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/subscription/plan_card.dart';
import 'package:ente_ui/components/subscription/plan_price.dart';
import 'package:flutter/material.dart';
import "package:photos/ui/payment/subscription_locker_sheet.dart";

String subscriptionStorageLabel(int storage) {
  final (value, unit) = convertBytesToNumberAndUnit(storage);
  return "$value ${unit.toUpperCase()}";
}

class SubscriptionPlanWidget extends StatelessWidget {
  const SubscriptionPlanWidget({
    super.key,
    required this.storage,
    required this.price,
    required this.period,
    this.monthlyPrice,
    this.isActive = false,
    this.isCurrentPlan = false,
    this.isPopular = false,
  });

  final int storage;
  final String price;
  final String period;
  final String? monthlyPrice;
  final bool isActive;
  final bool isCurrentPlan;
  final bool isPopular;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final (value, unit) = convertBytesToNumberAndUnit(storage);
    return SubscriptionPlanCard(
      value: value.toString(),
      unit: unit.toUpperCase(),
      isSelected: isActive,
      isFree: price.isEmpty,
      badgeLabel: isCurrentPlan
          ? context.strings.subscriptionCurrentPlan
          : isPopular
          ? context.strings.mostPopular
          : null,
      includedAllowance: isActive
          ? _LockerAllowance(
              count: price.isEmpty ? 100 : 1000,
              color: colors.specialWhite,
            )
          : null,
      onIncludedAllowanceTap: isActive
          ? () => showSubscriptionLockerSheet(context)
          : null,
      price: _Price(
        price: price,
        period: period,
        monthlyPrice: monthlyPrice,
        isActive: isActive,
      ),
    );
  }
}

class _LockerAllowance extends StatelessWidget {
  const _LockerAllowance({required this.count, required this.color});

  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = context.strings
        .subscriptionLockerItems(count: count, appName: "\uFFFC")
        .split("\uFFFC");
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: label[0]),
          const TextSpan(
            text: "Locker",
            style: TextStyle(decoration: TextDecoration.underline),
          ),
          TextSpan(text: label[1]),
        ],
      ),
      style: TextStyles.mini.copyWith(
        color: color,
        decorationColor: color,
        height: 18 / 12,
      ),
    );
  }
}

class _Price extends StatelessWidget {
  const _Price({
    required this.price,
    required this.period,
    required this.monthlyPrice,
    required this.isActive,
  });

  final String price;
  final String period;
  final String? monthlyPrice;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    if (price.isEmpty) {
      return SubscriptionPrice(
        amount: context.strings.free,
        isSelected: isActive,
      );
    }
    if (period == "month") {
      return SubscriptionPrice(
        amount: _displayPrice(price),
        periodLabel: context.strings.month,
        isSelected: isActive,
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
    return SubscriptionPrice(
      amount: _displayPrice(price),
      periodLabel: context.strings.year,
      monthlyPriceLabel:
          "${_displayPrice("$currencySymbol$pricePerMonthString")}/${context.strings.month}",
      originalMonthlyPrice: monthlyPrice == null
          ? null
          : _displayPrice(monthlyPrice!),
      isSelected: isActive,
    );
  }
}

String _displayPrice(String price) {
  final parts = price.split(".");
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r"\d(?=(\d{3})+$)"),
    (match) => "${match[0]},",
  );
  return parts.join(".");
}
