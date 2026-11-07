import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showAegisImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "Aegis Authenticator",
    body: l10n.importAegisGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_aegis',
    onImport: () => _pickAegisJsonFile(context),
  );
}

Future<void> _pickAegisJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.strings.importSelectJsonFile,
    logger: Logger('AegisImport'),
    logMessage: 'Exception while processing Aegis import',
    process: (path, progressDialog) =>
        _processAegisExportFile(context, path, progressDialog),
  );
}

Future<int?> _processAegisExportFile(
  BuildContext context,
  String path,
  final ProgressDialog dialog,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  late rust.ImportBatch batch;
  try {
    batch = await runRustImportAsync(() => rust.importAegis(input: jsonString));
  } on rust.ImportError_PasswordRequired {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.enterPasswordToAegisVault,
    );
    if (password == null) {
      await dialog.hide();
      return null;
    }
    await dialog.show();
    try {
      batch = await runRustImportAsync(
        () => rust.importAegis(input: jsonString, password: password),
      );
    } on rust.ImportError_IncorrectPassword catch (e, s) {
      Logger(
        "AegisImport",
      ).warning("exception while decrypting aegis vault", e, s);
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.failedToDecryptAegisVault,
        context.strings.pleaseCheckPasswordAndTryAgain,
      );
      return null;
    }
  }
  return saveImportedCodes(importCodes(batch));
}
