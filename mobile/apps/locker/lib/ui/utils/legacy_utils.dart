import "package:ente_legacy/pages/create_legacy_kit_sheet.dart";
import "package:ente_legacy/pages/emergency_page.dart";
import "package:ente_legacy/pages/legacy_kit_intro_page.dart";
import "package:ente_legacy/services/legacy_kit_service.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/configuration.dart";
import "package:logging/logging.dart";

final _logger = Logger("LegacyUtils");

/// Opens the Legacy (Emergency contacts) page after authenticating the user.
Future<void> openLegacyPage(BuildContext context) async {
  await _openLegacy(context, showIntroWhenNoKits: false);
}

/// Opens Legacy from a home onboarding entrypoint.
///
/// Users without a Legacy kit see the intro before setup. Users with an
/// existing kit continue to the regular Legacy management page.
Future<void> openLegacyFromHome(BuildContext context) async {
  await _openLegacy(context, showIntroWhenNoKits: true);
}

Future<void> _openLegacy(
  BuildContext context, {
  required bool showIntroWhenNoKits,
}) async {
  var hasAuthenticatedForLegacyFlow = await _authenticateForLegacyFlow(
    context,
    context.l10n.authToManageLegacy,
  );
  if (!hasAuthenticatedForLegacyFlow || !context.mounted) {
    return;
  }

  final config = Configuration.instance;
  Future<bool> legacyKitAuthenticator(
    BuildContext context,
    String reason,
  ) async {
    if (hasAuthenticatedForLegacyFlow) {
      return true;
    }
    hasAuthenticatedForLegacyFlow = await _authenticateForLegacyFlow(
      context,
      reason,
    );
    return hasAuthenticatedForLegacyFlow;
  }

  if (showIntroWhenNoKits && await hasLegacyKit() == false) {
    if (!context.mounted) {
      return;
    }
    final shouldStart = await showLegacyKitIntroPage(context);
    if (!shouldStart || !context.mounted) {
      return;
    }
    await showCreateLegacyKitPage(
      context,
      accountEmail: config.getEmail() ?? "",
      isFirstLegacyKit: true,
      authenticator: legacyKitAuthenticator,
    );
    return;
  }

  if (!context.mounted) {
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (BuildContext context) {
        return EmergencyPage(
          config: config,
          legacyKitAuthenticator: legacyKitAuthenticator,
        );
      },
    ),
  );
}

Future<bool?> hasLegacyKit() async {
  if (!LegacyKitService.instance.isInitialized) {
    return null;
  }
  try {
    return (await LegacyKitService.instance.getKits()).isNotEmpty;
  } catch (e, s) {
    _logger.warning("Failed to fetch legacy kits", e, s);
    return null;
  }
}

Future<bool> _authenticateForLegacyFlow(BuildContext context, String reason) {
  return LocalAuthenticationService.instance.requestLocalAuthentication(
    context,
    reason,
    useDebugAuthCache: false,
  );
}
