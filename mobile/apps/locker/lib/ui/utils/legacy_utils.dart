import "package:ente_events/event_bus.dart";
import "package:ente_legacy/events/legacy_kit_created_event.dart";
import "package:ente_legacy/models/legacy_kit_models.dart";
import "package:ente_legacy/pages/create_legacy_kit_sheet.dart";
import "package:ente_legacy/pages/emergency_page.dart";
import "package:ente_legacy/pages/legacy_kit_intro_page.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:locker/services/authenticated_session.dart";
import "package:locker/services/configuration.dart";
import "package:locker/services/legacy_kit.dart" as legacy;
import "package:logging/logging.dart";

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
      createKit: _createLegacyKit,
      getKits: _getLegacyKits,
      downloadShares: _downloadLegacyKitShares,
      updateRecoveryNotice: _updateLegacyKitRecoveryNotice,
      blockRecovery: _blockLegacyKitRecovery,
      deleteKit: _deleteLegacyKit,
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
          getLegacyKits: _getLegacyKits,
          createLegacyKit: _createLegacyKit,
          downloadLegacyKitShares: _downloadLegacyKitShares,
          updateLegacyKitRecoveryNotice: _updateLegacyKitRecoveryNotice,
          blockLegacyKitRecovery: _blockLegacyKitRecovery,
          deleteLegacyKit: _deleteLegacyKit,
          legacyKitAuthenticator: legacyKitAuthenticator,
        );
      },
    ),
  );
}

Future<bool?> hasLegacyKit() async {
  try {
    return (await _getLegacyKits()).isNotEmpty;
  } catch (e, s) {
    _logger.warning("Failed to fetch legacy kits", e, s);
    return null;
  }
}

Future<List<LegacyKit>> _getLegacyKits() =>
    legacy.kits(session: authenticatedSession());

Future<LegacyKitCreateResult> _createLegacyKit(
  List<String> partNames,
  int noticePeriodInHours,
) async {
  final keyAttributes = Configuration.instance.getKeyAttributes();
  if (keyAttributes == null) {
    throw StateError("Missing account key attributes");
  }
  final result = await legacy.createKit(
    session: authenticatedSession(),
    currentUserKeyAttrs: keyAttributes,
    partNames: partNames,
    noticePeriodInHours: noticePeriodInHours,
  );
  Bus.instance.fire(LegacyKitCreatedEvent());
  return result;
}

Future<List<LegacyKitShare>> _downloadLegacyKitShares(String kitId) =>
    legacy.downloadKitShares(session: authenticatedSession(), kitId: kitId);

Future<void> _updateLegacyKitRecoveryNotice(
  String kitId,
  int noticePeriodInHours,
) => legacy.updateKitRecoveryNotice(
  session: authenticatedSession(),
  kitId: kitId,
  noticePeriodInHours: noticePeriodInHours,
);

Future<void> _blockLegacyKitRecovery(String kitId) =>
    legacy.blockKitRecovery(session: authenticatedSession(), kitId: kitId);

Future<void> _deleteLegacyKit(String kitId) =>
    legacy.deleteKit(session: authenticatedSession(), kitId: kitId);

Future<bool> _authenticateForLegacyFlow(BuildContext context, String reason) {
  return LocalAuthenticationService.instance.requestLocalAuthentication(
    context,
    reason,
    useDebugAuthCache: false,
  );
}
