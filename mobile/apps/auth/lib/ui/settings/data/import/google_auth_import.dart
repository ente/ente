import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/scanner_gauth_page.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_migration_tracker.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';
import 'package:ente_auth/ui/settings/data/import/import_instruction_sheet.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/gallery_import_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

export 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';

final _migrationTracker = GoogleAuthMigrationTracker();

Future<bool> showGoogleAuthInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final isMobile = PlatformDetector.isMobile();
  final result = await showImportInstructionSheet(
    context: context,
    title: "Google Authenticator",
    body: l10n.importGoogleAuthGuide,
    cancelLabel: l10n.cancel,
    semanticsIdentifier: 'auth_import_instruction_google_authenticator',
    actions: [
      if (isMobile)
        ImportInstructionAction(
          label: l10n.scanAQrCode,
          result: ImportInstructionResult.primary,
        ),
      ImportInstructionAction(
        label: l10n.selectFile,
        result: ImportInstructionResult.secondary,
        variant: isMobile
            ? ButtonComponentVariant.secondary
            : ButtonComponentVariant.primary,
      ),
    ],
  );
  if (result == null) {
    return false;
  }
  if (!context.mounted) return false;
  switch (result) {
    case ImportInstructionResult.primary:
      final GoogleAuthMigration? migration = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const ScannerGoogleAuthPage();
          },
        ),
      );
      if (!context.mounted || migration == null || migration.codes.isEmpty) {
        return false;
      }
      return _completeGoogleAuthImport(context, migration);
    case ImportInstructionResult.secondary:
      return _importGoogleAuthFromImage(context);
  }
}

Future<bool> _importGoogleAuthFromImage(BuildContext context) async {
  final importResult = await pickCodeFromImage(
    context,
    logger: Logger("GoogleAuthImport"),
    pickFromFiles: true,
  );
  if (importResult == null) {
    return false;
  }
  final migration = importResult.googleAuthMigration;
  if (migration == null || migration.codes.isEmpty) {
    if (!context.mounted) return false;
    await showErrorDialog(
      context,
      context.l10n.errorInvalidQRCode,
      context.l10n.errorInvalidQRCodeBody,
    );
    return false;
  }
  if (!context.mounted) return false;
  final shouldImport = await confirmGoogleAuthImport(
    context,
    migration.codes.length,
  );
  if (!shouldImport || !context.mounted) {
    return false;
  }
  return _completeGoogleAuthImport(context, migration);
}

Future<bool> _completeGoogleAuthImport(
  BuildContext context,
  GoogleAuthMigration migration,
) async {
  final importedCount = await importGoogleAuthCodes(migration.codes);
  if (!context.mounted) return false;
  await importSuccessDialog(context, importedCount);
  return _migrationTracker.record(migration);
}

Future<bool> confirmGoogleAuthImport(
  BuildContext context,
  int codeCount,
) async {
  final l10n = context.l10n;
  final result = await showImportInstructionSheet(
    context: context,
    title: "Google Authenticator",
    body: l10n.importGoogleAuthConfirmation(codeCount),
    cancelLabel: l10n.cancel,
    semanticsIdentifier: 'auth_import_confirm_google_authenticator',
    actions: [
      ImportInstructionAction(
        label: l10n.importLabel,
        result: ImportInstructionResult.primary,
      ),
    ],
  );
  return result == ImportInstructionResult.primary;
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
