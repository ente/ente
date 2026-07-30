import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

class StorageDetailsScreen extends StatefulWidget {
  final ReferralView referralView;
  final UserDetails userDetails;

  const StorageDetailsScreen(this.referralView, this.userDetails, {super.key});

  @override
  State<StorageDetailsScreen> createState() => _StorageDetailsScreenState();
}

class _StorageDetailsScreenState extends State<StorageDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.referralStats,
      children: [
        FutureBuilder<BonusDetails>(
          future: storageBonusService.getBonusDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 80),
                child: Center(child: EnteLoadingWidget()),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: Text(
                    l10n.oopsSomethingWentWrong,
                    style: TextStyles.body.copyWith(
                      color: context.componentColors.textLight,
                    ),
                  ),
                ),
              );
            }

            final BonusDetails data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        value: data.refCount.toString(),
                        label: l10n.usedYourCode,
                      ),
                    ),
                    const SizedBox(width: Spacing.lg),
                    Expanded(
                      child: _StatCard(
                        value: data.refUpgradeCount.toString(),
                        label: l10n.eligible,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.lg),
                if (data.hasAppliedCode) ...[
                  _StatCard(value: "1", label: l10n.claimedByYou),
                  const SizedBox(height: Spacing.lg),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _StatCard(
                        value:
                            "${convertBytesToAbsoluteGBs(widget.referralView.claimedStorage)} GB",
                        label: l10n.earned,
                      ),
                    ),
                    const SizedBox(width: Spacing.lg),
                    Expanded(
                      child: _StatCard(
                        value:
                            "${convertBytesToAbsoluteGBs(min(widget.referralView.claimedStorage, widget.userDetails.getPlanPlusAddonStorage()))} GB",
                        label: l10n.usable,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Spacing.xxl),
                Text(
                  l10n.referralStorageInfo,
                  style: TextStyles.body.copyWith(
                    color: context.componentColors.textLight,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: Spacing.xxl),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;

  const _StatCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyles.h1.copyWith(color: colors.primary)),
          const SizedBox(height: Spacing.xs),
          Text(label, style: TextStyles.body.copyWith(color: colors.textLight)),
        ],
      ),
    );
  }
}
