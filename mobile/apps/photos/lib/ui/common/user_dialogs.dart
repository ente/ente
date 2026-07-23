import "dart:async";

import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/dialog_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/utils/share_util.dart";

Future<void> showInviteDialog(BuildContext context, String email) async {
  await showDialogWidget(
    context: context,
    title: AppLocalizations.of(context).inviteToEnte,
    icon: Icons.info_outline,
    body: AppLocalizations.of(context).emailNoEnteAccount(email: email),
    isDismissible: true,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.neutral,
        icon: Icons.adaptive.share,
        labelText: AppLocalizations.of(context).sendInvite,
        isInAlert: true,
        onTap: () async {
          unawaited(
            shareText(AppLocalizations.of(context).shareTextRecommendUsingEnte),
          );
        },
      ),
    ],
  );
}
