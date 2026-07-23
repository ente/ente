import "package:dotted_border/dotted_border.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/growth/storage_details_screen.dart";
import "package:photos/utils/share_util.dart";

class CodeSuccessScreen extends StatelessWidget {
  final ReferralView referralView;
  final UserDetails userDetails;

  const CodeSuccessScreen(this.referralView, this.userDetails, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);
    const greenColor = Color(0xFF08C225);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
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
                  AppLocalizations.of(context).codeAppliedPageTitle,
                  style: textTheme.largeBold,
                ),
                const SizedBox(height: 42),
                // Success icon and claimed text
                Center(
                  child: Column(
                    children: [
                      // Green circle with checkmark
                      Container(
                        width: 69,
                        height: 69,
                        decoration: const BoxDecoration(
                          color: greenColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // "10 GB claimed!" text
                      Text(
                        AppLocalizations.of(context).storageClaimed(
                          storageAmountInGB: referralView.planInfo.storageInGB,
                        ),
                        style: textTheme.h3Bold,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 42),
                // Details button
                GestureDetector(
                  onTap: () {
                    routeToPage(
                      context,
                      StorageDetailsScreen(referralView, userDetails),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          AppLocalizations.of(context).details,
                          style: textTheme.body,
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: colorScheme.strokeMuted,
                          size: 31,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Earn more space card
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        children: [
                          Text(
                            AppLocalizations.of(context).earnMoreSpace,
                            style: textTheme.bodyBold,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            AppLocalizations.of(context).referralStorageForBoth(
                              storageAmountInGB:
                                  referralView.planInfo.storageInGB,
                            ),
                            style: textTheme.small.copyWith(
                              color: colorScheme.textMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          // Referral code with dotted border
                          DottedBorder(
                            options: const RoundedRectDottedBorderOptions(
                              color: greenColor,
                              strokeWidth: 1,
                              dashPattern: [6, 6],
                              radius: Radius.circular(16),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                color: cardColor,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 36,
                                vertical: 20,
                              ),
                              child: Text(
                                referralView.code,
                                style: textTheme.small.copyWith(
                                  color: greenColor,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Share button positioned at top right
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          shareText(
                            AppLocalizations.of(context).shareTextReferralCode(
                              referralCode: referralView.code,
                              referralStorageInGB:
                                  referralView.planInfo.storageInGB,
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: HugeIcon(
                            icon: HugeIcons.strokeRoundedShare08,
                            color: colorScheme.strokeMuted,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
