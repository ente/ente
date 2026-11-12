import 'dart:async';
import 'dart:math' as math;

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/faq/faq_widgets.dart';
import 'package:ente_ui/components/subscription/billing_period_toggle.dart';
import 'package:ente_ui/components/subscription/family_card.dart';
import 'package:flutter/material.dart';
import "package:intl/intl.dart";
import 'package:photos/gateways/billing/models/subscription.dart';
import "package:photos/gateways/storage_bonus/models/bonus.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/payment/billing_questions_widget.dart';

class ValidityWidget extends StatelessWidget {
  final Subscription? currentSubscription;
  final BonusData? bonusData;

  const ValidityWidget({super.key, this.currentSubscription, this.bonusData});

  @override
  Widget build(BuildContext context) {
    final List<Bonus> addOnBonus = bonusData?.getAddOnBonuses() ?? <Bonus>[];
    if (currentSubscription == null ||
        (currentSubscription!.isFreePlan() && addOnBonus.isEmpty)) {
      return const SizedBox(height: 56);
    }
    final bool isFreeTrialSub = currentSubscription!.productID == freeProductID;
    bool hideSubValidityView = false;
    if (isFreeTrialSub && addOnBonus.isNotEmpty) {
      hideSubValidityView = true;
    }
    if (!currentSubscription!.isValid()) {
      hideSubValidityView = true;
    }
    final endDate =
        DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(
          DateTime.fromMicrosecondsSinceEpoch(currentSubscription!.expiryTime),
        );

    var message = context.strings.renewsOn(endDate: endDate);
    if (currentSubscription!.attributes?.isCancelled ?? false) {
      message = context.strings.subWillBeCancelledOn(endDate: endDate);
      if (addOnBonus.isNotEmpty) {
        hideSubValidityView = true;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: [
          if (!hideSubValidityView)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                message,
                style: getEnteTextTheme(
                  context,
                ).body.copyWith(fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
          if (addOnBonus.isNotEmpty)
            ...addOnBonus.map((bonus) => AddOnBonusValidity(bonus)),
        ],
      ),
    );
  }
}

class AddOnBonusValidity extends StatelessWidget {
  final Bonus bonus;

  const AddOnBonusValidity(this.bonus, {super.key});

  @override
  Widget build(BuildContext context) {
    final endDate = DateFormat.yMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(DateTime.fromMicrosecondsSinceEpoch(bonus.validTill));
    final String storage = convertBytesToReadableFormat(bonus.storage);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        context.strings.addOnValidTill(
          storageAmount: storage,
          endDate: endDate,
        ),
        style: getEnteTextTheme(context).smallFaint,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class SubscriptionContinueButton extends StatelessWidget {
  const SubscriptionContinueButton({
    super.key,
    required this.label,
    this.onTap,
    this.isDisabled = false,
  });

  final String label;
  final FutureOr<void> Function()? onTap;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyles.large.copyWith(
      fontFamily: TextStyles.outfitFontFamily,
      package: TextStyles.fontPackage,
      fontWeight: FontWeight.w700,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          maxLines: 2,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.localeOf(context),
        )..layout(maxWidth: math.max(0, constraints.maxWidth - Spacing.xl * 2));
        final fits = !painter.didExceedMaxLines;
        painter.dispose();
        return ButtonComponent(
          label: fits ? label : context.strings.continueLabel,
          labelStyle: labelStyle,
          variant: ButtonComponentVariant.neutral,
          shouldShowSuccessState: false,
          isDisabled: isDisabled,
          onTap: onTap,
        );
      },
    );
  }
}

class SubFaqWidget extends StatelessWidget {
  const SubFaqWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return FaqCard(
      title: context.strings.faqs,
      subtitle: context.strings.subscriptionFaqDescription,
      onTap: () => showPlanFaqSheet(context),
    );
  }
}

class SubscriptionFamilyWidget extends StatelessWidget {
  const SubscriptionFamilyWidget({
    super.key,
    required this.title,
    required this.onTap,
  });

  final String title;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return FamilyCard(
      title: title,
      subtitle: context.strings.subscriptionFamilyDescription,
      onTap: onTap,
    );
  }
}

Future<void> showPlanFaqSheet(BuildContext context) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: context.strings.faqs,
      isScrollable: true,
      initialChildSize: 0.6,
      content: const BillingQuestionsWidget(),
    ),
  );
}

class SubscriptionToggle extends StatelessWidget {
  const SubscriptionToggle({
    super.key,
    required this.isYearly,
    required this.onToggle,
  });

  final bool isYearly;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) => BillingPeriodToggle(
    monthlyLabel: context.strings.monthly,
    yearlyLabel: context.strings.yearly,
    isYearly: isYearly,
    onToggle: onToggle,
  );
}
