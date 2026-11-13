import 'dart:async';

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
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

export 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';

final _logger = Logger('GoogleAuthImport');

Future<bool> showGoogleAuthInstruction(BuildContext context) async {
  final l10n = context.strings;
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
      final List<Code>? codes = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (BuildContext context) {
            return const ScannerGoogleAuthPage();
          },
        ),
      );
      if (!context.mounted || codes == null || codes.isEmpty) {
        return false;
      }
      return _completeGoogleAuthImport(context, codes);
    case ImportInstructionResult.secondary:
      return _importGoogleAuthFromImage(context);
  }
}

Future<bool> _importGoogleAuthFromImage(BuildContext context) async {
  if (!context.mounted) return false;
  final importResult = await pickCodeFromImage(
    context,
    logger: _logger,
    pickFromFiles: true,
  );
  if (importResult == null || !context.mounted) return false;
  final codes = await collectGoogleAuthImageBatches(
    context,
    importResult.googleAuthMigration,
    logger: _logger,
    pickFromFiles: true,
  );

  if (!context.mounted || codes == null) return false;
  return _completeGoogleAuthImport(context, codes);
}

Future<List<Code>?> collectGoogleAuthImageBatches(
  BuildContext context,
  GoogleAuthMigration? migration, {
  required Logger logger,
  bool pickFromFiles = false,
  GoogleAuthMigrationTracker? tracker,
}) async {
  final migrationTracker = tracker ?? GoogleAuthMigrationTracker();
  while (true) {
    final currentMigration = migration;
    if (currentMigration == null || currentMigration.codes.isEmpty) {
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.invalidQRCode,
        context.strings.errorInvalidQRCodeBody,
      );
      return null;
    }

    try {
      final codes = migrationTracker.add(currentMigration);
      if (codes != null) return codes;
    } on FormatException catch (error) {
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.invalidQRCode,
        error.message,
      );
      return null;
    }

    if (!context.mounted) return null;
    final result = await showImportInstructionSheet(
      context: context,
      title: 'Google Authenticator',
      body:
          '${context.strings.selectFile} '
          '(${migrationTracker.receivedBatchCount}/${migrationTracker.batchSize})',
      cancelLabel: context.strings.cancel,
      semanticsIdentifier: 'auth_import_google_authenticator_next_file',
      actions: [
        ImportInstructionAction(
          label: context.strings.selectFile,
          result: ImportInstructionResult.primary,
        ),
      ],
    );
    if (result != ImportInstructionResult.primary || !context.mounted) {
      return null;
    }
    final importResult = await pickCodeFromImage(
      context,
      logger: logger,
      pickFromFiles: pickFromFiles,
    );
    if (importResult == null) return null;
    migration = importResult.googleAuthMigration;
  }
}

Future<bool> _completeGoogleAuthImport(
  BuildContext context,
  List<Code> codes,
) async {
  int? importedCount;
  final shouldImport = await confirmGoogleAuthImport(
    context,
    codes.length,
    onImport: () async {
      try {
        importedCount = await importGoogleAuthCodes(codes);
      } catch (error, stackTrace) {
        _logger.severe(
          'Failed to import Google Authenticator codes',
          error,
          stackTrace,
        );
        if (context.mounted) {
          await showGenericErrorDialog(context: context, error: error);
        }
        rethrow;
      }
    },
  );
  final count = importedCount;
  if (!shouldImport || count == null || !context.mounted) return false;
  await importSuccessDialog(context, count);
  return true;
}

Future<bool> confirmGoogleAuthImport(
  BuildContext context,
  int codeCount, {
  FutureOr<void> Function()? onImport,
}) async {
  final l10n = context.strings;
  final result = await showImportInstructionSheet(
    context: context,
    title: "Google Authenticator",
    body: l10n.importGoogleAuthConfirmation(codeCount: codeCount),
    cancelLabel: l10n.cancel,
    semanticsIdentifier: 'auth_import_confirm_google_authenticator',
    actions: [
      ImportInstructionAction(
        label: l10n.importLabel,
        result: ImportInstructionResult.primary,
        onTap: onImport,
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
