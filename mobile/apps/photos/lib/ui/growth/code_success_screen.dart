import "package:dotted_border/dotted_border.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/gateways/storage_bonus/models/storage_bonus.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/ui/growth/storage_details_screen.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/utils/share_util.dart";

class CodeSuccessScreen extends StatelessWidget {
  final ReferralView referralView;
  final UserDetails userDetails;

  const CodeSuccessScreen(this.referralView, this.userDetails, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.codeAppliedPageTitle,
      children: [
        Column(
          children: [
            const SizedBox(height: Spacing.xl),
            Container(
              width: 69,
              height: 69,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check, color: colors.specialWhite, size: 40),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              l10n.storageClaimed(
                storageAmountInGB: referralView.planInfo.storageInGB,
              ),
              style: TextStyles.h1.copyWith(color: colors.textBase),
            ),
            const SizedBox(height: 40),
            MenuComponent(
              title: l10n.details,
              trailing: Icon(
                Icons.chevron_right_outlined,
                color: colors.textLight,
                size: IconSizes.medium,
              ),
              onTap: () async {
                await routeToPage(
                  context,
                  StorageDetailsScreen(referralView, userDetails),
                );
              },
            ),
            const SizedBox(height: Spacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Spacing.xxl),
              decoration: BoxDecoration(
                color: colors.fillLight,
                borderRadius: BorderRadius.circular(Radii.lg),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Text(
                        l10n.earnMoreSpace,
                        style: TextStyles.bodyBold.copyWith(
                          color: colors.textBase,
                        ),
                      ),
                      const SizedBox(height: Spacing.md),
                      Text(
                        l10n.referralStorageForBoth(
                          storageAmountInGB: referralView.planInfo.storageInGB,
                        ),
                        style: TextStyles.body.copyWith(
                          color: colors.textLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Spacing.md),
                      DottedBorder(
                        options: RoundedRectDottedBorderOptions(
                          color: colors.primary,
                          strokeWidth: 1,
                          dashPattern: const [6, 6],
                          radius: const Radius.circular(Radii.lg),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 36,
                            vertical: Spacing.xl,
                          ),
                          child: Text(
                            referralView.code,
                            style: TextStyles.body.copyWith(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButtonComponent(
                      variant: .unfilled,
                      shouldSurfaceExecutionStates: false,
                      tooltip: l10n.share,
                      icon: HugeIcon(
                        icon: HugeIcons.strokeRoundedShare08,
                        color: colors.textLight,
                      ),
                      onTap: () {
                        shareText(
                          l10n.shareTextReferralCode(
                            referralCode: referralView.code,
                            referralStorageInGB:
                                referralView.planInfo.storageInGB,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.xxl),
          ],
        ),
      ],
    );
  }
}
