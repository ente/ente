import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/utils/dialog_util.dart';
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
    final AlertDialog alert = AlertDialog(
      title: Text(l10n.sessionExpired),
      content: Text(l10n.pleaseLoginAgain),
      actions: [
        TextButton(
          child: Text(
            l10n.ok,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
          onPressed: () async {
            Navigator.of(context, rootNavigator: true).pop('dialog');
            Navigator.of(context).popUntil((route) => route.isFirst);
            int pendingSyncCount = await AuthenticatorDB.instance
                .getNeedSyncCount();
            if (pendingSyncCount > 0) {
              if (!context.mounted) return;
              // ignore: unawaited_futures
              showChoiceActionSheet(
                context,
                title: l10n.pendingSyncs,
                body: l10n.pendingSyncsWarningBody,
                firstButtonLabel: context.l10n.yesLogout,
                isCritical: true,
                firstButtonOnTap: () async {
                  await _logout(context, l10n);
                },
              );
            } else {
              if (!context.mounted) return;
              await _logout(context, l10n);
            }
          },
        ),
      ],
    );
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return alert;
      },
    );
  } catch (e) {
    Logger("LogoutDialog").severe('failed to process sign out action', e);
  } finally {
    showingLogoutDialog = false;
  }
}

Future<void> _logout(BuildContext context, AppLocalizations l10n) async {
  final dialog = createProgressDialog(context, l10n.loggingOut);
  await dialog.show();
  await Configuration.instance.logout();
  await dialog.hide();
}
