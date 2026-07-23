import "package:dotted_border/dotted_border.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/growth/change_referral_code_sheet.dart";
import "package:photos/utils/dialog_util.dart";

class ReferralCodeWidget extends StatelessWidget {
  final String codeValue;
  final bool shouldShowEdit;
  final UserDetails? userDetails;
  final Function? notifyParent;

  const ReferralCodeWidget(
    this.codeValue, {
    this.shouldShowEdit = false,
    this.userDetails,
    this.notifyParent,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    const greenColor = Color(0xFF08C225);
    final cardColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);

    // The edit button is 24px (6px padding + 12px icon + 6px padding)
    // Plus 12px tap padding on each side = 48px total tap area
    // We need extra space at bottom-right for the overlapping button
    const editButtonSize = 24.0;
    const tapPadding = 12.0;
    const overlapAmount = editButtonSize / 2; // How much it overlaps the box

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Add padding to the code box to make room for the edit button in layout
        Padding(
          padding: EdgeInsets.only(
            bottom: shouldShowEdit ? overlapAmount + tapPadding : 0,
            right: shouldShowEdit ? overlapAmount + tapPadding : 0,
          ),
          child: DottedBorder(
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
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 20),
              child: Text(
                codeValue,
                style: textTheme.small.copyWith(color: greenColor),
              ),
            ),
          ),
        ),
        if (shouldShowEdit)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (userDetails!.isPartOfFamily() &&
                    !userDetails!.isFamilyAdmin()) {
                  final String familyAdmin = userDetails!.familyData!.members!
                      .firstWhere((element) => element.isAdmin)
                      .email;
                  showInfoDialog(
                    context,
                    title: AppLocalizations.of(context).error,
                    body: AppLocalizations.of(context)
                        .onlyFamilyAdminCanChangeCode(
                          familyAdminEmail: familyAdmin,
                        ),
                    icon: Icons.error,
                  );
                } else {
                  showChangeReferralCodeSheet(
                    context,
                    currentCode: codeValue,
                    onCodeChanged: () => notifyParent?.call(),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(tapPadding),
                child: Container(
                  decoration: const BoxDecoration(
                    color: greenColor,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const HugeIcon(
                    icon: HugeIcons.strokeRoundedEdit03,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
