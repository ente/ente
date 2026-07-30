import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_utils/email_util.dart" show sendLogs;
import "package:flutter/material.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";

/// Shows Locker's standard generic-error bottom sheet.
///
/// Parses [error] into a user-facing message via [parseErrorForUI] and offers a
/// "contact support" action that ships logs. Kept as a single helper so every
/// catch block stays a one-liner instead of re-inlining the same sheet config.
Future<void> showLockerErrorSheet(BuildContext context, Object? error) {
  return showErrorBottomSheetComponent<void>(
    context: context,
    title: context.strings.error,
    message: parseErrorForUI(
      context,
      context.strings.itLooksLikeSomethingWentWrongPleaseRetryAfterSome,
      error: error,
    ),
    illustration: LockerBottomSheetIllustration.warningGrey,
    actionLabel: context.strings.contactSupport,
    onActionTap: () => sendLogs(context, "support@ente.com", postShare: () {}),
  );
}
