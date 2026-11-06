import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/gateways/storage_bonus/models/bonus.dart";
import "package:photos/ui/payment/add_on_page.dart";

class ViewAddOnButton extends StatelessWidget {
  final BonusData? bonusData;

  const ViewAddOnButton(this.bonusData, {super.key});

  @override
  Widget build(BuildContext context) {
    if (bonusData?.getAddOnBonuses().isEmpty ?? true) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: NavigationCardComponent(
        title: context.strings.viewAddOnButton,
        leading: HugeIcon(
          icon: HugeIcons.strokeRoundedDatabase,
          size: NavigationCardComponent.leadingSize,
          color: context.componentColors.textLight,
        ),
        onTap: () async {
          await routeToPage(context, AddOnPage(bonusData!));
        },
      ),
    );
  }
}
