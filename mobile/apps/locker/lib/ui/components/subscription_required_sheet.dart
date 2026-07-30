import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";

Future<void> showSubscriptionRequiredSheet(BuildContext context) async {
  final l10n = context.l10n;

  await showBottomSheetComponent(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: l10n.sorry,
      message: l10n.subscriptionRequiredForSharing,
      illustration: LockerBottomSheetIllustration.warningBlue,
    ),
  );
}
