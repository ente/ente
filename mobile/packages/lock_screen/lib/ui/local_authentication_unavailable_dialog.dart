import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/auth_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:ente_utils/platform_util.dart';
import 'package:flutter/material.dart';

const linuxSystemAuthGuideUrl =
    'https://ente.com/help/auth/troubleshooting/linux-system-auth';

bool shouldShowLinuxSystemAuthSetupGuide(
  LocalAuthenticationUnavailableException exception,
) {
  return exception.issue == LocalAuthUnavailableIssue.linuxSetupRequired;
}

Future<void> showLocalAuthenticationUnavailableMessage(
  BuildContext context,
  LocalAuthenticationUnavailableException exception, {
  VoidCallback? onOpenGuide,
}) async {
  if (shouldShowLinuxSystemAuthSetupGuide(exception)) {
    await showLinuxSystemAuthSetupDialog(context, onOpenGuide: onOpenGuide);
    return;
  }
  showToast(context, exception.userMessage);
}

Future<void> showLinuxSystemAuthSetupDialog(
  BuildContext context, {
  VoidCallback? onOpenGuide,
}) async {
  await showBottomSheetComponent(
    context: context,
    builder: (context) => BottomSheetComponent(
      title: pendingTranslation('Linux setup required'),
      message: pendingTranslation(
        'To use device lock on Linux, Ente Auth needs a one-time system authentication setup. The guide includes setup steps for Flatpak, AppImage, and fingerprint prompts.',
      ),
      actions: [
        ButtonComponent(
          label: pendingTranslation('Open guide'),
          dismissModalOnSuccess: true,
          onTap: () async {
            onOpenGuide?.call();
            await PlatformUtil.openWebView(
              context,
              pendingTranslation('Linux setup required'),
              linuxSystemAuthGuideUrl,
            );
          },
        ),
      ],
    ),
  );
}
