import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
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

class SubFaqWidget extends StatelessWidget {
  const SubFaqWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MenuGroupComponent(
      items: [
        MenuComponent(
          title: context.strings.faqs,
          leading: HugeIcon(
            icon: HugeIcons.strokeRoundedHelpCircle,
            size: IconSizes.small,
            color: colors.textBase,
          ),
          trailing: HugeIcon(
            icon: HugeIcons.strokeRoundedArrowRight01,
            size: IconSizes.small,
            color: colors.textBase,
          ),
          onTap: () => showPlanFaqSheet(context),
        ),
      ],
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

class SubscriptionPlanList extends StatelessWidget {
  const SubscriptionPlanList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.sm),
          children[i],
        ],
      ],
    );
  }
}

class SubscriptionToggle extends StatefulWidget {
  final bool isYearly;
  final Function(bool) onToggle;
  const SubscriptionToggle({
    required this.isYearly,
    required this.onToggle,
    super.key,
  });

  @override
  State<SubscriptionToggle> createState() => _SubscriptionToggleState();
}

class _SubscriptionToggleState extends State<SubscriptionToggle> {
  static const double _padding = Spacing.xs;
  static const double _minSegmentHeight = 41;
  static const double _radius = 35;

  late bool _isYearly;

  @override
  void initState() {
    super.initState();
    _isYearly = widget.isYearly;
  }

  @override
  void didUpdateWidget(covariant SubscriptionToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isYearly != widget.isYearly) {
      _isYearly = widget.isYearly;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final labelStyle = TextStyles.body.copyWith(color: colors.textLight);
    return Container(
      padding: const EdgeInsets.all(_padding),
      decoration: BoxDecoration(
        color: colors.strokeFaint,
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: Motion.slow,
              curve: Curves.easeInOutCubic,
              alignment: _isYearly
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colors.fillLight,
                    borderRadius: BorderRadius.circular(_radius),
                  ),
                ),
              ),
            ),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _segment(context.strings.yearly, true, labelStyle),
                _segment(context.strings.monthly, false, labelStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment(String label, bool isYearly, TextStyle style) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setIsYearly(isYearly),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _minSegmentHeight),
          child: Center(
            child: Text(label, style: style, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
  }

  void setIsYearly(bool isYearly) {
    if (_isYearly == isYearly) return;
    setState(() {
      _isYearly = isYearly;
    });
    widget.onToggle(isYearly);
  }
}
