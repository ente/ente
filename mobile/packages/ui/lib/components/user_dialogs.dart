import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/buttons/button_widget.dart";
import "package:ente_ui/components/buttons/models/button_type.dart";
import "package:ente_ui/components/dialog_widget.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";

Future<void> showInviteDialog(BuildContext context, String email) async {
  await showDialogWidget(
    context: context,
    title: context.strings.inviteToEnte,
    icon: Icons.info_outline,
    body: context.strings.emailNoEnteAccount(email),
    isDismissible: true,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.neutral,
        icon: Icons.adaptive.share,
        labelText: context.strings.sendInvite,
        isInAlert: true,
        onTap: () async {
          unawaited(shareText(context.strings.shareTextRecommendUsingEnte));
        },
      ),
    ],
  );
}
