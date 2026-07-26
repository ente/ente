import 'dart:async';

import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/profile_service.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:flutter/material.dart';

/// Signs the active profile out and lands on whatever comes next.
///
/// Every logout has to go through here. Clearing the account on its own leaves
/// the process pointed at a scope with no data and its profile record still in
/// the registry, so '/' resolves to a vault that can no longer be opened;
/// dropping the record first is what makes '/' resolve to the next profile's
/// home, or to onboarding when none remain.
///
/// Pass [serverSideLogout] as false when the session is already gone (an
/// expired token, or a sign out that must not depend on the network), which
/// clears the account locally instead of calling the logout endpoint.
///
/// Pass [navigate] as false from the lock screen, which lives in the app lock's
/// own navigator: '/' is not a route there. Unlocking builds the app afresh, so
/// it lands on the surviving profile on its own.
Future<void> completeLogout(
  BuildContext context, {
  bool serverSideLogout = true,
  bool navigate = true,
}) async {
  final l10n = context.l10n;
  // Captured up front: the logout tears down the page that called this.
  final navigator = navigate
      ? Navigator.of(context, rootNavigator: true)
      : null;
  final dialog = createProgressDialog(context, l10n.loggingOut);
  await dialog.show();
  if (!context.mounted) {
    // Nothing left to navigate from, so leave the account signed in rather
    // than half tearing it down.
    await dialog.hide();
    return;
  }
  try {
    if (serverSideLogout) {
      // Navigation is ours, so that it happens only once the record is gone.
      await UserService.instance.logout(context, navigate: false);
    } else {
      await Configuration.instance.logout();
    }
    await ProfileService.instance.removeActive();
  } catch (_) {
    // A failure before the account was cleared leaves it signed in, so its
    // profile is left alone; one after it leaves the record for reconcile()
    // to drop on the next start. Either way the dialog has to come down, or
    // the user is stranded under a modal spinner.
    await dialog.hide();
    rethrow;
  }
  // Hide before navigating: the always-false predicate below would otherwise
  // take the dialog's route with it.
  await dialog.hide();
  if (navigator != null) {
    unawaited(navigator.pushNamedAndRemoveUntil('/', (route) => false));
  }
}
