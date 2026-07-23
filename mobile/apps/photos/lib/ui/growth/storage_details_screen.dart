import "dart:math";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";

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
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: SafeArea(
        child: FutureBuilder<BonusDetails>(
          future: storageBonusService.getBonusDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        color: colorScheme.strokeBase,
                        size: 24,
                      ),
                    ),
                    const Expanded(child: Center(child: EnteLoadingWidget())),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        color: colorScheme.strokeBase,
                        size: 24,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          AppLocalizations.of(context).oopsSomethingWentWrong,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            final BonusDetails data = snapshot.data!;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    // Back arrow
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Icon(
                        Icons.arrow_back,
                        color: colorScheme.strokeBase,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Title
                    Text(
                      AppLocalizations.of(context).referralStats,
                      style: textTheme.largeBold,
                    ),
                    const SizedBox(height: 24),
                    // Stats cards
                    Column(
                      children: [
                        // Row 1: Used your code + Eligible
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                value: data.refCount.toString(),
                                label: AppLocalizations.of(
                                  context,
                                ).usedYourCode,
                                cardColor: cardColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _StatCard(
                                value: data.refUpgradeCount.toString(),
                                label: AppLocalizations.of(context).eligible,
                                cardColor: cardColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Row 2: Claimed by you (only if has applied code)
                        if (data.hasAppliedCode) ...[
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  value: "1",
                                  label: AppLocalizations.of(
                                    context,
                                  ).claimedByYou,
                                  cardColor: cardColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        // Row 3: Earned + Usable
                        Row(
                          children: [
                            Expanded(
                              child: _StatCard(
                                value:
                                    "${convertBytesToAbsoluteGBs(widget.referralView.claimedStorage)} GB",
                                label: AppLocalizations.of(context).earned,
                                cardColor: cardColor,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _StatCard(
                                value:
                                    "${convertBytesToAbsoluteGBs(min(widget.referralView.claimedStorage, widget.userDetails.getPlanPlusAddonStorage()))} GB",
                                label: AppLocalizations.of(context).usable,
                                cardColor: cardColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Info text
                    Text(
                      AppLocalizations.of(context).referralStorageInfo,
                      style: textTheme.small.copyWith(
                        color: colorScheme.textMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 60),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color cardColor;

  const _StatCard({
    required this.value,
    required this.label,
    required this.cardColor,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    const greenColor = Color(0xFF08C225);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: textTheme.h3Bold.copyWith(color: greenColor)),
          const SizedBox(height: 4),
          Text(label, style: textTheme.smallMuted),
        ],
      ),
    );
  }
}
