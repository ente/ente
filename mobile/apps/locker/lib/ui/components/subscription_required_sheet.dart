import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";

Future<void> showSubscriptionRequiredSheet(BuildContext context) async {
  final l10n = context.strings;

  await showBottomSheetComponent(
    context: context,
    builder: (_) => BottomSheetComponent(
      title: l10n.sorry,
      message: l10n.subscriptionRequiredForSharing,
      illustration: LockerBottomSheetIllustration.warningBlue,
    ),
  );
}
