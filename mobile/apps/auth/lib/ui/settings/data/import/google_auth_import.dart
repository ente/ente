import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/scanner_gauth_page.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/gallery_import_util.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

export 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';

Future<void> showGoogleAuthInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final isMobile = PlatformDetector.isMobile();
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("Google Authenticator"),
    body: l10n.importGoogleAuthGuide,
    buttons: [
      if (isMobile)
        ButtonWidget(
          buttonType: ButtonType.primary,
          labelText: l10n.scanAQrCode,
          isInAlert: true,
          buttonSize: ButtonSize.large,
          buttonAction: ButtonAction.first,
        ),
      ButtonWidget(
        buttonType: isMobile ? ButtonType.secondary : ButtonType.primary,
        labelText: l10n.importFromGallery,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.l10n.cancel,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
  final action = result?.action;
  if (action == null || action == ButtonAction.cancel) {
    return;
  }
  if (action == ButtonAction.first) {
    if (!context.mounted) return;
    final List<Code>? codes = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return const ScannerGoogleAuthPage();
        },
      ),
    );
    if (codes == null || codes.isEmpty) {
      return;
    }
    final importedCount = await importGoogleAuthCodes(codes);
    if (!context.mounted) return;
    // ignore: unawaited_futures
    importSuccessDialog(context, importedCount);
  } else if (action == ButtonAction.second) {
    if (!context.mounted) return;
    await _importGoogleAuthFromImage(context);
  }
}

Future<void> _importGoogleAuthFromImage(BuildContext context) async {
  final importResult = await pickCodeFromGallery(
    context,
    logger: Logger("GoogleAuthImport"),
  );
  if (importResult == null) {
    return;
  }
  final codes = importResult.googleAuthCodes;
  if (codes == null || codes.isEmpty) {
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.errorInvalidQRCode,
      context.l10n.errorInvalidQRCodeBody,
    );
    return;
  }
  if (!context.mounted) return;
  final shouldImport = await confirmGoogleAuthImport(context, codes.length);
  if (!shouldImport) {
    return;
  }
  final importedCount = await importGoogleAuthCodes(codes);
  if (!context.mounted) return;
  // ignore: unawaited_futures
  importSuccessDialog(context, importedCount);
}

Future<bool> confirmGoogleAuthImport(
  BuildContext context,
  int codeCount,
) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("Google Authenticator"),
    body: l10n.importGoogleAuthConfirmation(codeCount),
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: l10n.importLabel,
        isInAlert: true,
        buttonSize: ButtonSize.large,
        buttonAction: ButtonAction.first,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: l10n.cancel,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.cancel,
      ),
    ],
  );
  return result?.action == ButtonAction.first;
}

Future<int> importGoogleAuthCodes(List<Code> codes) async {
  int importedCount = 0;
  for (final code in codes) {
    final result = await CodeStore.instance.addCode(code, shouldSync: false);
    if (result != AddResult.duplicate) {
      importedCount++;
    }
  }
  if (importedCount > 0) {
    unawaited(AuthenticatorService.instance.onlineSync());
  }
  return importedCount;
}
