import 'package:flutter/material.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/extensions/file_props.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/ui/components/action_sheet_widget.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/components/models/button_type.dart';
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/utils/dialog_util.dart';

bool canSuggestDeleteForFile({required EnteFile file, Collection? collection}) {
  if (collection == null || file.uploadedFileID == null) {
    return false;
  }
  if (file.isOwner) {
    return false;
  }
  final int? currentUserID = Configuration.instance.getUserID();
  if (currentUserID == null) {
    return false;
  }
  return collection.isOwner(currentUserID) || collection.isAdmin(currentUserID);
}

typedef SuggestDeleteConfirmCallback = Future<void> Function();

Future<bool> showSuggestDeleteSheet({
  required BuildContext context,
  required SuggestDeleteConfirmCallback onConfirm,
}) async {
  final l10n = AppLocalizations.of(context);
  final actionResult = await showActionSheet(
    context: context,
    title: l10n.suggestDeletion,
    body: l10n.suggestDeletionDescription,
    actionSheetType: ActionSheetType.defaultActionSheet,
    buttons: [
      ButtonWidget(
        labelText: l10n.suggestDeletion,
        buttonType: ButtonType.neutral,
        buttonSize: ButtonSize.large,
        shouldStickToDarkTheme: true,
        buttonAction: ButtonAction.first,
        isInAlert: true,
        onTap: () async {
          await onConfirm();
          if (!context.mounted) return;
          showShortToast(context, l10n.deleteSuggestionSent);
        },
      ),
      ButtonWidget(
        labelText: l10n.cancel,
        buttonType: ButtonType.secondary,
        buttonSize: ButtonSize.large,
        shouldStickToDarkTheme: true,
        buttonAction: ButtonAction.second,
        isInAlert: true,
      ),
    ],
  );

  if (actionResult?.action == ButtonAction.error) {
    if (!context.mounted) return false;
    await showGenericErrorDialog(
      context: context,
      error:
          actionResult?.exception ??
          Exception("Failed to send delete suggestion"),
    );
    return false;
  }

  return actionResult?.action == ButtonAction.first;
}
