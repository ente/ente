import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/logout_util.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

bool showingLogoutDialog = false;
Future<void> autoLogoutAlert(BuildContext context) async {
  if (showingLogoutDialog) {
    debugPrint("Ignore event as already logging out");
    return;
  }
  try {
    showingLogoutDialog = true;
    final l10n = context.l10n;
    await showErrorDialog(
      context,
      l10n.sessionExpired,
      l10n.pleaseLoginAgain,
      isDismissable: false,
      showContactSupport: false,
      dismissButtonLabel: l10n.ok,
      useRootNavigator: true,
    );
    if (!context.mounted) return;

    Navigator.of(context).popUntil((route) => route.isFirst);
    final pendingSyncCount = await AuthenticatorDB.instance.getNeedSyncCount();
    if (!context.mounted) return;
    if (pendingSyncCount > 0) {
      // ignore: unawaited_futures
      showChoiceActionSheet(
        context,
        title: l10n.pendingSyncs,
        body: l10n.pendingSyncsWarningBody,
        firstButtonLabel: context.l10n.yesLogout,
        isCritical: true,
        firstButtonOnTap: () async {
          // The session is already gone, so sign out locally.
          await completeLogout(context, serverSideLogout: false);
        },
      );
    } else {
      await completeLogout(context, serverSideLogout: false);
    }
  } catch (e) {
    Logger("LogoutDialog").severe('failed to process sign out action', e);
  } finally {
    showingLogoutDialog = false;
  }
}
