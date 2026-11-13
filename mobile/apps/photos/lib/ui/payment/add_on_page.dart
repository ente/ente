import "package:ente_components/components/app_bar_component.dart";
import "package:ente_components/theme/text_styles.dart";
import "package:ente_components/theme/theme.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/gateways/storage_bonus/models/bonus.dart";

class AddOnPage extends StatelessWidget {
  final BonusData bonusData;

  const AddOnPage(this.bonusData, {super.key});

  String _sectionNameForBonusType(String bonusType) {
    switch (bonusType) {
      case "ADD_ON_BF_2023":
        return "Black Friday 2023";
      case "ADD_ON_BF_2024":
        return "Black Friday 2024";
      case "ADD_ON_SUPPORT":
        return "Support";
      case "ADD_ON_NON_PROFIT":
        return "Non-profit";
      default:
        return bonusType.replaceAll("_", " ");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBarComponent(
        title: context.strings.addOns,
        subtitle: context.strings.addOnPageSubtitle,
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((
                delegateBuildContext,
                index,
              ) {
                final bonus = bonusData.getAddOnBonuses()[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AddOnViewSection(
                    sectionName: _sectionNameForBonusType(bonus.type),
                    bonus: bonus,
                  ),
                );
              }, childCount: bonusData.getAddOnBonuses().length),
            ),
          ),
        ],
      ),
    );
  }
}

class AddOnViewSection extends StatelessWidget {
  final String sectionName;
  final Bonus bonus;

  const AddOnViewSection({
    super.key,
    required this.sectionName,
    required this.bonus,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              sectionName,
              style: TextStyles.large.copyWith(color: colors.textLight),
            ),
            if (bonus.validTill != 0)
              Text(
                context.strings.validTill(
                  endDate:
                      DateFormat.yMMMd(
                            Localizations.localeOf(context).languageCode,
                          )
                          .format(
                            DateTime.fromMicrosecondsSinceEpoch(
                              bonus.validTill,
                            ),
                          )
                          .toString(),
                ),
                style: TextStyles.large.copyWith(color: colors.textLight),
              ),
          ],
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: convertBytesToReadableFormat(bonus.storage).toString(),
                style: TextStyles.display2.copyWith(color: colors.textBase),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
