import "package:ente_legacy/pages/create_legacy_kit_sheet.dart";
import "package:ente_legacy/pages/emergency_page.dart";
import "package:ente_legacy/pages/legacy_kit_intro_page.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/legacy_api.dart";
import "package:logging/logging.dart";

const _legacy = LockerLegacyApi();

final _logger = Logger("LegacyUtils");

Future<void> openLegacyPage(BuildContext context) async {
  await _openLegacy(context, showIntroWhenNoKits: false);
}

Future<void> openLegacyFromHome(BuildContext context) async {
  await _openLegacy(context, showIntroWhenNoKits: true);
}

Future<void> _openLegacy(
  BuildContext context, {
  required bool showIntroWhenNoKits,
}) async {
  var hasAuthenticatedForLegacyFlow = await _authenticateForLegacyFlow(
    context,
    context.strings.authToManageLegacy,
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
      legacy: _legacy,
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
          legacy: _legacy,
          legacyKitAuthenticator: legacyKitAuthenticator,
        );
      },
    ),
  );
}

Future<bool?> hasLegacyKit() async {
  try {
    return (await _legacy.kits()).isNotEmpty;
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
