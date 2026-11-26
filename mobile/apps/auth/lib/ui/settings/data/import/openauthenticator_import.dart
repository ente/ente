import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/openauthenticator_import_parser.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showOpenAuthenticatorImportInstruction(
  BuildContext context,
) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: 'Open Authenticator',
    body: l10n.importOpenAuthenticatorGuide,
    actionLabel: l10n.selectFile,
    semanticsIdentifier: 'auth_import_instruction_open_authenticator',
    onImport: () => _pickBackupFile(context),
  );
}

Future<void> _pickBackupFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.strings.selectFile,
    showProgressBeforeProcessing: false,
    logger: Logger('OpenAuthenticatorImport'),
    logMessage: 'Exception while processing Open Authenticator import',
    process: (path, progressDialog) =>
        _processBackup(context, path, progressDialog),
  );
}

Future<int?> _processBackup(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final backup = await readPickedImportFileAsString(path);
  runRustImport(() => rust.validateOpenAuthenticator(input: backup));
  while (true) {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.passwordForDecryptingExport,
    );
    if (password == null) return null;

    await dialog.show();
    try {
      final codes = await importOpenAuthenticatorExport(
        backup,
        password: password,
      );
      return await saveImportedCodes(codes);
    } on rust.ImportError_IncorrectPassword {
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.incorrectPasswordTitle,
        context.strings.pleaseCheckPasswordAndTryAgain,
      );
    }
  }
}
