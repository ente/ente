import "package:ente_sharing/components/gradient_button.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/base_bottom_sheet.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:ente_utils/share_utils.dart";
import "package:flutter/material.dart";

/// Shows the invite sheet when a user doesn't have an Ente account
Future<void> showInviteSheet(BuildContext context, {required String email}) {
  return showBaseBottomSheet<void>(
    context,
    title: context.strings.inviteToEnte,
    headerSpacing: 20,
    crossAxisAlignment: CrossAxisAlignment.center,
    child: InviteSheet(email: email),
  );
}

class InviteSheet extends StatelessWidget {
  final String email;

  const InviteSheet({super.key, required this.email});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.strings.emailNoEnteAccount(email),
          style: textTheme.small.copyWith(color: colorScheme.textMuted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        GradientButton(
          text: context.strings.sendInvite,
          onTap: () {
            shareText(context.strings.shareTextRecommendUsingEnte);
          },
        ),
      ],
    );
  }
}
