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

Future<void> show2FasImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "2FAS Authenticator",
    body: l10n.import2FasGuide,
    actionLabel: l10n.importSelectAppExport(appName: "2FAS Authenticator"),
    semanticsIdentifier: 'auth_import_instruction_two_fas',
    onImport: () => _pick2FasFile(context),
  );
}

Future<void> _pick2FasFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.strings.importSelectJsonFile,
    showProgressBeforeProcessing: false,
    logger: Logger('2FASImport'),
    logMessage: 'Exception while processing 2FAS import',
    process: (path, progressDialog) =>
        _process2FasExportFile(context, path, progressDialog),
  );
}

Future<int?> _process2FasExportFile(
  BuildContext context,
  String path,
  final ProgressDialog dialog,
) async {
  final export = await readPickedImportFileAsString(path);
  late rust.ImportBatch batch;
  try {
    batch = await runRustImportAsync(() => rust.importTwoFas(input: export));
    await dialog.show();
  } on rust.ImportError_PasswordRequired {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.enterPasswordToDecrypt2FASBackup,
    );
    if (password == null) {
      await dialog.hide();
      return null;
    }
    await dialog.show();
    try {
      batch = await runRustImportAsync(
        () => rust.importTwoFas(input: export, password: password),
      );
    } on rust.ImportError_IncorrectPassword catch (e, s) {
      Logger("2FASImport").warning("exception while decrypting  backup", e, s);
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.failedToDecrypt2FASExport,
        context.strings.pleaseCheckPasswordAndTryAgain,
      );
      return null;
    }
  }
  return saveImportedCodes(importCodes(batch));
}
